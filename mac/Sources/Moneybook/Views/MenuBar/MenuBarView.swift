import AppKit
import MoneybookCore
import SwiftUI

/// Menu bar extra: what you spent today, today's transactions, quick add, and a one-line month summary.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    @UIState private var amount = ""
    @UIState private var note = ""
    @UIState private var categoryId: String?
    @UIState private var accountId: String?
    @UIState private var saving = false
    @UIState private var message: (ok: Bool, text: String)?
    @FocusState private var amountFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            todaySection
            Divider()
            listSection
            Divider()
            quickAdd
            Divider()
            monthSection
            Divider()
            footer
        }
        .frame(width: 330)
        .onAppear {
            let s = model.snapshot
            if accountId == nil { accountId = s.defaultAccountId.flatMap { s.accounts[$0] != nil ? $0 : nil } ?? s.sortedAccounts.first?.id }
            amountFocused = true
            Task { await model.sync() }
        }
    }

    // MARK: Today

    private var today: String { Periods.today() }

    private func expenses(on day: String) -> [Transaction] {
        Ledger.transactions(in: Period(from: day, to: day), model.snapshot).filter { $0.type == .expense }
    }

    private var todaySection: some View {
        let spent = expenses(on: today)
        let yesterday = Ledger.totals(expenses(on: Periods.addDays(today, -1))).expense
        let p = model.currentPeriod
        let monthSpent = Ledger.totals(Ledger.transactions(in: p, model.snapshot)).expense
        let daysSoFar = max(Periods.days(from: p.from, to: min(today, p.to)).count, 1)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Today · \(Self.dayLabel(today))")
                Spacer()
                Text(spent.count == 1 ? "1 expense" : "\(spent.count) expenses")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(MB.fg2)
            Text(model.money(Ledger.totals(spent).expense))
                .font(.system(size: 30, weight: .bold).monospacedDigit())
                .foregroundStyle(MB.exp)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.bottom, 2)
            HStack(spacing: 14) {
                (Text("Yesterday ") + Text(model.money(yesterday)).foregroundColor(MB.fg))
                (Text("Daily avg ") + Text(model.money(monthSpent / Double(daysSoFar))).foregroundColor(MB.fg))
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(MB.fg2)
            .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var listSection: some View {
        let s = model.snapshot
        let txs = Ledger.transactions(in: Period(from: today, to: today), s)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Today").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(MB.fg2)
            if txs.isEmpty {
                Text("Nothing spent yet today").font(.system(size: 13)).foregroundStyle(MB.fg3).padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(txs) { tx in TodayRow(tx: tx) { open(tx.id) } }
                    }
                }
                .frame(height: min(CGFloat(txs.count), 6) * 40)
                .scrollDisabled(txs.count <= 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Quick add

    /// The three expense categories used most in the last 30 days.
    private var frequentCategories: [MoneybookCore.Category] {
        let s = model.snapshot
        let since = Periods.addDays(today, -30)
        var counts: [String: Int] = [:]
        for tx in s.transactions.values where tx.type == .expense && tx.day >= since {
            if let c = tx.categoryId, s.categories[c] != nil { counts[c, default: 0] += 1 }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).compactMap { s.categories[$0.key] }
    }

    private var quickAdd: some View {
        let s = model.snapshot
        var chips = frequentCategories
        if let id = categoryId, let c = s.categories[id], !chips.contains(where: { $0.id == id }) { chips.append(c) }
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Quick add").font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text("↩ to save").font(.system(size: 11.5))
            }
            .foregroundStyle(MB.fg2)
            HStack(spacing: 6) {
                TextField("Amount", text: $amount)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13).monospacedDigit())
                    .frame(width: 130)
                    .focused($amountFocused)
                    .onSubmit { Task { await add() } }
                TextField("Note", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await add() } }
            }
            FlowLayout(spacing: 5) {
                ForEach(chips) { c in
                    Chip(title: c.name, on: categoryId == c.id) { categoryId = categoryId == c.id ? nil : c.id }
                }
                Menu {
                    ForEach(s.topCategories(.expense)) { c in
                        let subs = s.subcategories(of: c.id)
                        if subs.isEmpty {
                            Button(c.name) { categoryId = c.id }
                        } else {
                            Menu(c.name) {
                                Button("\(c.name) (all)") { categoryId = c.id }
                                ForEach(subs) { sub in Button(sub.name) { categoryId = sub.id } }
                            }
                        }
                    }
                    if categoryId != nil {
                        Divider()
                        Button("No category") { categoryId = nil }
                    }
                } label: {
                    Text("More…").font(.system(size: 11.5)).foregroundStyle(MB.fgNote)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.07), in: Capsule())
                .fixedSize()
            }
            HStack(spacing: 6) {
                Picker("", selection: $accountId) {
                    ForEach(s.sortedAccounts.filter { !$0.hidden }) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                Button { Task { await add() } } label: {
                    Text("Add").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 22)
                        .background(MB.accent.opacity(canAdd ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
            if let message {
                Label(message.text, systemImage: message.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(message.ok ? .green : MB.exp)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var canAdd: Bool { !saving && (Money.parse(amount) ?? 0) > 0 }

    // MARK: Month and footer

    private var monthSection: some View {
        let spent = Ledger.totals(Ledger.transactions(in: model.currentPeriod, model.snapshot)).expense
        let budget = Ledger.budgetLines(model.snapshot, month: model.currentMonth).first { $0.categoryId == nil }
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                (Text("\(Fmt.monthName(model.currentMonth)) so far ") + Text(model.money(spent)).foregroundColor(MB.fg))
                    .foregroundStyle(MB.fg2)
                Spacer()
                if let budget, budget.budget > 0 {
                    Text(budget.remaining >= 0 ? "\(model.money(budget.remaining)) left" : "Over budget")
                        .foregroundStyle(budget.remaining >= 0 ? MB.fg2 : MB.exp)
                }
            }
            .font(.system(size: 12).monospacedDigit())
            .lineLimit(1)
            if let budget, budget.budget > 0 {
                ProgressBar(ratio: budget.ratio, tint: budget.ratio > 1 ? MB.exp : budget.ratio > 0.85 ? .orange : MB.sat, height: 5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Button("Open Moneybook") {
                openWindow(id: "main")
                NSApp.activate()
            }
            .foregroundStyle(MB.accent)
            Spacer()
            SyncDot()
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .font(.system(size: 12.5, weight: .medium))
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private func open(_ id: String) {
        openWindow(id: "main")
        NSApp.activate()
        model.section = .transactions
        model.edit(id)
    }

    private func add() async {
        guard let value = Money.parse(amount), value > 0 else { return }
        var d = TransactionDraft()
        d.type = .expense
        d.amount = value
        d.accountId = accountId ?? model.snapshot.defaultAccountId ?? model.snapshot.sortedAccounts.first?.id
        d.categoryId = categoryId
        d.note = note.trimmingCharacters(in: .whitespaces)
        saving = true
        defer { saving = false }
        do {
            try await model.save(d)
            message = (true, "Added \(model.money(value))")
            amount = ""
            note = ""
            amountFocused = true
        } catch {
            message = (false, error.localizedDescription)
        }
    }

    /// "Thu, 15 Oct"
    static func dayLabel(_ day: String) -> String {
        guard let d = Periods.date(day) else { return day }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE, d MMM"
        return f.string(from: d)
    }
}

/// Time, note over category · account, amount. Click opens it in the main window.
private struct TodayRow: View {
    @Environment(AppModel.self) private var model
    var tx: Transaction
    var action: () -> Void
    @UIState private var hover = false

    var body: some View {
        let s = model.snapshot
        let acc = s.accounts[tx.accountId]?.name ?? "?"
        let cat = tx.type == .transfer ? "Transfer" : s.categories[tx.categoryId ?? ""]?.name ?? "Uncategorized"
        let sub = tx.type == .transfer ? "\(acc) → \(s.accounts[tx.toAccountId ?? ""]?.name ?? "?")" : "\(cat) · \(acc)"
        Button(action: action) {
            HStack(spacing: 8) {
                Text(tx.time.replacingOccurrences(of: ":", with: ".")).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(MB.fg3)
                    .frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
                        Text(tx.note.isEmpty ? cat : tx.note).font(.system(size: 13)).lineLimit(1)
                        if tx.isAI { Text("✦").font(.system(size: 10)).foregroundStyle(Palette.ai) }
                    }
                    Text(sub).font(.system(size: 11)).foregroundStyle(MB.fg3).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(model.money(tx.amount)).font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(tx.type == .income ? MB.inc : tx.type == .expense ? MB.exp : MB.xfer)
            }
            .frame(height: 40)
            .padding(.horizontal, 4)
            .background(hover ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Open in Moneybook")
    }
}

private struct Chip: View {
    var title: String
    var on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5)).lineLimit(1)
                .foregroundStyle(on ? Color.white : MB.fgNote)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(on ? MB.accent : Color.primary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var r = rows[rows.count - 1]
            r.width += (r.items.isEmpty ? 0 : spacing) + size.width
            r.height = max(r.height, size.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}

private struct SyncDot: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let (color, text): (Color, String) = switch model.connection {
        case .online: (.green, "Synced")
        case .connecting: (.yellow, "Connecting")
        case .offline: (.orange, "Offline")
        case .unconfigured: (.gray, "Not connected")
        }
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }
}
