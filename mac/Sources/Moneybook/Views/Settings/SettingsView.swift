import AppKit
import MoneybookCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    /// True inside the ⌘, Settings window.
    var standalone = false

    enum Part { case connection, preferences, categories, accounts, groups }
    var parts: [Part] = [.connection, .preferences, .categories, .groups]

    @UIState private var server = ""
    @UIState private var token = ""
    @UIState private var testing = false
    @UIState private var testResult: (ok: Bool, message: String)?
    @UIState private var categoryType: CategoryType = .expense
    @UIState private var editingCategory: CategoryEditRequest?
    @UIState private var editingGroup: GroupEditRequest?
    @UIState private var deleteCategory: MoneybookCore.Category?
    @UIState private var deleteGroup: AccountGroup?
    @UIState private var editingAccount: AccountEditRequest?
    @UIState private var deleteAccount: Account?
    @UIState private var currencyDraft = ""

    var body: some View {
        Form {
            if parts.contains(.connection) { connectionSection }
            if parts.contains(.preferences) { preferencesSection }
            if parts.contains(.categories) { categoriesSection }
            if parts.contains(.accounts) { accountsSection }
            if parts.contains(.groups) { groupsSection }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(item: $editingAccount) { AccountEditor(request: $0) }
        .confirmationDialog("Delete \u{201C}\(deleteAccount?.name ?? "")\u{201D}?", isPresented: Binding(get: { deleteAccount != nil }, set: { if !$0 { deleteAccount = nil } })) {
            Button("Delete Account", role: .destructive) {
                guard let a = deleteAccount else { return }
                deleteAccount = nil
                run { try await model.deleteAccount(a.id) }
            }
        } message: {
            Text("Its transactions stay in your history but will show a deleted account.")
        }
        .onAppear {
            server = model.serverURL
            token = model.token
            currencyDraft = model.currency
        }
        .onChange(of: model.currency) { currencyDraft = model.currency }
        .sheet(item: $editingCategory) { CategoryEditor(request: $0) }
        .sheet(item: $editingGroup) { GroupEditor(request: $0) }
        .confirmationDialog("Delete \u{201C}\(deleteCategory?.name ?? "")\u{201D}?", isPresented: Binding(get: { deleteCategory != nil }, set: { if !$0 { deleteCategory = nil } })) {
            Button("Delete Category", role: .destructive) {
                guard let c = deleteCategory else { return }
                deleteCategory = nil
                run { try await model.deleteCategory(c.id) }
            }
        } message: {
            Text("Existing transactions keep their amounts but will show as uncategorized.")
        }
        .confirmationDialog("Delete group \u{201C}\(deleteGroup?.name ?? "")\u{201D}?", isPresented: Binding(get: { deleteGroup != nil }, set: { if !$0 { deleteGroup = nil } })) {
            Button("Delete Group", role: .destructive) {
                guard let g = deleteGroup else { return }
                deleteGroup = nil
                run { try await model.deleteGroup(g.id) }
            }
        }
    }

    // MARK: Connection

    private var connectionSection: some View {
        Section {
            TextField("Server URL", text: $server, prompt: Text("https://moneybook.example.workers.dev"))
            SecureField("API token", text: $token, prompt: Text("Bearer token"))
            HStack {
                if let r = testResult {
                    Label(r.message, systemImage: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(r.ok ? .green : Palette.expense)
                        .font(.callout)
                        .lineLimit(2)
                } else {
                    connectionLabel
                }
                Spacer()
                if testing { ProgressView().controlSize(.small) }
                Button("Test Connection") {
                    testing = true
                    testResult = nil
                    Task {
                        let r = await model.testConnection(server: server, token: token)
                        testing = false
                        switch r {
                        case .success(let msg): testResult = (true, msg)
                        case .failure(let e): testResult = (false, e.localizedDescription)
                        }
                    }
                }
                .disabled(server.isEmpty || token.isEmpty || testing)
                Button("Save") {
                    model.configure(server: server, token: token)
                    testResult = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(server == model.serverURL && token == model.token)
            }
        } header: {
            Text("Server")
        } footer: {
            Text("The token is stored in your Keychain. Data is cached in ~/Library/Application Support/Moneybook so the app works offline (read-only).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var connectionLabel: some View {
        switch model.connection {
        case .online: Label("Connected", systemImage: "checkmark.circle").foregroundStyle(.green).font(.callout)
        case .connecting: Label("Connecting…", systemImage: "hourglass").foregroundStyle(.secondary).font(.callout)
        case .offline(let msg): Label(msg, systemImage: "wifi.exclamationmark").foregroundStyle(.orange).font(.callout).lineLimit(2)
        case .unconfigured: Label("Not configured", systemImage: "circle.dashed").foregroundStyle(.secondary).font(.callout)
        }
    }

    // MARK: Preferences (stored on the server)

    private var preferencesSection: some View {
        let s = model.snapshot
        return Section("Preferences") {
            HStack {
                Text("Currency")
                Spacer()
                TextField("", text: $currencyDraft)
                    .frame(width: 70)
                    .multilineTextAlignment(.center)
                    .onSubmit { setCurrency(currencyDraft) }
                Menu {
                    ForEach(Money.commonCodes, id: \.self) { code in
                        Button("\(code)  \(Locale.current.localizedString(forCurrencyCode: code) ?? "")") { setCurrency(code) }
                    }
                } label: { Image(systemName: "list.bullet") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Text(Money.format(1234.5, currency: s.currency)).foregroundStyle(.secondary).monospacedDigit().frame(minWidth: 90, alignment: .trailing)
            }
            Picker("Month starts on day", selection: Binding(get: { s.monthStartDay }, set: { v in run { try await model.updateSettings(["month_start_day": String(v)]) } })) {
                ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
            }
            Picker("Week starts on", selection: Binding(get: { s.firstWeekday }, set: { v in run { try await model.updateSettings(["week_start": v == 2 ? "1" : "0"]) } })) {
                Text("Sunday").tag(1)
                Text("Monday").tag(2)
            }
            Picker("Default account", selection: Binding(get: { s.defaultAccountId ?? "" }, set: { v in run { try await model.updateSettings(["default_account_id": v]) } })) {
                Text("None").tag("")
                ForEach(s.sortedAccounts) { Text($0.name).tag($0.id) }
            }
            LabeledContent("Time zone", value: s.timezone)
        }
        .disabled(!model.isConfigured)
    }

    private func setCurrency(_ code: String) {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard c.count == 3, c.allSatisfy(\.isLetter) else {
            currencyDraft = model.currency
            model.errorMessage = "Use a 3-letter ISO currency code like USD, EUR or IDR."
            return
        }
        currencyDraft = c
        run { try await model.updateSettings(["currency": c]) }
    }

    // MARK: Categories

    private var categoriesSection: some View {
        let s = model.snapshot
        return Section {
            Picker("", selection: $categoryType) {
                Text("Expense").tag(CategoryType.expense)
                Text("Income").tag(CategoryType.income)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ForEach(s.topCategories(categoryType)) { c in
                categoryRow(c, indent: false)
                ForEach(s.subcategories(of: c.id)) { sub in categoryRow(sub, indent: true) }
            }
        } header: {
            HStack {
                Text("Categories")
                Spacer()
                Button { editingCategory = CategoryEditRequest(type: categoryType) } label: { Label("Add Category", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func categoryRow(_ c: MoneybookCore.Category, indent: Bool) -> some View {
        HStack(spacing: 8) {
            if indent { Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary).padding(.leading, 12) }
            Text(c.icon.isEmpty ? "·" : c.icon).frame(width: 22)
            Text(c.name)
            Spacer()
            if !indent {
                Button { editingCategory = CategoryEditRequest(type: c.type, parentId: c.id) } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless).help("Add a subcategory")
            }
            Button { editingCategory = CategoryEditRequest(type: c.type, categoryId: c.id) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).help("Edit")
            Button { deleteCategory = c } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete")
        }
        .contextMenu {
            Button("Edit…") { editingCategory = CategoryEditRequest(type: c.type, categoryId: c.id) }
            if !indent { Button("Add Subcategory…") { editingCategory = CategoryEditRequest(type: c.type, parentId: c.id) } }
            Button("Delete…", role: .destructive) { deleteCategory = c }
        }
    }

    // MARK: Accounts

    private var accountsSection: some View {
        let s = model.snapshot
        return Section {
            ForEach(s.sortedGroups) { g in
                ForEach(s.sortedAccounts.filter { $0.groupId == g.id }) { a in
                    HStack {
                        Text(a.name).foregroundStyle(a.hidden ? .secondary : .primary)
                        Text(g.name).font(.caption).foregroundStyle(.secondary)
                        if a.hidden { Text("Hidden").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button { editingAccount = AccountEditRequest(accountId: a.id) } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).help("Edit")
                        Button { deleteAccount = a } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Delete")
                    }
                }
            }
        } header: {
            HStack {
                Text("Accounts")
                Spacer()
                Button { editingAccount = AccountEditRequest() } label: { Label("Add Account", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: Account groups

    private var groupsSection: some View {
        let s = model.snapshot
        return Section {
            ForEach(s.sortedGroups) { g in
                let count = s.accounts.values.filter { $0.groupId == g.id }.count
                HStack {
                    Text(g.name)
                    Text(g.kind.capitalized).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(count == 1 ? "1 account" : "\(count) accounts").font(.caption).foregroundStyle(.secondary)
                    Button { editingGroup = GroupEditRequest(groupId: g.id) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                    Button { deleteGroup = g } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .disabled(count > 0)
                        .help(count > 0 ? "Move or delete its accounts first" : "Delete")
                }
            }
        } header: {
            HStack {
                Text("Account groups")
                Spacer()
                Button { editingGroup = GroupEditRequest() } label: { Label("Add Group", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        Task {
            do { try await op() } catch { model.errorMessage = error.localizedDescription }
        }
    }
}

struct CategoryEditRequest: Identifiable {
    let id = UUID()
    var type: CategoryType
    var categoryId: String?
    var parentId: String?
}

struct CategoryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var request: CategoryEditRequest
    @UIState private var name = ""
    @UIState private var icon = ""
    @UIState private var error: String?
    @FocusState private var iconFocused: Bool

    private static let suggestions = ["🍜", "🍔", "☕️", "🛒", "🚖", "🚌", "⛽️", "🏠", "💡", "📱", "🎬", "🎮", "📚", "🎁", "💊", "🏋️", "✈️", "🐶",
                                      "👕", "💄", "👶", "🍺", "💼", "💰", "💵", "🥇", "📈", "🏦", "🧾", "📦"]

    var body: some View {
        let parent = request.parentId.flatMap { model.snapshot.categories[$0] }
        VStack(alignment: .leading, spacing: 14) {
            Text(request.categoryId != nil ? "Edit Category" : parent != nil ? "New Subcategory of \(parent!.name)" : "New \(request.type.label) Category")
                .font(.title3.weight(.semibold))
            HStack(spacing: 10) {
                TextField("", text: $icon)
                    .font(.system(size: 26))
                    .multilineTextAlignment(.center)
                    .frame(width: 56, height: 44)
                    .focused($iconFocused)
                    .onChange(of: icon) { if icon.count > 1 { icon = String(icon.suffix(1)) } }
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 10), spacing: 4) {
                ForEach(Self.suggestions, id: \.self) { e in
                    Button(e) { icon = e }.buttonStyle(.plain).font(.system(size: 20))
                }
            }
            Button("More Emoji…") {
                iconFocused = true
                NSApp.orderFrontCharacterPalette(nil)
            }
            .buttonStyle(.link)
            if let error { Text(error).foregroundStyle(Palette.expense).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        do {
                            try await model.saveCategory(id: request.categoryId, type: request.type, name: name.trimmingCharacters(in: .whitespaces),
                                                         icon: icon, parentId: request.parentId)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let id = request.categoryId, let c = model.snapshot.categories[id] { name = c.name; icon = c.icon }
        }
    }
}

struct GroupEditRequest: Identifiable {
    let id = UUID()
    var groupId: String?
}

struct GroupEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var request: GroupEditRequest
    @UIState private var name = ""
    @UIState private var kind = "asset"
    @UIState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.groupId == nil ? "New Account Group" : "Edit Account Group").font(.title3.weight(.semibold))
            Form {
                TextField("Name", text: $name)
                Picker("Kind", selection: $kind) {
                    Text("Asset").tag("asset")
                    Text("Card").tag("card")
                    Text("Liability").tag("liability")
                }
            }
            if let error { Text(error).foregroundStyle(Palette.expense).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        do {
                            try await model.saveGroup(id: request.groupId, name: name.trimmingCharacters(in: .whitespaces), kind: kind)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            if let id = request.groupId, let g = model.snapshot.groups[id] { name = g.name; kind = g.kind }
        }
    }
}
