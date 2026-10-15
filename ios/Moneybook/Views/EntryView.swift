import MoneybookCore
import PhotosUI
import SwiftUI

/// Full-screen transaction form (new + edit), Money Manager style (web/js/views/entry.js):
/// labelled fields, and a docked black-header panel for account, category and the amount keypad.
struct EntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var request: EditorRequest

    enum Panel: String { case account, to, category, amount }

    @State private var type: TxType = .expense
    @State private var date = Periods.today()
    @State private var time = "12:00"
    @State private var accountId = ""
    @State private var toAccountId = ""
    @State private var categoryId = ""
    @State private var amount = ""
    @State private var note = ""
    @State private var memo = ""
    @State private var receipt: String?
    @State private var photo: Data?
    @State private var removePhoto = false
    @State private var panel: Panel?
    @State private var openParent: String?
    @State private var calc = false
    @State private var saving = false
    @State private var loaded = false
    @State private var picker: PickerKind?
    @State private var pickedItem: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var showPhoto = false
    @State private var confirmDelete = false
    @State private var editPanel: Panel?
    @FocusState private var focus: TextFieldKind?

    enum TextFieldKind { case note, memo }
    enum PickerKind: String, Identifiable { case date, time; var id: String { rawValue } }

    private static let lastAccountKey = "mb.lastAccount"
    private var editing: Bool { request.transactionId != nil }
    private var tc: Color { MM.color(type) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageHeader(title: type.label, backLabel: "Trans.")
                typeSeg
                ScrollView {
                    form
                    actions.opacity(panel == nil ? 1 : 0)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.bottom, panel == nil ? 0 : 370, for: .scrollContent)
            }
            .background(MM.bg)
            .overlay(alignment: .bottom) {
                if let panel { DockedPanel(title: panelTitle(panel), showEdit: panel != .amount, onEdit: { editPanel = panel; self.panel = nil }, onClose: { self.panel = nil }) {
                    panelBody(panel)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.22), value: panel)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $editPanel) { p in
                if p == .category { CategoriesPage(type: type == .income ? .income : .expense) } else { AccountsAdmin() }
            }
        }
        .onAppear(perform: load)
        .sheet(item: $picker) { kind in
            DateTimeSheet(kind: kind, date: $date, time: $time).presentationDetents([kind == .date ? .medium : .height(300)])
        }
        .photosPicker(isPresented: $showLibrary, selection: $pickedItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { data in setPhoto(data) }.ignoresSafeArea() }
        .sheet(isPresented: $showPhoto) { PhotoSheet(data: photo, receipt: removePhoto ? nil : receipt) }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { if let d = try? await item.loadTransferable(type: Data.self) { setPhoto(d) }; pickedItem = nil }
        }
        .onChange(of: focus) { _, f in if f != nil { panel = nil } }
        .confirmationDialog("Delete transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: { Text("This can't be undone.") }
    }

    // MARK: Type

    private var typeSeg: some View {
        HStack(spacing: 8) {
            ForEach(TxType.allCases) { t in
                let on = t == type
                Button { switchType(t) } label: {
                    Text(t.label)
                        .font(.system(size: 15))
                        .foregroundStyle(on ? MM.color(t) == MM.xfer ? MM.fg : MM.color(t) : MM.fg2)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(on ? MM.bg : MM.dyn(0xf8f8fa, 0x111112), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? (t == .transfer ? MM.fg : MM.color(t)) : MM.dyn(0xe4e5e7, 0x2c2c2e), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
        .background(MM.chrome)
    }

    private func switchType(_ t: TxType) {
        guard t != type else { return }
        let was = type
        type = t
        // Categories are typed; keep only if still valid.
        if let c = model.snapshot.categories[categoryId], c.type.rawValue != t.rawValue { categoryId = "" }
        if t == .transfer && was != .transfer { categoryId = "" }
        if panel == .category && t == .transfer { panel = .to } else if panel == .to && t != .transfer { panel = .category }
    }

    // MARK: Form

    private var form: some View {
        let s = model.snapshot
        let cat = s.categories[categoryId]
        let parent = cat?.parentId.flatMap { s.categories[$0] }
        let catLabel = cat.map { (parent.map { "\($0.name)/" } ?? "") + $0.name } ?? ""
        return VStack(spacing: 0) {
            field("Date") {
                HStack(spacing: 0) {
                    Button(Fmt.entryDate(date)) { focus = nil; panel = nil; picker = .date }.padding(.trailing, 10)
                    Button(timeLabel) { focus = nil; panel = nil; picker = .time }.padding(.leading, 8)
                    Spacer(minLength: 0)
                }
                .buttonStyle(.plain)
                .frame(height: 44)
            }
            field(type == .transfer ? "From" : "Account", pick: .account) { Text(s.accounts[accountId]?.name ?? "") }
            if type == .transfer {
                field("To", pick: .to) { Text(s.accounts[toAccountId]?.name ?? "") }
            } else {
                field("Category", pick: .category) { Text(catLabel) }
            }
            field("Amount", pick: .amount) {
                HStack(spacing: 6) {
                    Text(Fmt.symbol(model.currency))
                    Text(Self.grouped(amount)).monospacedDigit()
                }
            }
            field("Note", focusedLine: focus == .note) {
                TextField("", text: $note).focused($focus, equals: .note).submitLabel(.done).frame(minHeight: 44)
            }
            VStack(spacing: 0) { Line(); MM.bg2.frame(height: 10); Line() }.padding(.top, 16)
            HStack(alignment: .top, spacing: 10) {
                TextField("Description", text: $memo, axis: .vertical)
                    .focused($focus, equals: .memo)
                    .lineLimit(1...8)
                    .font(.system(size: 16))
                    .padding(.vertical, 13)
                Menu {
                    Button("Take Photo", systemImage: "camera") { showCamera = true }
                    Button("Choose from Library", systemImage: "photo") { showLibrary = true }
                } label: {
                    Icon("camera", size: 24).foregroundStyle(MM.dyn(0x7d7d7d, 0x9a9a9e)).frame(width: 40, height: 46)
                }
                .accessibilityLabel(hasPhoto ? "Replace receipt photo" : "Add receipt photo")
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .overlay(alignment: .bottom) { Line() }
            if hasPhoto {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let photo, let img = UIImage(data: photo) { Image(uiImage: img).resizable().scaledToFill() }
                            else if let receipt { ReceiptImage(key: receipt, fill: true) }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onTapGesture { showPhoto = true }
                        Button {
                            photo = nil
                            if receipt != nil { removePhoto = true }
                        } label: {
                            Text("✕").font(.system(size: 13)).foregroundStyle(.white).frame(width: 22, height: 22).background(.black.opacity(0.6), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                        .accessibilityLabel("Remove photo")
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private var hasPhoto: Bool { photo != nil || (receipt != nil && !removePhoto) }

    private var timeLabel: String {
        let p = time.split(separator: ":").compactMap { Int($0) }
        var c = DateComponents(); c.hour = p.first ?? 12; c.minute = p.count > 1 ? p[1] : 0
        let d = Calendar.current.date(from: c) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }

    /// A labelled row with the bottom rule that turns the type colour when its panel is open.
    private func field<V: View>(_ label: String, pick: Panel? = nil, focusedLine: Bool = false, @ViewBuilder value: () -> V) -> some View {
        let on = (pick != nil && panel == pick) || focusedLine
        let content = HStack(spacing: 6) { value() }
            .font(.system(size: 16))
            .foregroundStyle(MM.fg)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .overlay(alignment: .bottom) {
                if on { VStack(spacing: 0) { tc.opacity(0.4).frame(height: 1); tc.frame(height: 1) } } else { Line() }
            }
            .contentShape(Rectangle())
        return HStack(spacing: 0) {
            Text(label).font(.system(size: 15)).foregroundStyle(MM.label).frame(width: 76, alignment: .leading)
            if let pick {
                Button { focus = nil; showPanel(pick) } label: { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        if editing {
            VStack(spacing: 7) {
                actionButton("Save", primary: true) { Task { await save(again: false) } }
                HStack(spacing: 7) {
                    actionButton("Delete", icon: "trash") { confirmDelete = true }
                    actionButton("Copy", icon: "copy") {
                        guard let id = request.transactionId else { return }
                        dismiss()
                        Task { try? await Task.sleep(for: .milliseconds(450)); model.copy(id) }
                    }
                }
            }
            .padding(.horizontal, 15).padding(.top, 35).padding(.bottom, 16)
        } else {
            GeometryReader { geo in
                HStack(spacing: 7) {
                    actionButton("Save", primary: true) { Task { await save(again: false) } }.frame(width: (geo.size.width - 7) * 1.6 / 2.6)
                    actionButton("Continue") { Task { await save(again: true) } }
                }
            }
            .frame(height: 45)
            .padding(.horizontal, 15).padding(.top, 35).padding(.bottom, 16)
        }
    }

    private func actionButton(_ title: String, icon: String? = nil, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon, size: 19) }
                Text(title).font(.system(size: primary ? 15 : 14, weight: primary ? .medium : .regular))
            }
            .foregroundStyle(primary ? .white : MM.fg)
            .frame(maxWidth: .infinity, minHeight: 45)
            .background(primary ? tc : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay { if !primary { RoundedRectangle(cornerRadius: 8).strokeBorder(MM.fg3, lineWidth: 1) } }
            .opacity(saving ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(saving)
    }

    // MARK: Docked panel

    private func panelTitle(_ p: Panel) -> String {
        switch p {
        case .account, .to: "Accounts"
        case .category: "Category"
        case .amount: "Amount"
        }
    }

    private func showPanel(_ p: Panel?) {
        if p != nil { focus = nil }
        panel = p
    }

    @ViewBuilder private func panelBody(_ p: Panel) -> some View {
        switch p {
        case .amount: Keypad(calc: calc, noDecimals: Money.fractionDigits(model.currency) == 0, onKey: typeKey)
        case .category: categoryPanel
        case .account: accountPanel(selected: accountId, exclude: nil)
        case .to: accountPanel(selected: toAccountId, exclude: accountId)
        }
    }

    private func accountPanel(selected: String, exclude: String?) -> some View {
        let s = model.snapshot
        let list = s.sortedGroups.flatMap { g in s.sortedAccounts.filter { $0.groupId == g.id && !$0.hidden && $0.id != exclude } }
        return Group {
            if list.isEmpty { EmptyText(text: "No accounts") } else {
                PanelGrid(items: list.map { ($0.id, $0.name) }, selected: selected, tint: tc) { pick($0) }
            }
        }
    }

    @ViewBuilder private var categoryPanel: some View {
        let s = model.snapshot
        let kind: CategoryType = type == .income ? .income : .expense
        let tree = s.topCategories(kind)
        let sel = s.categories[categoryId]
        let selTop = sel?.parentId ?? sel?.id
        if tree.isEmpty {
            EmptyText(text: "No categories yet — add some in Settings.")
        } else if !tree.contains(where: { !s.subcategories(of: $0.id).isEmpty }) {
            PanelGrid(items: tree.map { ($0.id, $0.name) }, selected: selTop ?? "", tint: tc) { pick($0) }
        } else {
            // With subcategories Money Manager shows two lists side by side.
            let parent = tree.first { $0.id == (openParent ?? selTop) }
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(tree) { c in
                            let kids = !s.subcategories(of: c.id).isEmpty
                            Button { if kids { openParent = c.id } else { pick(c.id) } } label: {
                                panelRow(c.name, on: parent?.id == c.id, chevron: kids)
                            }
                            .buttonStyle(PressStyle(pressed: MM.pressed))
                        }
                    }
                }
                .background(MM.bg)
                MM.line.frame(width: 1)
                ScrollView {
                    VStack(spacing: 0) {
                        if let parent {
                            Button { pick(parent.id) } label: { panelRow(parent.name, suffix: " (all)", on: categoryId == parent.id) }
                                .buttonStyle(PressStyle(pressed: MM.pressed))
                            ForEach(s.subcategories(of: parent.id)) { c in
                                Button { pick(c.id) } label: { panelRow(c.name, on: categoryId == c.id) }
                                    .buttonStyle(PressStyle(pressed: MM.pressed))
                            }
                        }
                    }
                }
                .background(MM.bg)
            }
        }
    }

    private func panelRow(_ name: String, suffix: String = "", on: Bool, chevron: Bool = false) -> some View {
        HStack {
            (Text(name) + Text(suffix).foregroundColor(MM.fg3).fontWeight(.regular))
                .font(.system(size: 14, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? tc : MM.fg)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            if chevron { Icon("chev", size: 14).foregroundStyle(MM.fg3) }
        }
        .padding(.leading, 23).padding(.trailing, 14)
        .frame(minHeight: 50)
        .background(on ? tc.opacity(0.06) : Color.clear)
        .overlay(alignment: .bottom) { Line() }
        .contentShape(Rectangle())
    }

    /// Money Manager walks the fields: account → category → amount → note.
    private func pick(_ id: String) {
        guard let kind = panel else { return }
        switch kind {
        case .account:
            accountId = id
            UserDefaults.standard.set(id, forKey: Self.lastAccountKey)
        case .to: toAccountId = id
        case .category:
            categoryId = id
            openParent = nil
        case .amount: break
        }
        let next: Panel? = switch kind {
        case .account: type == .transfer ? (toAccountId.isEmpty ? .to : amount.isEmpty ? .amount : nil)
                                         : (categoryId.isEmpty ? .category : amount.isEmpty ? .amount : nil)
        case .to, .category: amount.isEmpty ? .amount : nil
        case .amount: nil
        }
        if let next { showPanel(next) } else {
            panel = nil
            if note.isEmpty { focus = .note }
        }
    }

    private func typeKey(_ k: String) {
        var v = amount
        if k == "done" || k == "=" {
            let n = Self.evalAmount(v)
            amount = n.isFinite && n > 0 ? Self.plain(n) : (!v.isEmpty && v.rangeOfCharacter(from: CharacterSet(charactersIn: "-+×÷")) == nil ? v : "")
            if k == "=" { calc = true; return }
            panel = nil
            focus = .note
            return
        }
        if k == "calc" { calc.toggle(); return }
        let ops = CharacterSet(charactersIn: "-+×÷")
        let last = String(v.split(omittingEmptySubsequences: false, whereSeparator: { "-+×÷".contains($0) }).last ?? "")
        if k == "AC" { v = "" }
        else if k == "back" { if !v.isEmpty { v.removeLast() } }
        else if "+-×÷".contains(k) {
            if let l = v.unicodeScalars.last, ops.contains(l) { v.removeLast() }
            if !(v.isEmpty && k != "-") { v += k }
        } else if k == "." {
            if !last.contains(".") { v += last.isEmpty ? "0." : "." }
        } else {
            let dec = last.contains(".") ? last.split(separator: ".", omittingEmptySubsequences: false)[1].count : -1
            if dec != -1 && dec >= Money.fractionDigits(model.currency) { return }
            if last == "0" { v.removeLast(); v += k == "00" ? "0" : k } else { v += k }
        }
        amount = v
    }

    /// "12+3×2−1" left to right with × ÷ precedence.
    static func evalAmount(_ expr: String) -> Double {
        var toks: [String] = []
        var num = ""
        for ch in expr {
            if ch.isNumber || ch == "." { num.append(ch) }
            else if "+-×÷".contains(ch) { if !num.isEmpty { toks.append(num); num = "" }; toks.append(String(ch)) }
        }
        if !num.isEmpty { toks.append(num) }
        guard !toks.isEmpty else { return .nan }
        var out: [Double] = []
        var sign = 1.0
        var i = 0
        while i < toks.count {
            let t = toks[i]
            if t == "+" || t == "-" { sign = t == "-" ? -1 : 1 }
            else if t == "×" || t == "÷" {
                i += 1
                guard i < toks.count, let nx = Double(toks[i]) else { break }
                let v = out.popLast() ?? 0
                out.append(t == "×" ? v * nx : nx != 0 ? v / nx : 0)
            } else if let n = Double(t) { out.append(sign * n); sign = 1 }
            i += 1
        }
        return (out.reduce(0, +) * 100).rounded() / 100
    }

    /// Shows what was typed with thousands separators: "25000" → "25,000", "1200.5+300" → "1,200.5+300".
    /// The keypad's "." is always the decimal point, so the separator is always a comma.
    static func grouped(_ expr: String) -> String {
        var out = "", num = ""
        func flush() {
            guard !num.isEmpty else { return }
            let parts = num.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            var whole = String(parts[0])
            var i = whole.count - 3
            while i > 0 { whole.insert(",", at: whole.index(whole.startIndex, offsetBy: i)); i -= 3 }
            out += whole + (parts.count > 1 ? "." + parts[1] : "")
            num = ""
        }
        for ch in expr {
            if ch.isNumber || ch == "." { num.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        return out
    }

    /// 25000 → "25000", 12.5 → "12.5"
    static func plain(_ n: Double) -> String {
        n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
    }

    // MARK: Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        let s = model.snapshot
        let now = Date()
        let hm = { (d: Date) in String(Periods.localStamp(d).suffix(5)) }
        if let id = request.transactionId, let t = s.transactions[id] {
            type = t.type; date = t.day; time = t.time.isEmpty ? "12:00" : t.time
            accountId = t.accountId; toAccountId = t.toAccountId ?? ""; categoryId = t.categoryId ?? ""
            amount = Self.plain(t.amount); note = t.note; memo = t.memo; receipt = t.receipt
            return
        }
        type = request.type
        date = request.day ?? Periods.today()
        time = hm(now)
        accountId = defaultAccount(s)
        if let id = request.copyOf, let t = s.transactions[id] {
            type = t.type; accountId = t.accountId; toAccountId = t.toAccountId ?? ""; categoryId = t.categoryId ?? ""
            amount = Self.plain(t.amount); note = t.note; memo = t.memo
            return
        }
        // New entries start the walk at the category (or "To" for transfers), like the app.
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            showPanel(type == .transfer ? .to : categoryId.isEmpty ? .category : .amount)
            #if DEBUG
            if let p = UserDefaults.standard.string(forKey: "panel") { showPanel(Panel(rawValue: p)); amount = "25000" }
            #endif
        }
    }

    private func defaultAccount(_ s: Snapshot) -> String {
        if let last = UserDefaults.standard.string(forKey: Self.lastAccountKey), s.accounts[last] != nil { return last }
        if let d = s.defaultAccountId, s.accounts[d] != nil { return d }
        return s.sortedAccounts.first?.id ?? ""
    }

    private func setPhoto(_ data: Data) {
        photo = Self.jpeg(data)
        removePhoto = false
    }

    private func save(again: Bool) async {
        guard !saving else { return }
        let value = amount.rangeOfCharacter(from: CharacterSet(charactersIn: "-+×÷")) != nil ? Self.evalAmount(amount) : (Double(amount) ?? Money.parse(amount) ?? 0)
        if accountId.isEmpty { model.toast("Choose an account"); return }
        if type == .transfer {
            if toAccountId.isEmpty { model.toast("Choose the destination account"); return }
            if toAccountId == accountId { model.toast("Pick two different accounts"); return }
        }
        guard value > 0 else { model.toast("Enter an amount"); showPanel(.amount); return }
        saving = true
        defer { saving = false }
        let stamp = Periods.parseStamp("\(date)T\(time)") ?? Date()
        let draft = TransactionDraft(id: request.transactionId, type: type, date: stamp, amount: value, accountId: accountId,
                                     toAccountId: type == .transfer ? toAccountId : nil, categoryId: categoryId.isEmpty ? nil : categoryId,
                                     note: note.trimmingCharacters(in: .whitespaces), memo: memo.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            let row = try await model.save(draft)
            if let photo {
                do { try await model.uploadReceipt(transactionId: row.id, data: photo, mimeType: "image/jpeg") }
                catch { model.toast("Saved, but the photo failed: \(error.localizedDescription)", seconds: 3) }
            } else if removePhoto, receipt != nil {
                try? await model.removeReceipt(transactionId: row.id)
            }
            if again {
                model.toast("Saved — add another")
                amount = ""; note = ""; memo = ""; photo = nil; receipt = nil; removePhoto = false
                time = String(Periods.localStamp(Date()).suffix(5))
                showPanel(.amount)
            } else {
                model.toast("Saved")
                dismiss()
            }
        } catch {
            model.toast(error.localizedDescription, seconds: 2.6)
        }
    }

    private func delete() async {
        guard let id = request.transactionId else { return }
        await model.delete(transactionId: id)
        model.toast("Deleted")
        dismiss()
    }

    /// Downscales to ≤1600 px on the long edge and re-encodes as JPEG.
    static func jpeg(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let scale = min(1, 1600 / max(img.size.width, img.size.height))
        let size = CGSize(width: (img.size.width * scale).rounded(), height: (img.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            img.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.85)
    }
}

// MARK: - Panel pieces

/// Money Manager's input panel: black header, white cells on light grey.
struct DockedPanel<Content: View>: View {
    var title: String
    var showEdit: Bool
    var onEdit: () -> Void
    var onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(title).font(.system(size: 16)).foregroundStyle(.white)
                Spacer()
                if showEdit {
                    Button(action: onEdit) { Icon("pencil", size: 19).frame(width: 51, height: 42) }.accessibilityLabel("Edit")
                }
                Button(action: onClose) { Icon("close", size: 19).frame(width: 51, height: 42) }.accessibilityLabel("Close")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.leading, 20)
            .frame(height: 42)
            .background(Color.black)
            content.frame(maxHeight: .infinity).clipped()
        }
        .frame(height: 350)
        .background(MM.bg2.ignoresSafeArea(edges: .bottom))
        .shadow(color: .black.opacity(0.08), radius: 5, y: -2)
    }
}

/// Three-column grid of names (accounts, or categories without subcategories).
struct PanelGrid: View {
    var items: [(String, String)]
    var selected: String
    var tint: Color
    var onPick: (String) -> Void

    var body: some View {
        let padded = items + Array(repeating: ("", ""), count: (3 - items.count % 3) % 3)
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
                ForEach(Array(padded.enumerated()), id: \.offset) { i, item in
                    Button { if !item.0.isEmpty { onPick(item.0) } } label: {
                        Text(item.1)
                            .font(.system(size: 14, weight: item.0 == selected ? .semibold : .regular))
                            .foregroundStyle(item.0 == selected ? tint : MM.fg)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60)
                            .background(MM.bg, ignoresSafeAreaEdges: [])
                            .overlay(alignment: .trailing) { if i % 3 < 2 { MM.line.frame(width: 1) } }
                            .overlay(alignment: .bottom) { Line() }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(pressed: MM.pressed))
                    .disabled(item.0.isEmpty)
                }
            }
        }
    }
}

struct Keypad: View {
    var calc: Bool
    var noDecimals: Bool
    var onKey: (String) -> Void

    private static let pad = [["1", "2", "3", "back"], ["4", "5", "6", "-"], ["7", "8", "9", "calc"], ["00", "0", ".", "done"]]
    private static let calcPad = [["AC", "÷", "×", "back"], ["7", "8", "9", "-"], ["4", "5", "6", "+"], ["1", "2", "3", "="], ["00", "0", ".", "done"]]

    var body: some View {
        let rows = calc ? Self.calcPad : Self.pad
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { i, k in
                        key(k).overlay(alignment: .trailing) { if i < 3 { MM.line.frame(width: 1) } }
                    }
                }
                .overlay(alignment: .bottom) { Line() }
            }
        }
    }

    private func key(_ k: String) -> some View {
        let isNum = k.allSatisfy(\.isNumber)
        let disabled = k == "." && noDecimals
        let done = k == "done"
        let op = !isNum && k != "." && !done
        return Button { onKey(k) } label: {
            Group {
                switch k {
                case "back": Icon("backspace", size: 24)
                case "calc": Icon("calc", size: 24)
                case "done": Text("Done").font(.system(size: 16))
                case "-": Text("−").font(.system(size: 20, weight: .semibold))
                default: Text(k).font(.system(size: 20, weight: op ? .semibold : .regular))
                }
            }
            .foregroundStyle(done ? .white : disabled ? MM.fg3 : MM.fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(done ? MM.accent : disabled || (calc && op) ? MM.bg2 : MM.bg, ignoresSafeAreaEdges: [])
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(pressed: done ? MM.accentPress : MM.pressed))
        .disabled(disabled)
    }
}

struct DateTimeSheet: View {
    var kind: EntryView.PickerKind
    @Binding var date: String
    @Binding var time: String
    @Environment(\.dismiss) private var dismiss
    @State private var value = Date()

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: kind == .date ? "Date" : "Time") {
                Button("Done") { apply(); dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(MM.accent)
            }
            if kind == .date {
                DatePicker("", selection: $value, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().padding(.horizontal)
                    .onChange(of: value) { apply(); dismiss() }
            } else {
                DatePicker("", selection: $value, displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden()
            }
            Spacer(minLength: 0)
        }
        .background(MM.bg)
        .onAppear { value = Periods.parseStamp("\(date)T\(time)") ?? Date() }
    }

    private func apply() {
        let stamp = Periods.localStamp(value)
        if kind == .date { date = String(stamp.prefix(10)) } else { time = String(stamp.suffix(5)) }
    }
}

/// Loads a receipt photo from the server.
struct ReceiptImage: View {
    @Environment(AppModel.self) private var model
    var key: String
    var fill = false
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                if fill { Image(uiImage: image).resizable().scaledToFill() } else { Image(uiImage: image).resizable().scaledToFit() }
            } else {
                MM.bg2.overlay { ProgressView() }
            }
        }
        .task(id: key) { image = await model.receiptImage(key) }
    }
}

struct PhotoSheet: View {
    var data: Data?
    var receipt: String?
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Receipt")
            ScrollView {
                if let data, let img = UIImage(data: data) { Image(uiImage: img).resizable().scaledToFit() }
                else if let receipt { ReceiptImage(key: receipt) }
            }
        }
        .presentationDetents([.large])
    }
}

/// The system camera, for receipt photos.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage, let d = img.jpegData(compressionQuality: 0.9) { parent.onImage(d) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
