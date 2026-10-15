import AppKit
import MoneybookCore
import SwiftUI

/// Menu bar extra: this month's spending, a quick-add form and the latest transactions.
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
        let s = model.snapshot
        let txs = Ledger.transactions(in: model.currentPeriod, s)
        let totals = Ledger.totals(txs)
        let budget = Ledger.budgetLines(s, month: model.currentMonth).first { $0.categoryId == nil }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Fmt.monthTitle(model.currentMonth)) spending").font(.caption).foregroundStyle(.secondary)
                Text(model.money(totals.expense)).font(.system(size: 26, weight: .bold).monospacedDigit()).foregroundStyle(Palette.expense)
                HStack {
                    Text("Income \(model.money(totals.income))").foregroundStyle(Palette.income)
                    Spacer()
                    Text("Net \(model.money(totals.total))").foregroundStyle(.secondary)
                }
                .font(.caption.monospacedDigit())
                if let budget, budget.budget > 0 {
                    ProgressBar(ratio: budget.ratio, tint: budget.ratio > 1 ? Palette.expense : Palette.income, height: 5)
                        .padding(.top, 4)
                    Text(budget.remaining >= 0 ? "\(model.money(budget.remaining)) left of \(model.money(budget.budget))"
                                               : "\(model.money(-budget.remaining)) over budget")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Quick add expense").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    TextField("Amount", text: $amount)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospacedDigit())
                        .frame(width: 100)
                        .focused($amountFocused)
                        .onSubmit { Task { await add() } }
                    TextField("Note", text: $note)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await add() } }
                }
                HStack {
                    Picker("", selection: $categoryId) {
                        Text("Category").tag(String?.none)
                        ForEach(s.topCategories(.expense)) { c in
                            Text("\(c.icon) \(c.name)").tag(Optional(c.id))
                            ForEach(s.subcategories(of: c.id)) { sub in
                                Text("     \(sub.name)").tag(Optional(sub.id))
                            }
                        }
                    }
                    .labelsHidden()
                    Picker("", selection: $accountId) {
                        ForEach(s.sortedAccounts.filter { !$0.hidden }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    Button("Add") { Task { await add() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(saving || Money.parse(amount) == nil)
                }
                if let message {
                    Label(message.text, systemImage: message.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(message.ok ? .green : Palette.expense)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Recently added").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                let recent = Array(s.transactions.values.sorted { $0.createdAt > $1.createdAt }.prefix(5))
                if recent.isEmpty { Text("No transactions yet").font(.caption).foregroundStyle(.secondary) }
                ForEach(recent) { tx in
                    HStack(spacing: 6) {
                        Text(s.rootCategory(tx.categoryId)?.icon ?? (tx.type == .transfer ? "↔︎" : "•")).frame(width: 18)
                        Text(tx.note.isEmpty ? (s.categories[tx.categoryId ?? ""]?.name ?? tx.type.label) : tx.note).lineLimit(1)
                        if tx.isAI { AISparkle() }
                        Spacer()
                        Text(model.money(tx.amount)).monospacedDigit().foregroundStyle(Palette.color(tx.type))
                    }
                    .font(.callout)
                }
            }

            Divider()

            HStack {
                Button("Open Moneybook") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                SyncDot()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            if accountId == nil { accountId = s.defaultAccountId ?? s.sortedAccounts.first?.id }
            amountFocused = true
            Task { await model.sync() }
        }
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
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
