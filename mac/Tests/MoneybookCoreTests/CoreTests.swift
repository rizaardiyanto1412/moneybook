import Foundation
import Testing
@testable import MoneybookCore

private func tx(_ id: String, _ type: TxType, _ date: String, _ amount: Double, account: String = "cash", to: String? = nil,
                category: String? = nil, updated: Int64 = 1, created: Int64 = 1) -> Transaction {
    Transaction(id: id, type: type, date: date, amount: amount, accountId: account, toAccountId: to, categoryId: category,
                createdAt: created, updatedAt: updated)
}

private func snapshot() -> Snapshot {
    var s = Snapshot()
    s.accounts = ["cash": Account(id: "cash", groupId: "g", name: "Cash", initialBalance: 100),
                  "bank": Account(id: "bank", groupId: "g", name: "Bank", initialBalance: 1000),
                  "card": Account(id: "card", groupId: "g2", name: "Card")]
    s.categories = ["food": Category(id: "food", type: .expense, name: "Food", icon: "🍜", sort: 0),
                    "lunch": Category(id: "lunch", type: .expense, name: "Lunch", parentId: "food"),
                    "transport": Category(id: "transport", type: .expense, name: "Transport", icon: "🚖", sort: 1),
                    "salary": Category(id: "salary", type: .income, name: "Salary", icon: "💼")]
    for t in [tx("1", .expense, "2026-10-03T12:00", 10, category: "lunch"),
              tx("2", .expense, "2026-10-03T18:00", 30, account: "card", category: "food"),
              tx("3", .expense, "2026-10-05T08:00", 20, category: "transport"),
              tx("4", .income, "2026-10-01T09:00", 500, account: "bank", category: "salary"),
              tx("5", .transfer, "2026-10-02T09:00", 200, account: "bank", to: "cash"),
              tx("6", .expense, "2026-09-30T09:00", 99, category: "food")] {
        s.transactions[t.id] = t
    }
    return s
}

@Suite struct SyncMergeTests {
    @Test func upsertsAndDropsTombstones() {
        var s = snapshot()
        var deleted = s.transactions["1"]!
        deleted.deleted = true
        deleted.updatedAt = 5
        var edited = s.transactions["2"]!
        edited.amount = 31
        edited.updatedAt = 5
        let new = tx("9", .expense, "2026-10-10T10:00", 7, updated: 5)
        let changed = s.merge(SyncResponse(cursor: 5, transactions: [deleted, edited, new], settings: ["currency": "EUR"]))
        #expect(changed)
        #expect(s.transactions["1"] == nil)
        #expect(s.transactions["2"]?.amount == 31)
        #expect(s.transactions["9"] != nil)
        #expect(s.cursor == 5)
        #expect(s.currency == "EUR")
    }

    @Test func repeatedRowsAtCursorAreHarmless() {
        var s = snapshot()
        let row = tx("9", .expense, "2026-10-10T10:00", 7, updated: 5)
        s.merge(SyncResponse(cursor: 5, transactions: [row]))
        let changed = s.merge(SyncResponse(cursor: 5, transactions: [row]))
        #expect(!changed)
        #expect(s.transactions.count == 7)
    }

    @Test func olderRowDoesNotOverwriteNewer() {
        var s = snapshot()
        var newer = s.transactions["3"]!
        newer.amount = 25
        newer.updatedAt = 10
        s.upsert(newer)
        var stale = newer
        stale.amount = 1
        stale.updatedAt = 9
        s.merge(SyncResponse(cursor: 10, transactions: [stale]))
        #expect(s.transactions["3"]?.amount == 25)
    }

    @Test func cursorNeverGoesBackwards() {
        var s = Snapshot()
        s.merge(SyncResponse(cursor: 50))
        s.merge(SyncResponse(cursor: 20))
        #expect(s.cursor == 50)
    }

    @Test func decodesServerJSON() throws {
        let json = """
        {"cursor":1791828507054,"account_groups":[{"id":"g","name":"Cash","kind":"asset","sort":0,"updated_at":1,"deleted":0}],
         "accounts":[{"id":"a","group_id":"g","name":"Cash","initial_balance":12.5,"currency":null,"include_in_totals":1,"hidden":0,"note":"","sort":0,"updated_at":1,"deleted":0}],
         "categories":[{"id":"c","type":"expense","name":"Food","icon":"🍜","parent_id":null,"sort":0,"updated_at":1,"deleted":0}],
         "transactions":[{"id":"t","type":"expense","date":"2026-10-12T18:08","amount":12.4,"account_id":"a","to_account_id":null,"category_id":"c","note":"Chipotle","description":"Bowl","receipt":null,"source":"ai","created_at":1,"updated_at":2,"deleted":0,"account_name":"Cash"}],
         "budgets":[{"id":"b","category_id":null,"month":null,"amount":2500,"updated_at":1,"deleted":0}],
         "settings":{"currency":"USD","week_start":"1","month_start_day":"25"}}
        """
        let r = try JSONDecoder().decode(SyncResponse.self, from: Data(json.utf8))
        var s = Snapshot()
        s.merge(r)
        #expect(s.cursor == 1791828507054)
        #expect(s.transactions["t"]?.memo == "Bowl")
        #expect(s.transactions["t"]?.isAI == true)
        #expect(s.accounts["a"]?.initialBalance == 12.5)
        #expect(s.accounts["a"]?.includeInTotals == true)
        #expect(s.firstWeekday == 2)
        #expect(s.monthStartDay == 25)
    }

    @Test func cacheRoundTrips() throws {
        let s = snapshot()
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Snapshot.self, from: data)
        #expect(back == s)
    }
}

@Suite struct PeriodTests {
    @Test func calendarMonth() {
        let p = Periods.month(YearMonth(year: 2026, month: 2))
        #expect(p.from == "2026-02-01")
        #expect(p.to == "2026-02-28")
    }

    @Test func customMonthStartDayBelow20() {
        let p = Periods.month(YearMonth(year: 2026, month: 3), startDay: 10)
        #expect(p == Period(from: "2026-03-10", to: "2026-04-09"))
        #expect(Periods.yearMonth(containing: "2026-04-09", startDay: 10) == YearMonth(year: 2026, month: 3))
        #expect(Periods.yearMonth(containing: "2026-04-10", startDay: 10) == YearMonth(year: 2026, month: 4))
    }

    @Test func customMonthStartDayNamedAfterEndMonth() {
        // S >= 20: the period is named after the month it ends in.
        #expect(Periods.month(YearMonth(year: 2026, month: 3), startDay: 25) == Period(from: "2026-02-25", to: "2026-03-24"))
        #expect(Periods.month(YearMonth(year: 2027, month: 1), startDay: 25) == Period(from: "2026-12-25", to: "2027-01-24"))
        #expect(Periods.yearMonth(containing: "2026-10-24", startDay: 25) == YearMonth(year: 2026, month: 10))
        #expect(Periods.yearMonth(containing: "2026-10-25", startDay: 25) == YearMonth(year: 2026, month: 11))
        // Every day maps back to the period that contains it.
        for day in Periods.days(from: "2026-01-01", to: "2026-12-31") {
            for s in [1, 10, 20, 25, 28] {
                #expect(Periods.month(Periods.yearMonth(containing: day, startDay: s), startDay: s).contains(day))
            }
        }
    }

    @Test func yearMonthArithmetic() {
        #expect(YearMonth(year: 2026, month: 1).adding(months: -1) == YearMonth(year: 2025, month: 12))
        #expect(YearMonth(year: 2026, month: 12).adding(months: 1).key == "2027-01")
        #expect(YearMonth(year: 2026, month: 3).adding(months: -27).key == "2023-12")
    }

    @Test func weeksStartOnConfiguredDay() {
        // October 2026 starts on a Thursday.
        let oct = Periods.month(YearMonth(year: 2026, month: 10))
        let sundayWeeks = Periods.weeks(in: oct, firstWeekday: 1)
        #expect(sundayWeeks.first == Period(from: "2026-10-01", to: "2026-10-03"))
        #expect(sundayWeeks[1] == Period(from: "2026-10-04", to: "2026-10-10"))
        #expect(sundayWeeks.last?.to == "2026-10-31")
        let mondayWeeks = Periods.weeks(in: oct, firstWeekday: 2)
        #expect(mondayWeeks.first == Period(from: "2026-10-01", to: "2026-10-04"))
        #expect(mondayWeeks.reduce(0) { $0 + $1.days.count } == 31)
    }

    @Test func calendarGridPadding() {
        let cells = Periods.calendarGrid(Periods.month(YearMonth(year: 2026, month: 10)), firstWeekday: 1)
        #expect(cells.count % 7 == 0)
        #expect(cells.prefix(4).allSatisfy { $0 == nil })
        #expect(cells[4] == "2026-10-01")
    }

    @Test func stampRoundTrip() {
        let tz = TimeZone(identifier: "Asia/Jakarta")!
        let d = Periods.parseStamp("2026-10-13T07:45", timeZone: tz)!
        #expect(Periods.localStamp(d, timeZone: tz) == "2026-10-13T07:45")
    }
}

@Suite struct LedgerTests {
    let s = snapshot()
    let oct = Periods.month(YearMonth(year: 2026, month: 10))

    @Test func totalsIgnoreTransfers() {
        let t = Ledger.totals(Ledger.transactions(in: oct, s))
        #expect(t.income == 500)
        #expect(t.expense == 60)
        #expect(t.total == 440)
    }

    @Test func groupsByDayNewestFirst() {
        let groups = Ledger.groupByDay(Ledger.transactions(in: oct, s))
        #expect(groups.map(\.day) == ["2026-10-05", "2026-10-03", "2026-10-02", "2026-10-01"])
        #expect(groups[1].transactions.map(\.id) == ["2", "1"])
        #expect(groups[1].totals.expense == 40)
    }

    @Test func categoriesRollUpToParent() {
        let slices = Ledger.byCategory(Ledger.transactions(in: oct, s), type: .expense, s)
        #expect(slices.map(\.id) == ["food", "transport"])
        #expect(slices[0].total == 40)
        #expect(abs(slices[0].percent - 66.666) < 0.01)
        let subs = Ledger.bySubcategory(Ledger.transactions(in: oct, s), parentId: "food", s)
        #expect(Set(subs.map(\.id)) == ["food", "lunch"])
    }

    @Test func balancesAndRunningBalance() {
        let b = Ledger.balances(s)
        #expect(b["cash"] == 171.0) // 100 - 10 - 20 + 200 - 99
        #expect(b["bank"] == 1300.0) // 1000 + 500 - 200
        #expect(b["card"] == -30)
        let summary = Ledger.balanceSummary(s, balances: b)
        #expect(summary.liabilities == 30)
        let running = Ledger.runningBalances(accountId: "cash", s)
        #expect(running["6"] == 1)    // 100 - 99
        #expect(running["5"] == 201)  // + 200 transfer in
        #expect(running["3"] == 171)
    }

    @Test func monthBudgetOverridesDefault() {
        var s = s
        s.budgets = ["d": Budget(id: "d", categoryId: "food", month: nil, amount: 100),
                     "o": Budget(id: "o", categoryId: "food", month: "2026-10", amount: 50),
                     "t": Budget(id: "t", categoryId: nil, month: nil, amount: 1000)]
        let lines = Ledger.budgetLines(s, month: YearMonth(year: 2026, month: 10))
        #expect(lines[0].name == "Total" && lines[0].budget == 1000 && lines[0].spent == 60)
        let food = lines.first { $0.categoryId == "food" }!
        #expect(food.budget == 50 && food.spent == 40 && food.isMonthOverride)
        let sept = Ledger.budgetLines(s, month: YearMonth(year: 2026, month: 9)).first { $0.categoryId == "food" }!
        #expect(sept.budget == 100 && sept.spent == 99)
    }

    @Test func totalFallsBackToSumOfCategoryBudgets() {
        var s = s
        s.budgets = ["f": Budget(id: "f", categoryId: "food", month: nil, amount: 100),
                     "t": Budget(id: "t", categoryId: "transport", month: nil, amount: 50)]
        let total = Ledger.budgetLines(s, month: YearMonth(year: 2026, month: 10))[0]
        #expect(total.budget == 150 && total.isSynthetic)
    }

    @Test func searchMatchesNoteAndDescription() {
        var t = s.transactions["1"]!
        t.note = "Sweetgreen"
        t.memo = "kale salad"
        #expect(Ledger.matches(t, query: "sweet", s))
        #expect(Ledger.matches(t, query: "KALE", s))
        #expect(!Ledger.matches(t, query: "pizza", s))
    }

    @Test func monthlyTrend() {
        let trend = Ledger.monthlyTrend(s, endingAt: YearMonth(year: 2026, month: 10), count: 2)
        #expect(trend.count == 2)
        #expect(trend[0].1.expense == 99)
        #expect(trend[1].1.income == 500)
    }
}

@Suite struct MoneyTests {
    let us = Locale(identifier: "en_US")

    @Test func formatsWithCurrency() {
        #expect(Money.format(1234.5, currency: "USD", locale: us) == "$1,234.50")
        #expect(Money.format(1234.5, currency: "usd", symbol: false, locale: us) == "1,234.50")
        #expect(Money.format(1500, currency: "JPY", locale: us) == "¥1,500")
        #expect(Money.format(-12, currency: "USD", locale: us).contains("12.00"))
    }

    @Test func parsesInput() {
        #expect(Money.parse("1,234.5", locale: us) == 1234.5)
        #expect(Money.parse("12,50", locale: us) == 12.5)
        #expect(Money.parse("$ 3", locale: us) == 3)
        #expect(Money.parse("", locale: us) == nil)
        #expect(Money.parse("1.234,5", locale: Locale(identifier: "de_DE")) == 1234.5)
    }
}
