import MoneybookCore
import SwiftUI

/// Accounts tab: Assets / Liabilities / Total and grouped balances (web/js/views/accounts.js).
struct AccountsTab: View {
    @Environment(AppModel.self) private var model
    @State private var editing: AccountEdit?
    @State private var showAdmin = false

    var body: some View {
        let s = model.snapshot
        let balances = Ledger.balances(s)
        let summary = Ledger.balanceSummary(s, balances: balances)
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HeaderBar(left: { EmptyView() }, center: { HeaderTitle("Accounts") }, right: {
                    IconButton(icon: "pencil", label: "Edit accounts") { showAdmin = true }
                    IconButton(icon: "plus", label: "Add account") { editing = AccountEdit(accountId: nil) }
                })
                Strip(items: [("Assets", summary.assets, MM.inc), ("Liabilities", summary.liabilities, MM.exp), ("Total", summary.total, MM.fg)])
            }
            .background(MM.chrome)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(s.sortedGroups) { g in
                        let rows = s.sortedAccounts.filter { $0.groupId == g.id && !$0.hidden }
                        if !rows.isEmpty {
                            let sum = rows.reduce(0) { $0 + (balances[$1.id] ?? 0) }
                            groupHeader(g.name, sum)
                            ForEach(rows) { a in accountRow(a, balances[a.id] ?? 0) }
                        }
                    }
                    let hidden = s.sortedAccounts.filter(\.hidden)
                    if !hidden.isEmpty {
                        groupHeader("Hidden", nil)
                        ForEach(hidden) { a in accountRow(a, balances[a.id] ?? 0, muted: true) }
                    }
                    if s.accounts.isEmpty { EmptyText(text: "No accounts") }
                }
                .padding(.bottom, 90)
            }
            .background(MM.bg)
            .refreshable { await model.sync() }
        }
        .navigationDestination(for: AccountRoute.self) { AccountPage(accountId: $0.id) }
        .navigationDestination(isPresented: $showAdmin) { AccountsAdmin() }
        .sheet(item: $editing) { AccountEditor(edit: $0) }
    }

    private func groupHeader(_ name: String, _ sum: Double?) -> some View {
        HStack(alignment: .bottom) {
            Text(name).foregroundStyle(MM.fg2)
            Spacer()
            if let sum { Text(Fmt.money(sum, model.currency)).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(sum < 0 ? MM.exp : MM.inc) }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
        .background(MM.bg2)
        .overlay(alignment: .bottom) { Line() }
    }

    private func accountRow(_ a: Account, _ balance: Double, muted: Bool = false) -> some View {
        NavigationLink(value: AccountRoute(id: a.id)) {
            HStack {
                Text(a.name).foregroundStyle(muted ? MM.fg2 : MM.fg)
                if !a.includeInTotals && !muted { Text("(excluded)").font(.system(size: 12)).foregroundStyle(MM.fg2) }
                Spacer()
                Text(Fmt.money(balance, model.currency)).monospacedDigit()
                    .foregroundStyle(muted ? MM.fg2 : balance < 0 ? MM.exp : MM.inc)
            }
            .font(.system(size: 15))
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(MM.bg)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .overlay(alignment: .bottom) { Line() }
    }
}

struct AccountRoute: Hashable { var id: String }

/// One account's month: Deposit / Withdrawal / Balance and its day list.
struct AccountPage: View {
    @Environment(AppModel.self) private var model
    var accountId: String
    @State private var ym = Periods.yearMonth(containing: Periods.today())
    @State private var editing: AccountEdit?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = model.snapshot
        let acc = s.accounts[accountId]
        let bal = Ledger.balances(s)[accountId] ?? 0
        let p = Periods.month(ym, startDay: s.monthStartDay)
        let list = Ledger.transactions(in: p, s).filter { $0.accountId == accountId || $0.toAccountId == accountId }
        var dep = 0.0, wd = 0.0
        for t in list {
            if t.type == .income || (t.type == .transfer && t.toAccountId == accountId) { dep += t.amount } else { wd += t.amount }
        }
        return VStack(spacing: 0) {
            PageHeader(title: acc?.name ?? "") {
                Button("Edit") { editing = AccountEdit(accountId: accountId) }
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(MM.accent).padding(.horizontal, 8)
            }
            MonthSwitcher(label: Fmt.monthLabel(ym), onStep: { ym = ym.adding(months: $0) }, onToday: { ym = model.currentMonth })
                .background(MM.chrome)
            Strip(items: [("Deposit", dep, MM.inc), ("Withdrawal", wd, MM.exp), ("Balance", bal, bal < 0 ? MM.exp : MM.fg)])
            ScrollView {
                DayList(txs: list, accountId: accountId, emptyText: "No transactions in \(Fmt.monthLabel(ym))").padding(.bottom, 24)
            }
        }
        .background(MM.bg)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { ym = model.currentMonth }
        .sheet(item: $editing) { AccountEditor(edit: $0) }
        .onChange(of: acc == nil) { _, gone in if gone { dismiss() } }
    }
}

/// Settings → Accounts: every account by group with its starting balance.
struct AccountsAdmin: View {
    @Environment(AppModel.self) private var model
    @State private var editing: AccountEdit?

    var body: some View {
        let s = model.snapshot
        VStack(spacing: 0) {
            PageHeader(title: "Accounts") {
                IconButton(icon: "plus", label: "Add account") { editing = AccountEdit(accountId: nil) }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(s.sortedGroups) { g in
                        let list = s.sortedAccounts.filter { $0.groupId == g.id }
                        if !list.isEmpty {
                            SectionTitle(g.name)
                            Card {
                                ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                                    if i > 0 { Line() }
                                    Button { editing = AccountEdit(accountId: a.id) } label: {
                                        SettingRow(label: a.name + (a.hidden ? "  hidden" : ""),
                                                   value: "\(Fmt.money(a.initialBalance, model.currency)) start", chevron: true)
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .background(MM.bg2)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { AccountEditor(edit: $0) }
    }
}

struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 12.5)).tracking(0.3).foregroundStyle(MM.fg2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 6)
    }
}

struct AccountEdit: Identifiable {
    let id = UUID()
    var accountId: String?
}

struct AccountEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var edit: AccountEdit

    @State private var groupId = ""
    @State private var name = ""
    @State private var initial = ""
    @State private var includeInTotals = true
    @State private var hidden = false
    @State private var confirmDelete = false

    var body: some View {
        let s = model.snapshot
        VStack(spacing: 0) {
            SheetHeader(title: edit.accountId == nil ? "New account" : "Edit account")
            ScrollView {
                VStack(spacing: 0) {
                    FieldLabel("Group")
                    Menu {
                        Picker("Group", selection: $groupId) { ForEach(s.sortedGroups) { Text($0.name).tag($0.id) } }
                    } label: {
                        HStack {
                            Text(s.groups[groupId]?.name ?? "Choose").foregroundStyle(MM.fg)
                            Spacer()
                            Icon("chev", size: 14).foregroundStyle(MM.fg3).rotationEffect(.degrees(90))
                        }
                        .font(.system(size: 16))
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .background(MM.bg2, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MM.line, lineWidth: 1.5))
                    }
                    FieldLabel("Name")
                    InputField(placeholder: "e.g. BCA", text: $name)
                    FieldLabel("Starting balance")
                    InputField(placeholder: "0", text: $initial, keyboard: .numbersAndPunctuation)
                    Toggle("Include in totals", isOn: $includeInTotals).padding(.horizontal, 2).frame(minHeight: 50)
                    Toggle("Hide from lists", isOn: $hidden).padding(.horizontal, 2).frame(minHeight: 50)
                    MMButton(title: edit.accountId == nil ? "Add account" : "Save") { Task { await save() } }
                        .padding(.top, 8)
                    if edit.accountId != nil {
                        MMButton(title: "Delete account", kind: .danger) { confirmDelete = true }.padding(.top, 10)
                    }
                }
                .padding(14)
            }
        }
        .background(MM.bg)
        .presentationDetents([.large])
        .onAppear(perform: load)
        .confirmationDialog("Delete “\(name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            let n = model.snapshot.transactions.values.filter { $0.accountId == edit.accountId || $0.toAccountId == edit.accountId }.count
            if n > 0 { Text("\(n) transactions still reference it; they will remain but won't count toward any listed account.") }
        }
    }

    private func load() {
        let s = model.snapshot
        if let id = edit.accountId, let a = s.accounts[id] {
            groupId = a.groupId; name = a.name; includeInTotals = a.includeInTotals; hidden = a.hidden
            initial = a.initialBalance == 0 ? "" : Fmt.num(a.initialBalance, model.currency)
        } else {
            groupId = s.sortedGroups.first { $0.name == "Accounts" }?.id ?? s.sortedGroups.first?.id ?? ""
        }
    }

    private func save() async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { model.toast("Enter a name"); return }
        let t = initial.trimmingCharacters(in: .whitespaces)
        let ib = t.isEmpty ? 0 : (Money.parse(t) ?? .nan) * (t.hasPrefix("-") ? -1 : 1)
        guard ib.isFinite else { model.toast("Invalid balance"); return }
        let acc = edit.accountId.flatMap { model.snapshot.accounts[$0] }
        do {
            try await model.saveAccount(id: edit.accountId, groupId: groupId, name: n, initialBalance: ib,
                                        includeInTotals: includeInTotals, hidden: hidden, note: acc?.note ?? "")
            model.toast("Saved")
            dismiss()
        } catch { model.toast(error.localizedDescription) }
    }

    private func delete() async {
        guard let id = edit.accountId else { return }
        do {
            try await model.deleteAccount(id)
            model.toast("Deleted")
            dismiss()
        } catch { model.toast(error.localizedDescription) }
    }
}
