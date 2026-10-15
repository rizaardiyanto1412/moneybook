import MoneybookClient
import SwiftUI

/// Settings tab: Money Manager's icon grid (web/js/views/more.js).
struct SettingsTab: View {
    @Environment(AppModel.self) private var model
    enum Page: Hashable { case configuration, accounts, budgets, categories(CategoryType) }
    @State private var page: Page?
    @State private var sheet: SheetKind?
    @State private var pickCategoryType = false
    @State private var confirmLogout = false

    enum SheetKind: String, Identifiable { case ai, backup, password; var id: String { rawValue } }

    private let grid: [(String, String, String)] = [
        ("config", "Configuration", "gear"), ("accounts", "Accounts", "accounts"), ("budgets", "Budget", "budget"), ("cats", "Category", "list"),
        ("sync", "Sync", "refresh"), ("ai", "AI Assistant", "sparkle"), ("backup", "Backup", "download"), ("password", "Password", "lock"),
        ("logout", "Log out", "logout"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar("Settings").background(MM.chrome)
            ScrollView {
                VStack(spacing: 0) {
                    accountCard
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 0) {
                        ForEach(grid, id: \.0) { key, label, icon in
                            Button { tap(key) } label: {
                                VStack(spacing: 6) {
                                    Icon(icon, size: 27)
                                    Text(label).font(.system(size: 12.5)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .foregroundStyle(MM.fgNote)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle(pressed: MM.dyn(0xefeff2, 0x2c2c2e)))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    Text("Moneybook · Money Manager clone").font(.system(size: 12)).foregroundStyle(MM.fg3).padding(.top, 8).padding(.bottom, 20)
                }
            }
            .background(MM.bg)
        }
        .navigationDestination(item: $page) { p in
            switch p {
            case .configuration: ConfigurationPage()
            case .accounts: AccountsAdmin()
            case .budgets: BudgetSettings()
            case .categories(let t): CategoriesPage(type: t)
            }
        }
        .sheet(item: $sheet) { k in
            switch k {
            case .ai: AIHelpSheet()
            case .backup: BackupSheet()
            case .password: PasswordSheet()
            }
        }
        .sheet(isPresented: $pickCategoryType) {
            GridPicker(title: "Category", options: [("expense", "Expenses"), ("income", "Income")], selected: "", cols: 2) { v in
                page = .categories(v == "income" ? .income : .expense)
            }
        }
        .confirmationDialog("Log out?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { model.signOut() }
        } message: { Text("You'll need to sign in again on this device.") }
    }

    private var accountCard: some View {
        let host = URL(string: model.serverURL)?.host(percentEncoded: false) ?? model.serverURL
        let err: String? = if case .offline(let m) = model.connection { m } else { nil }
        let last = model.lastSync?.formatted(date: .omitted, time: .shortened) ?? "never"
        return HStack(spacing: 10) {
            Circle().fill(err != nil ? MM.exp : model.lastSync != nil ? Color(red: 0.2, green: 0.78, blue: 0.35) : MM.fg3).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(host).font(.system(size: 14, weight: .medium))
                Text(err ?? "Synced \(last) · \(model.snapshot.transactions.count) transactions").font(.system(size: 12)).foregroundStyle(MM.fg3).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(MM.line, lineWidth: 0.5))
        .padding(.horizontal, 15).padding(.top, 12).padding(.bottom, 6)
    }

    private func tap(_ key: String) {
        switch key {
        case "config": page = .configuration
        case "accounts": page = .accounts
        case "budgets": page = .budgets
        case "cats": pickCategoryType = true
        case "sync": Task {
            await model.sync()
            if case .offline(let m) = model.connection { model.toast(m) } else { model.toast("Up to date") }
        }
        case "ai": sheet = .ai
        case "backup": sheet = .backup
        case "password": sheet = .password
        default: confirmLogout = true
        }
    }
}

// MARK: - Configuration

struct ConfigurationPage: View {
    @Environment(AppModel.self) private var model
    @State private var picking: Pick?

    enum Pick: String, Identifiable { case currency, startDay, weekStart, account; var id: String { rawValue } }

    var body: some View {
        let s = model.snapshot
        let deviceTz = TimeZone.current.identifier
        VStack(spacing: 0) {
            PageHeader(title: "Configuration")
            ScrollView {
                VStack(spacing: 0) {
                    row("Main Currency Setting", "\(s.currency) (\(Fmt.symbol(s.currency)))") { picking = .currency }
                    row("Monthly Start Date", "Every month \(s.monthStartDay)") { picking = .startDay }
                    row("Weekly Start Day", s.settings["week_start"] == "1" ? "Monday" : "Sunday") { picking = .weekStart }
                    row("Default Account", s.defaultAccountId.flatMap { s.accounts[$0]?.name } ?? "—") { picking = .account }
                    Button { if s.timezone != deviceTz { save(["timezone": deviceTz]) } } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Time Zone").foregroundStyle(MM.fg)
                                Text(s.timezone != deviceTz ? "This iPhone: \(deviceTz) — tap to use" : "Matches this iPhone")
                                    .font(.system(size: 12)).foregroundStyle(MM.fg2)
                            }
                            Spacer()
                            Text(s.timezone).foregroundStyle(MM.fg2)
                        }
                        .font(.system(size: 15)).padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    Hairline()
                }
            }
        }
        .background(MM.bg)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $picking) { p in
            switch p {
            case .currency:
                GridPicker(title: "Currency", options: Money.commonCodes.map { ($0, "\($0) \(Fmt.symbol($0))") }, selected: s.currency, cols: 3) { save(["currency": $0]) }
            case .startDay:
                GridPicker(title: "Month start day", options: (1...28).map { (String($0), String($0)) }, selected: String(s.monthStartDay), cols: 4) { save(["month_start_day": $0]) }
            case .weekStart:
                GridPicker(title: "Week starts on", options: [("0", "Sunday"), ("1", "Monday")], selected: s.settings["week_start"] ?? "0", cols: 2) { save(["week_start": $0]) }
            case .account:
                GridPicker(title: "Default account", options: s.sortedAccounts.filter { !$0.hidden }.map { ($0.id, $0.name) }, selected: s.defaultAccountId ?? "", cols: 3) { save(["default_account_id": $0]) }
            }
        }
    }

    private func row(_ label: String, _ value: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) { SettingRow(label: label, value: value, chevron: true).frame(minHeight: 52) }.buttonStyle(PressStyle())
            Hairline()
        }
    }

    private func save(_ patch: [String: String]) {
        Task {
            do { try await model.updateSettings(patch); model.toast("Saved") } catch { model.toast(error.localizedDescription) }
        }
    }
}

/// A sheet of tappable cells (web `pickFromGrid`).
struct GridPicker: View {
    var title: String
    var options: [(String, String)]
    var selected: String
    var cols: Int = 3
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: cols), spacing: 1) {
                    ForEach(options, id: \.0) { k, l in
                        Button { dismiss(); onPick(k) } label: {
                            Text(l).font(.system(size: 14.5, weight: k == selected ? .semibold : .regular))
                                .foregroundStyle(k == selected ? MM.accent : MM.fg)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(MM.bg)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .background(MM.line)
                .overlay(alignment: .top) { Line() }
                .overlay(alignment: .bottom) { Line() }
            }
        }
        .background(MM.bg)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Budgets

struct BudgetSettings: View {
    @Environment(AppModel.self) private var model
    @State private var ym = Periods.yearMonth(containing: Periods.today())
    @State private var editing: BudgetEdit?

    struct BudgetEdit: Identifiable { let id = UUID(); var categoryId: String?; var name: String }

    var body: some View {
        let s = model.snapshot
        let lines = Ledger.budgetLines(s, month: ym)
        let byId = Dictionary(uniqueKeysWithValues: Ledger.budgetStatus(s, month: ym).map { ($0.categoryId ?? "", $0) })
        VStack(spacing: 0) {
            PageHeader(title: "Budget")
            MonthSwitcher(label: Fmt.monthLabel(ym), onStep: { ym = ym.adding(months: $0) }, onToday: { ym = model.currentMonth }).background(MM.chrome)
            ScrollView {
                VStack(spacing: 0) {
                    Card { row(nil, "🎯", "Total", byId[""]) }
                        .padding(.bottom, 12)
                    SectionTitle("Monthly budget by category")
                    Card {
                        ForEach(Array(lines.dropFirst().enumerated()), id: \.element.id) { i, l in
                            if i > 0 { Line() }
                            row(l.categoryId, l.icon, l.name, byId[l.categoryId ?? ""])
                        }
                    }
                    Text("Budgets repeat every month unless you choose “only this month”. Set 0 to remove.")
                        .font(.system(size: 12)).foregroundStyle(MM.fg3).multilineTextAlignment(.center)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                }
                .padding(.vertical, 12)
            }
            .background(MM.bg2)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { ym = model.currentMonth }
        .sheet(item: $editing) { BudgetEditor(categoryId: $0.categoryId, name: $0.name, month: ym) }
    }

    private func row(_ id: String?, _ icon: String, _ name: String, _ st: BudgetLine?) -> some View {
        Button { editing = BudgetEdit(categoryId: id, name: name) } label: {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text((icon.isEmpty ? "" : "\(icon) ") + name).font(.system(size: 14)).lineLimit(1)
                    if let m = st?.budgetRow?.month, let ym = YearMonth(key: m) {
                        Text("(\(Fmt.monthLabel(ym)) only)").font(.system(size: 12)).foregroundStyle(MM.fg2)
                    }
                    Spacer(minLength: 0)
                    if let st {
                        (Text("\(Fmt.money(st.spent, model.currency)) / ").foregroundColor(MM.fg2) + Text(Fmt.money(st.budget, model.currency)).foregroundColor(MM.fg).bold())
                            .font(.system(size: 13).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        Text("Set").font(.system(size: 13)).foregroundStyle(MM.accent)
                    }
                }
                if let st {
                    BarView(percent: st.ratio * 100).padding(.top, 6)
                    HStack {
                        Text(verbatim: "\(Int((st.ratio * 100).rounded()))%")
                        Spacer()
                        Text(st.remaining < 0 ? "Over by \(Fmt.money(-st.remaining, model.currency))" : "\(Fmt.money(st.remaining, model.currency)) left")
                            .foregroundStyle(st.remaining < 0 ? MM.exp : MM.fg2)
                    }
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(MM.fg2).padding(.top, 5)
                }
            }
            .foregroundStyle(MM.fg)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

extension YearMonth {
    init?(key: String) {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        self.init(year: p[0], month: p[1])
    }
}

struct BudgetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var categoryId: String?
    var name: String
    var month: YearMonth
    @State private var amount = ""
    @State private var onlyMonth = false
    @FocusState private var focused: Bool

    var body: some View {
        let existing = model.snapshot.budgets.values.filter { $0.categoryId == categoryId }
        let monthly = existing.first { $0.month == month.key }
        let every = existing.first { $0.month == nil }
        VStack(spacing: 0) {
            SheetHeader(title: "\(name) budget")
            VStack(spacing: 0) {
                FieldLabel("Amount (\(model.currency))")
                InputField(placeholder: "0", text: $amount, keyboard: .decimalPad).focused($focused)
                Seg(items: [(false, "Every month"), (true, "Only \(Fmt.monthLabel(month))")], selection: $onlyMonth).padding(.top, 14)
                MMButton(title: "Save") { Task { await put(Money.parse(amount.isEmpty ? "0" : amount) ?? -1, onlyMonth ? month : nil, done: "Budget saved") } }
                    .padding(.top, 16)
                if monthly != nil || every != nil {
                    MMButton(title: "Remove budget", kind: .danger) {
                        Task { await put(0, monthly != nil ? month : nil, done: "Removed") }
                    }
                    .padding(.top, 10)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .background(MM.bg)
        .presentationDetents([.medium])
        .onAppear {
            if let v = monthly?.amount ?? every?.amount { amount = Fmt.num(v, model.currency) }
            onlyMonth = monthly != nil
            focused = true
        }
    }

    private func put(_ v: Double, _ m: YearMonth?, done: String) async {
        guard v >= 0 else { model.toast("Enter an amount"); return }
        do {
            try await model.setBudget(categoryId: categoryId, month: m, amount: v)
            dismiss()
            model.toast(done)
        } catch { model.toast(error.localizedDescription) }
    }
}

// MARK: - Categories

struct CategoriesPage: View {
    @Environment(AppModel.self) private var model
    var type: CategoryType
    @State private var editing: CategoryEdit?

    struct CategoryEdit: Identifiable { let id = UUID(); var categoryId: String?; var parentId: String? }

    var body: some View {
        let s = model.snapshot
        let tree = s.topCategories(type)
        VStack(spacing: 0) {
            PageHeader(title: type == .income ? "Income categories" : "Expense categories") {
                IconButton(icon: "plus", label: "Add category") { editing = CategoryEdit() }
            }
            ScrollView {
                VStack(spacing: 0) {
                    Card {
                        ForEach(Array(tree.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { Line() }
                            let kids = s.subcategories(of: c.id)
                            Button { editing = CategoryEdit(categoryId: c.id) } label: {
                                SettingRow(emoji: c.icon.isEmpty ? "•" : c.icon, label: c.name, value: kids.isEmpty ? "" : "\(kids.count)", chevron: true)
                            }
                            .buttonStyle(PressStyle())
                            ForEach(kids) { k in
                                Line()
                                Button { editing = CategoryEdit(categoryId: k.id) } label: {
                                    SettingRow(label: (k.icon.isEmpty ? "" : "\(k.icon) ") + k.name, value: "", muted: true, chevron: true)
                                        .padding(.leading, 40).frame(minHeight: 44)
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                    }
                    Text("Tap a category to rename it, change its emoji, add subcategories or delete it.")
                        .font(.system(size: 12)).foregroundStyle(MM.fg3).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.vertical, 8)
                }
                .padding(.vertical, 12)
            }
            .background(MM.bg2)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { e in
            CategoryEditor(type: type, categoryId: e.categoryId, parentId: e.parentId) { editing = CategoryEdit(parentId: $0) }
        }
    }
}

struct CategoryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var type: CategoryType
    var categoryId: String?
    var parentId: String?
    var onAddSub: (String) -> Void
    @State private var name = ""
    @State private var icon = ""
    @State private var confirmDelete = false

    static let emoji = ["🍜", "🍔", "☕", "🍺", "🛒", "🚖", "🚌", "⛽", "🚗", "✈️", "🏠", "💡", "📱", "💻", "🧥", "👟", "💄", "💊", "🧘", "🏋️", "🎬", "🎮", "🎵", "📚", "📙", "🎁", "🐶", "👶", "👫", "🎉", "💼", "💰", "💵", "🥇", "📈", "🏦", "💳", "🧾", "🔧", "🧹", "🪑", "🖼️", "✂️", "🏥", "📦", "❤️", "⭐", "🌱"]

    var body: some View {
        let s = model.snapshot
        let cat = categoryId.flatMap { s.categories[$0] }
        let parent = (parentId ?? cat?.parentId).flatMap { s.categories[$0] }
        let isNew = categoryId == nil
        let kids = categoryId.map { s.subcategories(of: $0) } ?? []
        VStack(spacing: 0) {
            SheetHeader(title: isNew ? (parent.map { "New in \($0.name)" } ?? "New category") : "Edit category")
            ScrollView {
                VStack(spacing: 0) {
                    FieldLabel("Name")
                    InputField(placeholder: parent != nil ? "e.g. Lunch" : "e.g. Groceries", text: $name)
                    FieldLabel("Emoji")
                    InputField(placeholder: "Type or pick an emoji", text: $icon)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                        ForEach(Self.emoji, id: \.self) { e in
                            Button { icon = e } label: {
                                Text(e).font(.system(size: 24)).frame(maxWidth: .infinity, minHeight: 42)
                                    .background(e == icon ? MM.bg2 : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 10)
                    MMButton(title: isNew ? "Add" : "Save") { Task { await save() } }.padding(.top, 16)
                    if !isNew && cat?.parentId == nil {
                        MMButton(title: "＋ Add subcategory", kind: .ghost) {
                            guard let id = categoryId else { return }
                            dismiss()
                            Task { try? await Task.sleep(for: .milliseconds(300)); onAddSub(id) }
                        }
                        .padding(.top, 10)
                    }
                    if !isNew {
                        MMButton(title: "Delete category", kind: .danger) { confirmDelete = true }.padding(.top, 10)
                    }
                }
                .padding(14)
            }
        }
        .background(MM.bg)
        .presentationDetents([.large])
        .onAppear {
            name = cat?.name ?? ""
            icon = cat?.icon ?? (isNew && parent == nil ? "📦" : "")
        }
        .confirmationDialog("Delete “\(cat?.name ?? "")”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete(kids: kids) } }
        } message: {
            Text("\(kids.isEmpty ? "" : "Its \(kids.count) subcategories will be deleted too. ")Existing transactions keep their amounts but show as uncategorized.")
        }
    }

    private func save() async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { model.toast("Enter a name"); return }
        let e = icon.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        do {
            try await model.saveCategory(id: categoryId, type: type, name: n, icon: e, parentId: parentId)
            dismiss()
            model.toast(categoryId == nil ? "Added" : "Saved")
        } catch { model.toast(error.localizedDescription) }
    }

    private func delete(kids: [Category]) async {
        guard let id = categoryId else { return }
        do {
            for k in kids { try await model.deleteCategory(k.id) }
            try await model.deleteCategory(id)
            dismiss()
            model.toast("Deleted")
        } catch { model.toast(error.localizedDescription) }
    }
}

// MARK: - Sheets

struct AIHelpSheet: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let url = "\(model.serverURL)/mcp"
        VStack(spacing: 0) {
            SheetHeader(title: "AI Assistant")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your AI can add, edit and summarise expenses here through MCP. Point it at:").padding(.horizontal, 2).padding(.vertical, 6)
                    code(url)
                    Text("with the header Authorization: Bearer <your token>. Claude Code:").padding(.horizontal, 2).padding(.vertical, 6)
                    code("claude mcp add --transport http moneybook \(url) --header \"Authorization: Bearer <token>\"")
                    Text("Rows the AI adds show a small ✦ next to the note.").foregroundStyle(MM.fg2).padding(.horizontal, 2).padding(.vertical, 6)
                }
                .font(.system(size: 15))
                .lineSpacing(3)
                .padding(14)
            }
        }
        .background(MM.bg)
        .presentationDetents([.large])
    }

    private func code(_ s: String) -> some View {
        Text(s).font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MM.bg2, in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 10)
    }
}

struct BackupSheet: View {
    @Environment(AppModel.self) private var model
    @State private var file: URL?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Backup")
            VStack(spacing: 0) {
                if let file {
                    ShareLink(item: file) { row("download", "Export ready", "Tap to save or share \(file.lastPathComponent)") }
                } else {
                    Button { Task { await export() } } label: { row("download", busy ? "Preparing…" : "Export", "Download all your data as a JSON file") }
                        .disabled(busy)
                }
                Line()
                Link(destination: URL(string: model.serverURL) ?? URL(string: AppModel.defaultServer)!) {
                    row("upload", "Import from Money Manager", "Open the web app → Settings → Backup and choose your .mmbak")
                }
            }
            .buttonStyle(PressStyle())
            .padding(14)
            Spacer(minLength: 0)
        }
        .background(MM.bg)
        .presentationDetents([.medium])
    }

    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Icon(icon, size: 24).foregroundStyle(MM.fgNote)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15)).foregroundStyle(MM.fg)
                Text(sub).font(.system(size: 12)).foregroundStyle(MM.fg2).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private func export() async {
        busy = true
        defer { busy = false }
        do { file = try await model.exportBackup() } catch { model.toast(error.localizedDescription) }
    }
}

/// Set or change the email + password used to sign in.
struct PasswordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var status: APIClient.AuthStatus?
    @State private var email = ""
    @State private var current = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error = ""
    @State private var busy = false
    @State private var confirmAll = false

    var body: some View {
        let has = status?.hasPassword ?? false
        let needCurrent = has && !model.usesAPIToken
        VStack(spacing: 0) {
            SheetHeader(title: has ? "Change password" : "Set up sign-in")
            ScrollView {
                VStack(spacing: 0) {
                    Text(has ? "Changing it signs out your other devices." : "Sign in with an email and password on your devices instead of the API token. Your AI keeps using the token.")
                        .font(.system(size: 15)).foregroundStyle(MM.fg2).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2).padding(.top, 2)
                    FieldLabel("Email")
                    InputField(placeholder: "", text: $email, keyboard: .emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    if needCurrent {
                        FieldLabel("Current password")
                        InputField(placeholder: "", text: $current, secure: true).textContentType(.password)
                    }
                    FieldLabel(has ? "New password" : "Password")
                    InputField(placeholder: "At least 8 characters", text: $password, secure: true).textContentType(.newPassword)
                    FieldLabel("Confirm password")
                    InputField(placeholder: "", text: $confirm, secure: true).textContentType(.newPassword)
                    Text(error).font(.system(size: 14)).foregroundStyle(MM.exp).frame(minHeight: 20).padding(.top, 10)
                    MMButton(title: "Save") { Task { await save(has: has, needCurrent: needCurrent) } }.padding(.top, 4).disabled(busy)
                    if has {
                        MMButton(title: "Sign out all devices", kind: .ghost) { confirmAll = true }.padding(.top, 10)
                    }
                }
                .padding(14)
            }
        }
        .background(MM.bg)
        .presentationDetents([.large])
        .task {
            status = try? await model.authStatus(server: model.serverURL)
            if email.isEmpty { email = status?.email ?? model.email }
        }
        .confirmationDialog("Sign out all devices?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Sign out all", role: .destructive) {
                Task {
                    do { try await model.logoutAll(); dismiss(); model.toast("Signed out everywhere") } catch { model.toast(error.localizedDescription) }
                }
            }
        } message: { Text("Every device signed in with your password will need to sign in again, including this one if it used the password.") }
    }

    private func save(has: Bool, needCurrent: Bool) async {
        guard password == confirm else { error = "Passwords don't match."; return }
        busy = true
        error = ""
        defer { busy = false }
        do {
            try await model.setPassword(email: email, password: password, current: needCurrent ? current : nil)
            dismiss()
            model.toast(has ? "Password changed" : "Sign-in set up. Use it on your other devices.", seconds: 2.6)
        } catch let e {
            error = e.localizedDescription
        }
    }
}
