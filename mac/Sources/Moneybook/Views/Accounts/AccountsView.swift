import MoneybookCore
import SwiftUI

struct AccountEditRequest: Identifiable {
    let id = UUID()
    var accountId: String?
}

struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @UIState private var editing: AccountEditRequest?
    @UIState private var pendingDelete: Account?
    @UIState private var showHidden = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.accountsPath) {
            list
                .navigationDestination(for: String.self) { AccountDetailView(accountId: $0, onEdit: { editing = AccountEditRequest(accountId: $0) }) }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem {
                Button { editing = AccountEditRequest() } label: { Label("Add Account", systemImage: "plus.rectangle.on.rectangle") }
                    .help("Add an account")
            }
        }
        .sheet(item: $editing) { AccountEditor(request: $0) }
        .confirmationDialog("Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete Account", role: .destructive) {
                guard let a = pendingDelete else { return }
                pendingDelete = nil
                Task {
                    do { try await model.deleteAccount(a.id) } catch { model.errorMessage = error.localizedDescription }
                }
            }
        } message: {
            Text("Its transactions stay in your history but will show a deleted account.")
        }
    }

    private var list: some View {
        let s = model.snapshot
        let balances = Ledger.balances(s)
        let summary = Ledger.balanceSummary(s, balances: balances)
        let groups = s.sortedGroups
        let accounts = s.sortedAccounts.filter { showHidden || !$0.hidden }
        return ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    StatCard(title: "Assets", value: model.money(summary.assets), symbol: "arrow.down.left", tint: Palette.income)
                    StatCard(title: "Liabilities", value: model.money(summary.liabilities), symbol: "arrow.up.right", tint: Palette.expense)
                    StatCard(title: "Net worth", value: model.money(summary.total), symbol: "equal",
                             tint: summary.total < 0 ? Palette.expense : .accentColor, valueColor: .primary)
                }
                ForEach(groups) { g in
                    let items = accounts.filter { $0.groupId == g.id }
                    if !items.isEmpty {
                        let sum = items.reduce(0) { $0 + (balances[$1.id] ?? 0) }
                        groupCard(title: g.name, sum: sum, items: items, balances: balances)
                    }
                }
                let orphans = accounts.filter { s.groups[$0.groupId] == nil }
                if !orphans.isEmpty {
                    groupCard(title: "Other", sum: orphans.reduce(0) { $0 + (balances[$1.id] ?? 0) }, items: orphans, balances: balances)
                }
                if accounts.isEmpty {
                    EmptyStateView(title: "No accounts", symbol: "creditcard", message: "Add an account to start tracking balances.")
                        .frame(height: 260)
                }
                if s.accounts.values.contains(where: \.hidden) {
                    Toggle("Show hidden accounts", isOn: $showHidden).toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .readableWidth()
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .pageBackground()
    }

    private func groupCard(title: String, sum: Double, items: [Account], balances: [String: Double]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(model.money(sum)).font(.money(13, weight: .medium)).foregroundStyle(sum < 0 ? Palette.expense : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            Divider()
            ForEach(Array(items.enumerated()), id: \.element.id) { i, a in
                if i > 0 { Divider().padding(.leading, 62) }
                NavigationLink(value: a.id) {
                    AccountCardRow(account: a, balance: balances[a.id] ?? 0, symbol: groupSymbol(title))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Edit…") { editing = AccountEditRequest(accountId: a.id) }
                    Button("Delete…", role: .destructive) { pendingDelete = a }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Surface.radius, style: .continuous))
        .card(padding: 0)
    }

    private func groupSymbol(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("cash") { return "banknote" }
        if n.contains("card") || n.contains("credit") || n.contains("debit") { return "creditcard" }
        if n.contains("saving") || n.contains("invest") { return "chart.line.uptrend.xyaxis" }
        if n.contains("loan") || n.contains("debt") { return "arrow.uturn.left" }
        if n.contains("insur") { return "umbrella" }
        return "building.columns"
    }
}

/// An account inside a group card: glyph, name, note, balance and a chevron; highlights on hover.
private struct AccountCardRow: View {
    @Environment(AppModel.self) private var model
    var account: Account
    var balance: Double
    var symbol: String
    @UIState private var hovering = false

    var body: some View {
        let a = account
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(balance < 0 ? Palette.expense : Color.accentColor)
                .frame(width: 36, height: 36)
                .background((balance < 0 ? Palette.expense : Color.accentColor).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(a.name).font(.body.weight(.medium))
                    if a.hidden { Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary) }
                    if !a.includeInTotals { Text("excluded").font(.caption2).foregroundStyle(.secondary) }
                }
                if !a.note.isEmpty { Text(a.note).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(model.money(balance)).font(.money(14)).foregroundStyle(balance < 0 ? Palette.expense : .primary)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(hovering ? Surface.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .opacity(a.hidden ? 0.6 : 1)
    }
}

private extension AccountsView {
    private func headerCell(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(model.money(value)).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func accountRow(_ a: Account, balance: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(a.name).font(.body.weight(.medium))
                    if a.hidden { Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary) }
                    if !a.includeInTotals { Text("excluded").font(.caption2).foregroundStyle(.secondary) }
                }
                if !a.note.isEmpty { Text(a.note).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(model.money(balance)).font(.body.monospacedDigit()).foregroundStyle(balance < 0 ? Palette.expense : Palette.income)
        }
        .padding(.vertical, 3)
        .opacity(a.hidden ? 0.6 : 1)
    }
}

/// An account's transactions with the running balance after each one.
struct AccountDetailView: View {
    @Environment(AppModel.self) private var model
    var accountId: String
    var onEdit: (String) -> Void
    @UIState private var allTime = false
    @UIState private var selection = Set<String>()
    @UIState private var pendingDelete: [String] = []

    var body: some View {
        let s = model.snapshot
        if let account = s.accounts[accountId] {
            let running = Ledger.runningBalances(accountId: accountId, s)
            let all = s.transactions.values.filter { $0.accountId == accountId || $0.toAccountId == accountId }
            let txs = (allTime ? all : all.filter { model.period.contains($0.date) }).sorted(by: Ledger.sortDescending)
            let inflow = txs.reduce(0) { $0 + max(Ledger.delta($1, for: accountId), 0) }
            let outflow = txs.reduce(0) { $0 + max(-Ledger.delta($1, for: accountId), 0) }
            let balance = Ledger.balances(s)[accountId] ?? 0
            ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(account.name) · \(s.groups[account.groupId]?.name ?? "")").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                        Text(model.money(balance)).font(.money(30, weight: .bold))
                            .foregroundStyle(balance < 0 ? Palette.expense : .primary)
                        Text("Current balance").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Picker("", selection: $allTime) {
                            Text(Fmt.monthTitle(model.month)).tag(false)
                            Text("All time").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                        HStack(spacing: 14) {
                            Label(model.money(inflow), systemImage: "arrow.down.left").foregroundStyle(Palette.income)
                            Label(model.money(outflow), systemImage: "arrow.up.right").foregroundStyle(Palette.expense)
                        }
                        .font(.callout.monospacedDigit())
                    }
                }
                .card(padding: 18)

                if txs.isEmpty {
                    EmptyStateView(title: "No transactions", symbol: "tray", message: allTime ? "This account has no transactions yet." : "Nothing in \(Fmt.monthTitle(model.month)).")
                        .frame(height: 260)
                } else {
                    VStack(spacing: 0) {
                        TransactionCardRows(transactions: txs, selection: $selection, pendingDelete: $pendingDelete,
                                            trailingDetail: { tx in running[tx.id].map { "Bal. " + model.money($0) } }, showDate: true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Surface.radius, style: .continuous))
                    .card(padding: 0)
                }
            }
            .readableWidth()
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            }
            .pageBackground()
            .transactionKeyboard(selection: $selection, pendingDelete: $pendingDelete)
            .navigationTitle(account.name)
            .toolbar {
                ToolbarItem {
                    Button { onEdit(accountId) } label: { Label("Edit Account", systemImage: "pencil") }
                }
            }
        } else {
            EmptyStateView(title: "Account deleted", symbol: "creditcard.trianglebadge.exclamationmark", message: "This account no longer exists.")
        }
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
