import AppKit
import MoneybookCore
import SwiftUI

/// Development aid: `Moneybook -snapshotDir /tmp/shots` walks the main screens and writes PNGs of the
/// app's own windows (rendered in-process, so it works without Screen Recording permission or an
/// unlocked display), then quits. Add `-snapshotWaitForAI 1` to also wait for an AI-added row.
enum SnapshotRunner {
    static var directory: URL? {
        UserDefaults.standard.string(forKey: "snapshotDir").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(model: AppModel, dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Wait for the first sync.
        for _ in 0..<60 where model.connection != .online { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .seconds(1))
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true || $0.title == "Moneybook" }) else {
            print("snapshot: no main window among", NSApp.windows.map { "\($0.identifier?.rawValue ?? "-") \($0.title) visible=\($0.isVisible)" }); NSApp.terminate(nil); return
        }
        window.setContentSize(NSSize(width: 1200, height: 780))

        func shot(_ name: String, delay: Double = 1.2, sheet: Bool = false) async {
            try? await Task.sleep(for: .seconds(delay))
            let target = sheet ? (window.attachedSheet ?? window) : window
            save(target, to: dir.appendingPathComponent("\(name).png"))
        }

        model.section = .transactions
        model.transactionsMode = .daily
        await shot("01-transactions-daily")
        model.transactionsMode = .calendar
        await shot("02-transactions-calendar")
        model.transactionsMode = .weekly
        await shot("02b-transactions-weekly")
        model.transactionsMode = .monthly
        await shot("03-transactions-monthly")
        model.transactionsMode = .summary
        await shot("04-transactions-summary")
        model.transactionsMode = .daily
        model.open(.search)
        await shot("05-search")
        model.drawers = []

        model.section = .stats
        model.statsMode = .stats
        await shot("06-stats")
        if let top = Ledger.byCategory(Ledger.transactions(in: model.period, model.snapshot), type: .expense, model.snapshot).first {
            model.open(.category(top.id.isEmpty ? nil : top.id, .expense, model.period, Fmt.monthLabel(model.month)))
            await shot("07-stats-category")
            model.drawers = []
        }
        model.statsMode = .note
        await shot("07b-stats-note")
        model.statsMode = .budget
        await shot("10-budget")
        model.statsMode = .stats

        model.section = .accounts
        await shot("08-accounts")
        if let acc = model.snapshot.sortedAccounts.first {
            model.open(.account(acc.id))
            await shot("09-account-detail")
            model.drawers = []
        }

        model.section = .settings
        await shot("11-settings")
        model.open(.configuration)
        await shot("11b-settings-configuration")
        model.drawers = []

        model.section = .transactions
        model.newTransaction()
        await shot("12-editor-new", delay: 1.5, sheet: true)
        model.editor = nil
        try? await Task.sleep(for: .seconds(0.8))
        // Type "12+34" on the keyboard, the last two digits on the numeric keypad.
        model.newTransaction()
        try? await Task.sleep(for: .seconds(1))
        for (ch, code, pad) in [("1", 18, false), ("2", 19, false), ("+", 69, true), ("3", 85, true), ("4", 86, true)] {
            if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: pad ? .numericPad : [], timestamp: 0,
                                        windowNumber: window.windowNumber, context: nil, characters: ch,
                                        charactersIgnoringModifiers: ch, isARepeat: false, keyCode: UInt16(code)) {
                NSApp.postEvent(e, atStart: false)
            }
        }
        await shot("12d-editor-typed", delay: 1)
        model.editor = EditorRequest(transactionId: nil, startPanel: .category)
        await shot("12b-editor-category", delay: 1.5)
        model.editor = EditorRequest(transactionId: nil, startPanel: .account)
        await shot("12c-editor-account", delay: 1.5)
        model.editor = nil
        try? await Task.sleep(for: .seconds(0.8))
        let s = model.snapshot
        if let tx = s.transactions.values.filter({ $0.isAI }).max(by: { $0.createdAt < $1.createdAt })
            ?? s.transactions.values.first(where: { s.categories[$0.categoryId ?? ""]?.parentId != nil }) {
            model.edit(tx.id)
            await shot("13-editor-edit", delay: 1.5, sheet: true)
            model.editor = nil
            try? await Task.sleep(for: .seconds(0.8))
        }
        let transfer = s.transactions.values.first { $0.type == .transfer }
        if let transfer {
            model.edit(transfer.id)
            await shot("14-editor-transfer", delay: 1.5, sheet: true)
            model.editor = nil
            try? await Task.sleep(for: .seconds(0.8))
        }

        NSApp.appearance = NSAppearance(named: .darkAqua)
        await shot("15-dark-daily")
        model.section = .stats
        await shot("16-dark-stats")
        NSApp.appearance = nil

        NSApp.appearance = NSAppearance(named: .aqua)
        model.section = .transactions
        await shot("15b-light-daily")
        model.section = .stats
        await shot("16b-light-stats")
        model.statsMode = .budget
        await shot("16c-light-budget")
        model.statsMode = .stats
        NSApp.appearance = nil

        renderMenuBar(model: model, to: dir.appendingPathComponent("17-menubar.png"))

        if UserDefaults.standard.bool(forKey: "snapshotWaitForAI") {
            // Something outside (the test script) adds an AI transaction via MCP; the poll loop should pick it up.
            model.section = .transactions
            let before = Set(model.snapshot.transactions.keys)
            print("snapshot: waiting for AI transaction")
            FileManager.default.createFile(atPath: dir.appendingPathComponent("ready").path, contents: nil)
            let start = Date()
            while Date().timeIntervalSince(start) < 40 {
                if model.snapshot.transactions.values.contains(where: { !before.contains($0.id) && $0.isAI }) { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            print(String(format: "snapshot: AI transaction visible after %.1fs", Date().timeIntervalSince(start)))
            await shot("18-ai-arrived", delay: 0.8)
        }
        print("snapshot: done")
        NSApp.terminate(nil)
    }

    static func save(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("snapshot: \(url.lastPathComponent)")
    }

    static func renderMenuBar(model: AppModel, to url: URL) {
        let host = NSHostingView(rootView: MenuBarView().environment(model))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        save(w, to: url)
    }
}

/// Development aid: `Moneybook -selfTest 1` runs every write path against the configured server
/// through `AppModel` (the same code the UI uses), prints PASS/FAIL lines and quits.
enum SelfTest {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "selfTest") }

    static func run(model: AppModel) async {
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print("selftest: \(ok ? "PASS" : "FAIL") \(name)")
            if !ok { failures += 1 }
        }
        for _ in 0..<60 where model.connection != .online { try? await Task.sleep(for: .milliseconds(250)) }
        check("connected", model.connection == .online)
        let s = model.snapshot
        guard let cash = s.accounts.values.first(where: { $0.name == "Cash" }),
              let savings = s.accounts.values.first(where: { $0.name == "Savings" }),
              let food = s.topCategories(.expense).first(where: { $0.name == "Food" }),
              let lunch = s.subcategories(of: food.id).first(where: { $0.name == "Lunch" }) else {
            print("selftest: FAIL seed data missing"); NSApp.terminate(nil); return
        }
        do {
            var d = TransactionDraft()
            d.type = .expense; d.amount = 9.99; d.accountId = cash.id; d.categoryId = lunch.id
            d.note = "Selftest lunch"; d.memo = "line 1\nline 2"
            d.date = Periods.parseStamp("2026-10-05T12:34")!
            let created = try await model.save(d)
            check("create expense", created.amount == 9.99 && created.categoryId == lunch.id && created.date == "2026-10-05T12:34" && created.source == "app")
            check("create applied locally", model.snapshot.transactions[created.id]?.memo == "line 1\nline 2")

            let png = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in NSColor.systemRed.setFill(); r.fill(); return true }
            let receipt = PendingReceipt(image: png)!
            try await model.uploadReceipt(transactionId: created.id, data: receipt.data, mimeType: receipt.mimeType)
            let key = model.snapshot.transactions[created.id]?.receipt
            check("upload receipt", key?.hasPrefix("receipts/") == true)
            let img = await model.receiptImage(key ?? "")
            check("download receipt", img != nil)

            d.id = created.id; d.amount = 12.5; d.type = .income; d.categoryId = nil
            let edited = try await model.save(d)
            check("edit to income", edited.type == .income && edited.amount == 12.5 && edited.categoryId != nil)

            var t = TransactionDraft()
            t.type = .transfer; t.amount = 20; t.accountId = cash.id; t.toAccountId = savings.id
            let transfer = try await model.save(t)
            check("create transfer", transfer.toAccountId == savings.id && transfer.categoryId == nil)

            try await model.removeReceipt(transactionId: created.id)
            check("remove receipt", model.snapshot.transactions[created.id]?.receipt == nil)
            await model.delete(transactionIds: [created.id, transfer.id])
            check("delete", model.snapshot.transactions[created.id] == nil && model.snapshot.transactions[transfer.id] == nil)

            let month = YearMonth(year: 2026, month: 10)
            try await model.setBudget(categoryId: food.id, month: month, amount: 333)
            check("month budget override", Ledger.budgetLines(model.snapshot, month: month).first { $0.categoryId == food.id }?.budget == 333)
            try await model.setBudget(categoryId: food.id, month: month, amount: 0)
            await model.sync()
            check("remove override falls back to default", Ledger.budgetLines(model.snapshot, month: month).first { $0.categoryId == food.id }?.budget == 400)

            try await model.saveCategory(id: nil, type: .expense, name: "Selftest", icon: "🧪", parentId: food.id)
            let cat = model.snapshot.categories.values.first { $0.name == "Selftest" }
            check("create subcategory", cat?.parentId == food.id)
            if let cat {
                try await model.saveCategory(id: cat.id, type: .expense, name: "Selftest 2", icon: "🧫", parentId: nil)
                check("edit category", model.snapshot.categories[cat.id]?.name == "Selftest 2")
                try await model.deleteCategory(cat.id)
                check("delete category", model.snapshot.categories[cat.id] == nil)
            }

            try await model.saveAccount(id: nil, groupId: savings.groupId, name: "Selftest acct", initialBalance: -50, includeInTotals: false, hidden: true, note: "n")
            let acct = model.snapshot.accounts.values.first { $0.name == "Selftest acct" }
            check("create account", acct?.initialBalance == -50 && acct?.hidden == true && acct?.includeInTotals == false)
            if let acct {
                try await model.deleteAccount(acct.id)
                check("delete account", model.snapshot.accounts[acct.id] == nil)
            }

            try await model.saveGroup(id: nil, name: "Selftest group", kind: "liability")
            let group = model.snapshot.groups.values.first { $0.name == "Selftest group" }
            check("create group", group?.kind == "liability")
            if let group { try await model.deleteGroup(group.id) }

            let oldWeek = model.snapshot.settings["week_start"] ?? "0"
            try await model.updateSettings(["week_start": "1"])
            check("settings patch", model.snapshot.firstWeekday == 2)
            try await model.updateSettings(["week_start": oldWeek])

            let result = await model.testConnection(server: model.serverURL, token: "wrong")
            if case .failure(let e) = result { check("bad token rejected (\(e.localizedDescription))", true) } else { check("bad token rejected", false) }
        } catch {
            check("unexpected error: \(error.localizedDescription)", false)
        }
        print("selftest: \(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")")
        NSApp.terminate(nil)
    }
}
