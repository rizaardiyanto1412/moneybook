import MoneybookCore
import SwiftUI

struct AccountEditRequest: Identifiable {
    let id = UUID()
    var accountId: String?
}

/// Accounts tab: Assets / Liabilities / Total and grouped balances (web/js/views/accounts.js).
struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @UIState private var editing: AccountEditRequest?

    var body: some View {
        let s = model.snapshot
        let balances = Ledger.balances(s)
        let summary = Ledger.balanceSummary(s, balances: balances)
        let visible = s.sortedAccounts.filter { !$0.hidden }
        let hidden = s.sortedAccounts.filter(\.hidden)
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                MBHeader(title: "Accounts") {
                    EmptyView()
                } right: {
                    IconButton(symbol: "pencil", help: "Edit accounts") { model.open(.accountsAdmin) }
                    IconButton(symbol: "plus", help: "Add account") { editing = AccountEditRequest() }
                }
                Strip(items: [("Assets", summary.assets, MB.inc), ("Liabilities", summary.liabilities, MB.exp), ("Total", summary.total, MB.fg)])
            }
            .background(MB.chrome)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(s.sortedGroups) { g in
                        let items = visible.filter { $0.groupId == g.id }
                        if !items.isEmpty {
                            let sum = items.reduce(0) { $0 + (balances[$1.id] ?? 0) }
                            groupHeader(g.name, sum: sum)
                            ForEach(items) { row($0, balance: balances[$0.id] ?? 0) }
                        }
                    }
                    if !hidden.isEmpty {
                        groupHeader("Hidden", sum: nil)
                        ForEach(hidden) { row($0, balance: balances[$0.id] ?? 0, muted: true) }
                    }
                    if s.accounts.isEmpty { MBEmpty(text: "No accounts", emoji: "💳") }
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $editing) { AccountEditor(request: $0) }
    }

    private func groupHeader(_ name: String, sum: Double?) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(name).font(.system(size: 14)).foregroundStyle(MB.fg2)
            Spacer()
            if let sum { Text(model.money(sum)).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(sum < 0 ? MB.exp : MB.inc) }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(MB.bg2)
        .bottomLine()
    }

    private func row(_ a: Account, balance: Double, muted: Bool = false) -> some View {
        HStack {
            Text(a.name).foregroundStyle(muted ? MB.fg2 : MB.fg)
            if !a.includeInTotals { Text("(excluded)").font(.system(size: 12)).foregroundStyle(MB.fg2) }
            Spacer()
            Text(model.money(balance)).monospacedDigit().foregroundStyle(muted ? MB.fg2 : balance < 0 ? MB.exp : MB.inc)
        }
        .font(.system(size: 15))
        .padding(.horizontal, 24)
        .frame(minHeight: 52)
        .bottomLine()
        .rowHover()
        .onTapGesture { model.open(.account(a.id)) }
        .contextMenu {
            Button("Edit Account…") { editing = AccountEditRequest(accountId: a.id) }
        }
    }
}

/// One account's month: Deposit / Withdrawal / Balance and its day list, with an Add button.
struct AccountDetailView: View {
    @Environment(AppModel.self) private var model
    var accountId: String
    @UIState private var month: YearMonth?
    @UIState private var editing: AccountEditRequest?

    var body: some View {
        let s = model.snapshot
        let ym = month ?? model.month
        let p = Periods.month(ym, startDay: s.monthStartDay)
        let txs = Ledger.transactions(in: p, s).filter { $0.accountId == accountId || $0.toAccountId == accountId }
        let deposit = txs.reduce(0) { $0 + ($1.type == .income || ($1.type == .transfer && $1.toAccountId == accountId) ? $1.amount : 0) }
        let withdrawal = txs.reduce(0) { $0 + ($1.type == .income || ($1.type == .transfer && $1.toAccountId == accountId) ? 0 : $1.amount) }
        let balance = Ledger.balances(s)[accountId] ?? 0
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                DrawerHeader(title: s.accounts[accountId]?.name ?? "Deleted account") {
                    HeaderTextButton(title: "Edit") { editing = AccountEditRequest(accountId: accountId) }
                }
                MonthSwitcher(label: Fmt.monthLabel(ym), onPrev: { month = ym.adding(months: -1) }, onNext: { month = ym.adding(months: 1) },
                              onLabel: { month = model.currentMonth })
                Strip(items: [("Deposit", deposit, MB.inc), ("Withdrawal", withdrawal, MB.exp), ("Balance", balance, balance < 0 ? MB.exp : MB.fg)])
                ScrollView {
                    DayList(transactions: txs, accountId: accountId, addable: true, emptyText: "No transactions in \(Fmt.monthLabel(ym))", categoryWidth: 96)
                        .padding(.bottom, 90)
                }
            }
            Button {
                let current = ym == model.currentMonth
                model.newTransaction(day: current ? nil : p.from, accountId: accountId)
            } label: {
                Image(systemName: "plus").font(.system(size: 24, weight: .regular)).foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(MB.accent, in: Circle())
                    .shadow(color: MB.accent.opacity(0.35), radius: 4, y: 3)
            }
            .buttonStyle(.plain)
            .help("Add a transaction to this account")
            .padding(18)
        }
        .sheet(item: $editing) { AccountEditor(request: $0) }
    }
}

struct AccountEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var request: AccountEditRequest

    @UIState private var name = ""
    @UIState private var groupId = ""
    @UIState private var initialBalance = ""
    @UIState private var includeInTotals = true
    @UIState private var hidden = false
    @UIState private var note = ""
    @UIState private var error: String?
    @UIState private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name)
                Picker("Group", selection: $groupId) {
                    ForEach(model.snapshot.sortedGroups) { Text($0.name).tag($0.id) }
                }
                TextField("Starting balance", text: $initialBalance)
                    .help("Balance before the first recorded transaction. Use a negative amount for debt.")
                TextField("Note", text: $note)
                Toggle("Include in totals", isOn: $includeInTotals)
                Toggle("Hidden", isOn: $hidden)
                if let error { Text(error).foregroundStyle(Palette.expense) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.accountId == nil ? "Add Account" : "Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || groupId.isEmpty || saving)
            }
            .padding(16)
        }
        .frame(width: 420)
        .navigationTitle(request.accountId == nil ? "New Account" : "Edit Account")
        .onAppear(perform: load)
    }

    private func load() {
        let s = model.snapshot
        if let id = request.accountId, let a = s.accounts[id] {
            name = a.name; groupId = a.groupId; includeInTotals = a.includeInTotals; hidden = a.hidden; note = a.note
            initialBalance = a.initialBalance == 0 ? "" : String(a.initialBalance)
        } else {
            groupId = s.sortedGroups.first { $0.name == "Accounts" }?.id ?? s.sortedGroups.first?.id ?? ""
        }
    }

    private func save() async {
        let trimmed = initialBalance.trimmingCharacters(in: .whitespaces)
        var balance = 0.0
        if !trimmed.isEmpty {
            guard let v = Money.parse(trimmed) else { error = "Starting balance isn't a number."; return }
            balance = trimmed.hasPrefix("-") || trimmed.hasPrefix("−") ? -v : v
        }
        saving = true
        defer { saving = false }
        do {
            try await model.saveAccount(id: request.accountId, groupId: groupId, name: name.trimmingCharacters(in: .whitespaces),
                                        initialBalance: balance, includeInTotals: includeInTotals, hidden: hidden, note: note)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
