import MoneybookCore
import SwiftUI
import UniformTypeIdentifiers

struct TransactionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var request: EditorRequest

    enum Field: Hashable { case amount, note, memo }

    @UIState private var type: TxType = .expense
    @UIState private var date = Date()
    @UIState private var amountText = ""
    @UIState private var accountId: String?
    @UIState private var toAccountId: String?
    @UIState private var categoryId: String?
    @UIState private var expandedParent: String?
    @UIState private var note = ""
    @UIState private var memo = ""
    @UIState private var existingReceipt: String?
    @UIState private var pendingReceipt: PendingReceipt?
    @UIState private var removeReceipt = false
    @UIState private var showLargeReceipt = false
    @UIState private var saving = false
    @UIState private var error: String?
    @UIState private var savedCount = 0
    @UIState private var confirmDelete = false
    @UIState private var dropTargeted = false
    @FocusState private var focus: Field?

    private var isEditing: Bool { request.transactionId != nil }
    private var existing: Transaction? { request.transactionId.flatMap { model.snapshot.transactions[$0] } }

    var body: some View {
        VStack(spacing: 0) {
            header
            amountHero
            Form {
                if type == .transfer {
                    Section {
                        accountPicker("From", $accountId)
                        HStack {
                            accountPicker("To", $toAccountId)
                            Button { swap(&accountId, &toAccountId) } label: { Image(systemName: "arrow.up.arrow.down") }
                                .buttonStyle(.borderless)
                                .help("Swap From and To")
                        }
                    }
                } else {
                    Section("Category") {
                        CategoryGrid(type: type == .income ? .income : .expense, selection: $categoryId, expandedParent: $expandedParent)
                            .padding(.vertical, 4)
                    }
                }
                Section {
                    HStack {
                        DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.field)
                        Button("Now") { date = Date() }.buttonStyle(.link).font(.caption)
                    }
                    if type != .transfer {
                        accountPicker("Account", $accountId)
                    }
                    TextField("Note", text: $note, prompt: Text("e.g. Starbucks"))
                        .focused($focus, equals: .note)
                    TextField("Description", text: $memo, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focus, equals: .memo)
                }
                Section("Receipt") {
                    receiptField
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            if let error {
                Text(error).font(.callout).foregroundStyle(Palette.expense).padding(.horizontal, 20).padding(.bottom, 6)
            }
            footer
        }
        .frame(width: 580, height: type == .transfer ? 560 : 740)
        .background(Surface.page)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(4).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { providers in
            PendingReceipt.load(from: providers) { if let r = $0 { pendingReceipt = r; removeReceipt = false } }
            return true
        }
        .onAppear(perform: load)
        .sheet(isPresented: $showLargeReceipt) {
            ReceiptViewer(image: pendingReceipt?.image, key: removeReceipt ? nil : existingReceipt)
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let id = request.transactionId {
                    Task { await model.delete(transactionIds: [id]) }
                }
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var amountHero: some View {
        VStack(spacing: 6) {
            Text(type == .transfer ? "Amount to move" : type == .income ? "Amount received" : "Amount spent")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Money.symbol(model.currency))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.color(type).opacity(0.7))
                TextField("", text: $amountText, prompt: Text("0").foregroundStyle(.quaternary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(type == .transfer ? Color.primary : Palette.color(type))
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .frame(minWidth: 80)
                    .focused($focus, equals: .amount)
                    .onSubmit { focus = .note }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(TxType.allCases) { t in
                Button { switchType(t) } label: {
                    Text(t.label)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(type == t ? Color.white : .secondary)
                        .background(type == t ? tabColor(t) : Color.clear, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack {
            if isEditing {
                Button("Delete", role: .destructive) { confirmDelete = true }
            }
            if savedCount > 0 {
                Label("\(savedCount) saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
                    .transition(.opacity)
            }
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            if !isEditing {
                Button("Continue") { Task { await save(continuing: true) } }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .help("Save and start another (⇧⌘↩)")
                    .disabled(saving)
            }
            Button("Save") { Task { await save(continuing: false) } }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(tabColor(type))
                .help("Save (⌘↩)")
                .disabled(saving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// Solid colour for a type (transfer uses a real grey so white text stays legible).
    private func tabColor(_ t: TxType) -> Color { t == .transfer ? Color(nsColor: .systemGray) : Palette.color(t) }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).frame(width: 84, alignment: .trailing)
    }

    private func accountPicker(_ title: String, _ binding: Binding<String?>) -> some View {
        let s = model.snapshot
        let accounts = s.sortedAccounts.filter { !$0.hidden || $0.id == binding.wrappedValue }
        return Picker(title, selection: binding) {
            Text("Choose…").tag(String?.none)
            ForEach(s.sortedGroups) { g in
                let items = accounts.filter { $0.groupId == g.id }
                if !items.isEmpty {
                    Section(g.name) {
                        ForEach(items) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var receiptField: some View {
        let hasImage = pendingReceipt != nil || (existingReceipt != nil && !removeReceipt)
        HStack(alignment: .top, spacing: 12) {
            Button { if hasImage { showLargeReceipt = true } else { chooseReceipt() } } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: hasImage ? [] : [4]))
                    if let img = pendingReceipt?.image {
                        Image(nsImage: img).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if let key = existingReceipt, !removeReceipt {
                        ReceiptThumbnail(key: key)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus").font(.title2)
                            Text("Drop photo").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 84, height: 84)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(hasImage ? "Click to view" : "Drop an image here or click to choose")
            VStack(alignment: .leading, spacing: 6) {
                Button(hasImage ? "Replace…" : "Choose…") { chooseReceipt() }
                if hasImage {
                    Button("Remove", role: .destructive) {
                        pendingReceipt = nil
                        if existingReceipt != nil { removeReceipt = true }
                    }
                }
                if pendingReceipt != nil { Text("Uploads when you save").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: Behaviour

    private func load() {
        let s = model.snapshot
        if let t = existing {
            type = t.type
            date = Periods.parseStamp(t.date) ?? Date()
            amountText = Money.format(t.amount, currency: model.currency, symbol: false)
                .replacingOccurrences(of: Locale.current.groupingSeparator ?? ",", with: "")
            accountId = t.accountId
            toAccountId = t.toAccountId
            categoryId = t.categoryId
            expandedParent = s.rootCategory(t.categoryId)?.id
            note = t.note
            memo = t.memo
            existingReceipt = t.receipt
        } else {
            type = request.type
            if let day = request.day, day != Periods.today(), let d = Periods.parseStamp(day + "T12:00") {
                date = d
            }
            accountId = s.defaultAccountId.flatMap { s.accounts[$0] != nil ? $0 : nil } ?? s.sortedAccounts.first?.id
        }
        DispatchQueue.main.async { focus = .amount }
    }

    private func switchType(_ t: TxType) {
        guard t != type else { return }
        type = t
        if let c = categoryId, model.snapshot.categories[c]?.type.rawValue != t.rawValue {
            categoryId = nil
            expandedParent = nil
        }
        error = nil
    }

    private func chooseReceipt() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a receipt photo"
        if panel.runModal() == .OK, let url = panel.url, let r = PendingReceipt(url: url) {
            pendingReceipt = r
            removeReceipt = false
        }
    }

    private func save(continuing: Bool) async {
        error = nil
        guard let amount = Money.parse(amountText), amount > 0 else {
            error = "Enter an amount."
            focus = .amount
            return
        }
        guard let accountId else { error = "Choose an account."; return }
        if type == .transfer {
            guard let toAccountId else { error = "Choose the account to transfer to."; return }
            if toAccountId == accountId { error = "Choose two different accounts."; return }
        }
        var d = TransactionDraft()
        d.id = request.transactionId
        d.type = type
        d.date = date
        d.amount = amount
        d.accountId = accountId
        d.toAccountId = type == .transfer ? toAccountId : nil
        d.categoryId = type == .transfer ? nil : categoryId
        d.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        d.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        defer { saving = false }
        do {
            let saved = try await model.save(d)
            if let r = pendingReceipt {
                do {
                    try await model.uploadReceipt(transactionId: saved.id, data: r.data, mimeType: r.mimeType)
                } catch {
                    model.errorMessage = "Saved, but the receipt upload failed: \(error.localizedDescription)"
                }
            } else if removeReceipt && existingReceipt != nil {
                try? await model.removeReceipt(transactionId: saved.id)
            }
            if continuing {
                withAnimation { savedCount += 1 }
                amountText = ""
                note = ""
                memo = ""
                pendingReceipt = nil
                focus = .amount
            } else {
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Category picker: a grid of emoji + name; parents with subcategories expand into a chip row.
struct CategoryGrid: View {
    @Environment(AppModel.self) private var model
    var type: CategoryType
    @Binding var selection: String?
    @Binding var expandedParent: String?

    var body: some View {
        let s = model.snapshot
        let parents = s.topCategories(type)
        let tint = type == .income ? Palette.income : Palette.expense
        VStack(alignment: .leading, spacing: 8) {
            // A plain grid (not Lazy) so it sizes exactly to its rows inside the form's Grid.
            let columns = 5
            Grid(horizontalSpacing: 4, verticalSpacing: 8) {
                ForEach(0..<((parents.count + columns - 1) / columns), id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { col in
                            let i = row * columns + col
                            if i < parents.count { tile(parents[i], s: s, tint: tint) } else { Color.clear.frame(height: 1) }
                        }
                    }
                }
            }
            if let pid = expandedParent, let parent = s.categories[pid] {
                let subs = s.subcategories(of: pid)
                if !subs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("\(parent.icon) \(parent.name)", selected: selection == pid, tint: tint) { selection = pid }
                            ForEach(subs) { sub in
                                chip(sub.icon.isEmpty ? sub.name : "\(sub.icon) \(sub.name)", selected: selection == sub.id, tint: tint) { selection = sub.id }
                            }
                        }
                    }
                }
            }
            if parents.isEmpty {
                Text("No \(type.label.lowercased()) categories. Add some in Settings.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func tile(_ c: MoneybookCore.Category, s: Snapshot, tint: Color) -> some View {
        let selected = s.rootCategory(selection)?.id == c.id
        let hasSubs = !s.subcategories(of: c.id).isEmpty
        Button {
            selection = c.id
            expandedParent = hasSubs ? c.id : nil
        } label: {
            VStack(spacing: 5) {
                Text(c.icon.isEmpty ? "•" : c.icon)
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
                    .background(selected ? tint.opacity(0.22) : Color.primary.opacity(0.05), in: Circle())
                    .overlay(Circle().strokeBorder(selected ? tint : .clear, lineWidth: 2))
                HStack(spacing: 2) {
                    Text(c.name).font(.caption.weight(selected ? .semibold : .regular)).lineLimit(1)
                    if hasSubs { Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary) }
                }
                .foregroundStyle(selected ? tint : .primary)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(c.name)
    }

    private func chip(_ title: String, selected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(selected ? tint : Color.secondary.opacity(0.1), in: Capsule())
                .foregroundStyle(selected ? Color.white : .primary)
        }
        .buttonStyle(.plain)
    }
}
