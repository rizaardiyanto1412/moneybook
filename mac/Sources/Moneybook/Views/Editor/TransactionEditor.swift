import AppKit
import MoneybookCore
import SwiftUI
import UniformTypeIdentifiers

/// The entry form, laid out like the web app (web/js/views/entry.js): Date, Amount, Category, Account,
/// Note, Description, with Money Manager's docked panel (calculator keypad, category and account grids).
struct TransactionEditor: View {
    @Environment(AppModel.self) private var model
    var request: EditorRequest

    enum Panel: Hashable { case amount, category, account, to }
    enum Field: Hashable { case note, memo }

    @UIState private var type: TxType = .expense
    @UIState private var date = Date()
    @UIState private var amount = ""
    @UIState private var accountId: String?
    @UIState private var toAccountId: String?
    @UIState private var categoryId: String?
    @UIState private var openParent: String?
    @UIState private var note = ""
    @UIState private var memo = ""
    @UIState private var existingReceipt: String?
    @UIState private var pendingReceipt: PendingReceipt?
    @UIState private var removeReceipt = false
    @UIState private var showLargeReceipt = false
    @UIState private var panel: Panel?
    @UIState private var showDate = false
    @UIState private var saving = false
    @UIState private var error: String?
    @UIState private var savedCount = 0
    @UIState private var confirmDelete = false
    @UIState private var dropTargeted = false
    @FocusState private var focus: Field?
    @UIState private var keyMonitor = KeyMonitor()

    private var isEditing: Bool { request.transactionId != nil }
    private var existing: Transaction? { request.transactionId.flatMap { model.snapshot.transactions[$0] } }
    private var tint: Color { type == .income ? MB.inc : type == .expense ? MB.exp : MB.fg }
    private var digits: Int { Money.fractionDigits(Money.normalizedCode(model.currency)) }

    var body: some View {
        VStack(spacing: 0) {
            DrawerHeader(title: type.label, back: "Trans.", onBack: close)
            typeSegment
            ScrollView {
                VStack(spacing: 0) {
                    form
                    if let error {
                        Text(error).font(.system(size: 14)).foregroundStyle(MB.exp).padding(.horizontal, 16).padding(.top, 12)
                    }
                    if savedCount > 0 {
                        Text("✓ \(savedCount) saved — add another").font(.system(size: 14)).foregroundStyle(.green).padding(.top, 12)
                    }
                    actions
                }
            }
            if let panel { inputPanel(panel) }
        }
        .onAppear { keyMonitor.start { keyboard($0) } }
        .onDisappear { keyMonitor.stop() }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(MB.accent, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(4).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { providers in
            PendingReceipt.load(from: providers) { if let r = $0 { pendingReceipt = r; removeReceipt = false } }
            return true
        }
        .onAppear(perform: load)
        .onChange(of: focus) { if focus != nil { panel = nil } }
        .sheet(isPresented: $showLargeReceipt) {
            ReceiptViewer(image: pendingReceipt?.image, key: removeReceipt ? nil : existingReceipt)
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let id = request.transactionId { Task { await model.delete(transactionIds: [id]) } }
                close()
            }
        }
    }

    private func close() { model.editor = nil }

    // MARK: Form

    /// `.typeseg`: Income / Expense / Transfer outlined in the type's colour.
    private var typeSegment: some View {
        HStack(spacing: 8) {
            ForEach(TxType.allCases) { t in
                let on = t == type
                let c: Color = t == .income ? MB.inc : t == .expense ? MB.exp : MB.fg
                Button { switchType(t) } label: {
                    Text(t.label)
                        .font(.system(size: 15))
                        .foregroundStyle(on ? c : MB.fg2)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(on ? MB.bg : MB.bg2, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? c : MB.line, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(MB.chrome)
    }

    private var form: some View {
        let s = model.snapshot
        let cat = s.categories[categoryId ?? ""]
        let parent = cat?.parentId.flatMap { s.categories[$0] }
        let catLabel = cat.map { (parent.map { "\($0.name)/" } ?? "") + $0.name } ?? ""
        return VStack(spacing: 0) {
            field("Date") {
                Button { showDate.toggle() } label: {
                    HStack(spacing: 18) {
                        Text(mmDate)
                        Text(mmTime)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDate, arrowEdge: .bottom) {
                    VStack(alignment: .trailing, spacing: 8) {
                        DatePicker("", selection: $date, displayedComponents: [.date]).datePickerStyle(.graphical).labelsHidden()
                        HStack {
                            DatePicker("Time", selection: $date, displayedComponents: [.hourAndMinute]).datePickerStyle(.field)
                            Button("Now") { date = Date() }
                        }
                    }
                    .padding(12)
                }
            }
            pickField("Amount", .amount) {
                Text(Money.symbol(model.currency)).padding(.trailing, 6)
                Text(Self.grouped(amount)).monospacedDigit()
            }
            if type != .transfer {
                pickField("Category", .category) { Text(catLabel) }
            }
            pickField(type == .transfer ? "From" : "Account", .account) { Text(s.accounts[accountId ?? ""]?.name ?? "") }
            if type == .transfer {
                pickField("To", .to) { Text(s.accounts[toAccountId ?? ""]?.name ?? "") }
            }
            field("Note") {
                TextField("", text: $note)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .note)
                    .frame(minHeight: 50)
                    .onSubmit { Task { await save(continuing: false) } }
            } underline: { focus == .note }
            MB.bg2.frame(height: 10)
                .overlay(alignment: .top) { MB.line.frame(height: 1) }
                .bottomLine()
                .padding(.top, 16)
            HStack(alignment: .top, spacing: 10) {
                TextField("Description", text: $memo, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($focus, equals: .memo)
                    .padding(.vertical, 13)
                Button(action: chooseReceipt) {
                    Image(systemName: "camera").font(.system(size: 20, weight: .light)).foregroundStyle(Color(white: 0.49))
                        .frame(width: 40, height: 46).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach a receipt photo (or drop one here)")
            }
            .font(.system(size: 16))
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .bottomLine()
            receiptRow
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content, underline: () -> Bool = { false }) -> some View {
        let focused = underline()
        return HStack(spacing: 0) {
            Text(label).font(.system(size: 15)).foregroundStyle(Color(white: 0.455)).frame(width: 76, alignment: .leading)
            content()
                .font(.system(size: 16))
                .foregroundStyle(MB.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    (focused ? tint : MB.line).frame(height: focused ? 2 : 1)
                }
        }
        .padding(.horizontal, 16)
    }

    private func pickField<Content: View>(_ label: String, _ kind: Panel, @ViewBuilder content: () -> Content) -> some View {
        field(label) {
            Button { showPanel(kind) } label: {
                HStack(spacing: 0) { content() }
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } underline: { panel == kind }
    }

    @ViewBuilder private var receiptRow: some View {
        let hasImage = pendingReceipt != nil || (existingReceipt != nil && !removeReceipt)
        if hasImage {
            HStack {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let img = pendingReceipt?.image {
                            Image(nsImage: img).resizable().scaledToFill()
                        } else if let key = existingReceipt {
                            ReceiptThumbnail(key: key)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { showLargeReceipt = true }
                    Button {
                        pendingReceipt = nil
                        if existingReceipt != nil { removeReceipt = true }
                    } label: {
                        Text("✕").font(.system(size: 13)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Color.black.opacity(0.6), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(3)
                    .help("Remove photo")
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    /// `.form-actions`: Save + Continue for a new entry; Save, Delete, Copy when editing.
    @ViewBuilder private var actions: some View {
        Group {
            if isEditing {
                VStack(spacing: 7) {
                    MBButton(title: "Save", primary: true, tint: MB.accent) { Task { await save(continuing: false) } }
                    HStack(spacing: 7) {
                        MBButton(title: "Delete", symbol: "trash") { confirmDelete = true }
                        MBButton(title: "Copy", symbol: "doc.on.doc") {
                            if let id = request.transactionId { model.duplicate(id) }
                            close()
                        }
                    }
                }
            } else {
                HStack(spacing: 7) {
                    MBButton(title: "Save", primary: true, tint: MB.accent) { Task { await save(continuing: false) } }
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1.6)
                    MBButton(title: "Continue") { Task { await save(continuing: true) } }
                        .frame(width: 160)
                        .help("Save and add another (⇧⌘↩)")
                }
            }
        }
        .disabled(saving)
        .padding(.horizontal, 15)
        .padding(.top, 35)
        .padding(.bottom, 16)
        .background {
            Button("") { Task { await save(continuing: false) } }.keyboardShortcut(.return, modifiers: .command).hidden()
            Button("") { Task { await save(continuing: !isEditing) } }.keyboardShortcut(.return, modifiers: [.command, .shift]).hidden()
        }
    }

    // MARK: Docked input panel

    private func inputPanel(_ kind: Panel) -> some View {
        let title = kind == .amount ? "Amount" : kind == .category ? "Category" : "Accounts"
        return VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 16))
                Spacer()
                Button { panel = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 15)).frame(width: 51, height: 42).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.leading, 20)
            .frame(height: 42)
            .foregroundStyle(Palette.dynamic(0xffffff, 0x232428))
            .background(Palette.dynamic(0x000000, 0x808186))
            Group {
                switch kind {
                case .amount: keypad
                case .category: categoryPanel
                case .account: accountPanel(selected: accountId, exclude: nil)
                case .to: accountPanel(selected: toAccountId, exclude: accountId)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 366)
        .background(MB.bg2)
        .shadow(color: .black.opacity(0.08), radius: 5, y: -2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private static let keypadRows: [[String]] = [["+", "-", "×", "÷"], ["7", "8", "9", "="], ["4", "5", "6", "."], ["1", "2", "3", "back"], ["", "0", "", "done"]]

    private var keypad: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.keypadRows.enumerated()), id: \.offset) { r, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { c, k in
                        KeypadKey(key: k, top: r == 0, disabled: k == "." && digits == 0, last: c == 3) { typeKey(k) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var categoryPanel: some View {
        let s = model.snapshot
        let kind: CategoryType = type == .income ? .income : .expense
        let tops = s.topCategories(kind)
        let selTop = s.rootCategory(categoryId)?.id
        if tops.isEmpty {
            MBEmpty(text: "No categories yet — add some in Settings.", emoji: "🗂️")
        } else if !tops.contains(where: { !s.subcategories(of: $0.id).isEmpty }) {
            PickGrid(items: tops.map { ($0.id, $0.name) }, selected: selTop, tint: tint) { pick(.category, $0) }
        } else {
            let parent = tops.first { $0.id == (openParent ?? selTop) }
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(tops) { c in
                            let hasSubs = !s.subcategories(of: c.id).isEmpty
                            PickRow(title: c.name, chevron: hasSubs, on: parent?.id == c.id, tint: tint) {
                                if hasSubs { openParent = c.id } else { pick(.category, c.id) }
                            }
                        }
                    }
                }
                .background(MB.bg)
                .overlay(alignment: .trailing) { MB.line.frame(width: 1) }
                ScrollView {
                    VStack(spacing: 0) {
                        if let parent {
                            PickRow(title: parent.name, suffix: "(all)", on: categoryId == parent.id, tint: tint) { pick(.category, parent.id) }
                            ForEach(s.subcategories(of: parent.id)) { sub in
                                PickRow(title: sub.name, on: categoryId == sub.id, tint: tint) { pick(.category, sub.id) }
                            }
                        }
                    }
                }
                .background(MB.bg)
            }
        }
    }

    private func accountPanel(selected: String?, exclude: String?) -> some View {
        let s = model.snapshot
        let items = s.sortedGroups.flatMap { g in s.sortedAccounts.filter { $0.groupId == g.id && !$0.hidden && $0.id != exclude } }
        return Group {
            if items.isEmpty {
                MBEmpty(text: "No accounts", emoji: "💳")
            } else {
                PickGrid(items: items.map { ($0.id, $0.name) }, selected: selected, tint: tint) { pick(panel ?? .account, $0) }
            }
        }
    }

    // MARK: Behaviour

    private var mmDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, dd/MM/yyyy"
        return f.string(from: date)
    }
    private var mmTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH.mm"
        return f.string(from: date)
    }

    private func showPanel(_ kind: Panel?) {
        focus = nil
        withAnimation(.easeOut(duration: 0.12)) { panel = kind }
        if kind == .category { openParent = nil }
    }

    /// Money Manager walks the fields top to bottom: amount → category (or From → To) → account → note.
    private func next(after kind: Panel) -> Panel? {
        if type == .transfer {
            if kind == .amount { return accountId == nil ? .account : toAccountId == nil ? .to : nil }
            return kind == .account && toAccountId == nil ? .to : nil
        }
        if kind == .amount { return categoryId == nil ? .category : accountId == nil ? .account : nil }
        return kind == .category && accountId == nil ? .account : nil
    }

    private func pick(_ kind: Panel, _ id: String) {
        switch kind {
        case .account: accountId = id
        case .to: toAccountId = id
        case .category: categoryId = id; openParent = nil
        case .amount: break
        }
        advance(from: kind)
    }

    private func advance(from kind: Panel) {
        if let n = next(after: kind) {
            showPanel(n)
        } else {
            withAnimation(.easeOut(duration: 0.12)) { panel = nil }
            if note.isEmpty { focus = .note }
        }
    }

    private func typeKey(_ k: String) {
        var v = amount
        switch k {
        case "done", "=":
            let n = Self.evaluate(v)
            amount = n.map { $0 > 0 ? Self.plain($0) : "" } ?? (v.contains(where: { "+-×÷".contains($0) }) ? "" : v)
            if k == "done" { advance(from: .amount) }
            return
        case "back": v = String(v.dropLast())
        case "+", "-", "×", "÷":
            if let last = v.last, "+-×÷".contains(last) { v.removeLast() }
            if !v.isEmpty || k == "-" { v += k }
        case ".":
            let last = Self.lastNumber(v)
            if !last.contains(".") { v += last.isEmpty ? "0." : "." }
        default:
            let last = Self.lastNumber(v)
            if let dot = last.firstIndex(of: "."), last[last.index(after: dot)...].count >= max(digits, 0) { return }
            v = last == "0" ? String(v.dropLast()) + k : v + k
        }
        amount = v
    }

    /// Typing on the Mac keyboard (number row or numeric keypad) drives the calculator while it's open.
    /// Returns true when the key was used.
    private func keyboard(_ e: NSEvent) -> Bool {
        if e.keyCode == 53, panel != nil { withAnimation(.easeOut(duration: 0.12)) { panel = nil }; return true }
        guard panel == .amount, focus == nil else { return false }
        let mods = e.modifierFlags.intersection([.command, .control, .option])
        guard mods.isEmpty else { return false }
        switch e.keyCode {
        case 36, 76: typeKey("done"); return true      // Return, keypad Enter
        case 51, 117: typeKey("back"); return true     // Delete, forward delete
        default: break
        }
        let map: [String: String] = ["*": "×", "x": "×", "X": "×", "/": "÷", ",": ".", "=": "="]
        let c = e.charactersIgnoringModifiers ?? ""
        let k = map[c] ?? c
        if k.count == 1, "0123456789+-×÷.=".contains(k) {
            if k == "." && digits == 0 { return true }
            typeKey(k)
            return true
        }
        return false
    }

    private func switchType(_ t: TxType) {
        guard t != type else { return }
        type = t
        if let c = categoryId, model.snapshot.categories[c]?.type.rawValue != t.rawValue { categoryId = nil }
        if panel == .category && t == .transfer { panel = nil }
        error = nil
    }

    private func load() {
        let s = model.snapshot
        if let t = existing {
            type = t.type
            date = Periods.parseStamp(t.date) ?? Date()
            amount = Self.plain(t.amount)
            accountId = t.accountId
            toAccountId = t.toAccountId
            categoryId = t.categoryId
            note = t.note
            memo = t.memo
            existingReceipt = t.receipt
        } else {
            type = request.type
            if let day = request.day, day != Periods.today(), let d = Periods.parseStamp(day + "T12:00") { date = d }
            let preferred = request.accountId ?? s.defaultAccountId
            accountId = preferred.flatMap { s.accounts[$0] != nil ? $0 : nil } ?? s.sortedAccounts.first?.id
            panel = request.startPanel ?? .amount
        }
    }

    private func chooseReceipt() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        p.message = "Choose a receipt photo"
        if p.runModal() == .OK, let url = p.url, let r = PendingReceipt(url: url) {
            pendingReceipt = r
            removeReceipt = false
        }
    }

    private func save(continuing: Bool) async {
        guard !saving else { return }
        error = nil
        let value = Self.evaluate(amount) ?? 0
        guard let accountId else { error = "Choose an account."; return }
        if type == .transfer {
            guard let toAccountId else { error = "Choose the destination account."; return }
            if toAccountId == accountId { error = "Pick two different accounts."; return }
        }
        guard value > 0 else { error = "Enter an amount."; showPanel(.amount); return }
        var d = TransactionDraft()
        d.id = request.transactionId
        d.type = type
        d.date = date
        d.amount = value
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
                savedCount += 1
                amount = ""
                note = ""
                memo = ""
                pendingReceipt = nil
                date = Date()
                showPanel(.amount)
            } else {
                close()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Calculator

    private static func lastNumber(_ v: String) -> String {
        String(v.split(omittingEmptySubsequences: false) { "+-×÷".contains($0) }.last ?? "")
    }

    /// "25000" → "25,000"; grouping only in the integer part of each number, for display.
    static func grouped(_ expr: String) -> String {
        var out = "", run = "", afterDot = false
        func flush() {
            if afterDot || run.count <= 3 { out += run } else {
                var g = ""
                for (i, ch) in run.reversed().enumerated() { if i > 0 && i % 3 == 0 { g.append(",") }; g.append(ch) }
                out += String(g.reversed())
            }
            run = ""
            afterDot = false
        }
        for ch in expr {
            if ch.isNumber { run.append(ch) } else { flush(); out.append(ch); afterDot = ch == "." }
        }
        flush()
        return out
    }

    /// Left-to-right with × ÷ before + −, like the web app's evalAmount.
    static func evaluate(_ expr: String) -> Double? {
        var tokens: [String] = []
        var num = ""
        for ch in expr {
            if ch.isNumber || ch == "." { num.append(ch) } else if "+-×÷".contains(ch) {
                if !num.isEmpty { tokens.append(num); num = "" }
                tokens.append(String(ch))
            }
        }
        if !num.isEmpty { tokens.append(num) }
        guard !tokens.isEmpty else { return nil }
        var terms: [Double] = []
        var sign = 1.0
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if t == "+" || t == "-" { sign = t == "-" ? -1 : 1 }
            else if t == "×" || t == "÷" {
                i += 1
                guard i < tokens.count, let n = Double(tokens[i]) else { break }
                let v = terms.popLast() ?? 0
                terms.append(t == "×" ? v * n : n != 0 ? v / n : 0)
            } else if let n = Double(t) { terms.append(sign * n); sign = 1 }
            i += 1
        }
        guard !terms.isEmpty else { return nil }
        return (terms.reduce(0, +) * 100).rounded() / 100
    }

    /// 1234.5 → "1234.5" (no grouping, no trailing zeros).
    static func plain(_ v: Double) -> String {
        v == v.rounded() ? String(Int64(v)) : String(format: "%.2f", v).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

/// Watches key presses in the app while the entry form is open, so typing works without clicking first.
final class KeyMonitor {
    private var token: Any?
    func start(_ handler: @escaping (NSEvent) -> Bool) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in handler(e) ? nil : e }
    }
    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

/// `.kpad .key`
private struct KeypadKey: View {
    var key: String
    var top: Bool
    var disabled: Bool
    var last: Bool
    var action: () -> Void
    @UIState private var hover = false

    var body: some View {
        let done = key == "done"
        Button(action: action) {
            Group {
                if key == "back" { Image(systemName: "delete.left").font(.system(size: 20)) }
                else if done { Text("OK").font(.system(size: 18)) }
                else { Text(key == "-" ? "−" : key).font(.system(size: top ? 24 : "=.".contains(key) ? 22 : 20)) }
            }
            .foregroundStyle(done ? .white : disabled ? MB.fg3 : MB.fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(done ? (hover ? MB.accentPress : MB.accent) : top || disabled ? MB.bg2 : hover ? MB.bg2 : MB.bg)
            .overlay(alignment: .trailing) { if !last { MB.line.frame(width: 1) } }
            .bottomLine()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(key.isEmpty || disabled)
        .onHover { hover = $0 }
    }
}

/// `.pgrid`: three columns of names.
private struct PickGrid: View {
    var items: [(String, String)]
    var selected: String?
    var tint: Color
    var onPick: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.0) { i, item in
                    PickCell(title: item.1, on: item.0 == selected, tint: tint, last: i % 3 == 2) { onPick(item.0) }
                }
            }
        }
    }
}

private struct PickCell: View {
    var title: String
    var on: Bool
    var tint: Color
    var last: Bool
    var action: () -> Void
    @UIState private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? tint : MB.fg)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(hover ? MB.bg2 : MB.bg)
                .overlay(alignment: .trailing) { if !last { MB.line.frame(width: 1) } }
                .bottomLine()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// `.prow`: a row in the two-column category picker.
private struct PickRow: View {
    var title: String
    var suffix: String?
    var chevron = false
    var on: Bool
    var tint: Color
    var action: () -> Void
    @UIState private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 14, weight: on ? .semibold : .regular)).foregroundStyle(on ? tint : MB.fg)
                if let suffix { Text(suffix).font(.system(size: 14)).foregroundStyle(MB.fg3) }
                Spacer()
                if chevron { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(MB.fg3) }
            }
            .padding(.leading, 23)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(on ? tint.opacity(0.06) : hover ? MB.bg2 : .clear)
            .bottomLine()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
