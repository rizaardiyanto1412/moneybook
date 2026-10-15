import MoneybookCore
import SwiftUI

struct BudgetView: View {
    @Environment(AppModel.self) private var model
    @UIState private var editing: BudgetEditRequest?

    var body: some View {
        let s = model.snapshot
        let lines = Ledger.budgetLines(s, month: model.month)
        let total = lines.first { $0.categoryId == nil }!
        let categories = lines.filter { $0.categoryId != nil }
        let budgeted = categories.filter { $0.budget > 0 }.sorted { $0.ratio > $1.ratio }
        let unbudgeted = categories.filter { $0.budget == 0 }.sorted { $0.spent > $1.spent }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                totalCard(total)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Categories").font(.headline).padding(.bottom, 6)
                    if budgeted.isEmpty {
                        Text("No category budgets yet. Click Edit Budgets to set monthly limits.")
                            .foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(budgeted) { line in
                        BudgetRow(line: line)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { editing = BudgetEditRequest(focus: line.categoryId) }
                            .contextMenu { Button("Edit Budget…") { editing = BudgetEditRequest(focus: line.categoryId) } }
                        Divider()
                    }
                }
                .card()

                if !unbudgeted.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Without a budget").font(.headline)
                        ForEach(unbudgeted) { line in
                            HStack {
                                CategoryIcon(icon: line.icon, size: 24, tint: Palette.expense)
                                Text(line.name)
                                Spacer()
                                Text(model.money(line.spent)).foregroundStyle(line.spent > 0 ? Palette.expense : .secondary).monospacedDigit()
                                Button("Set…") { editing = BudgetEditRequest(focus: line.categoryId) }
                                    .buttonStyle(.link)
                            }
                            .font(.callout)
                        }
                    }
                    .card()
                }
            }
            .readableWidth(1040)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .pageBackground()
        .navigationTitle("Budget")
        .toolbar {
            ToolbarItem {
                Button { editing = BudgetEditRequest(focus: nil) } label: { Label("Edit Budgets", systemImage: "slider.horizontal.3") }
                    .help("Edit budget amounts")
            }
        }
        .sheet(item: $editing) { BudgetEditor(request: $0) }
    }

    private func totalCard(_ line: BudgetLine) -> some View {
        let p = model.period
        let days = Double(p.days.count)
        let elapsed = p.contains(Periods.today()) ? Double(p.days.firstIndex(of: Periods.today()) ?? 0) + 1 : (Periods.today() > p.to ? days : 0)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Total budget").font(.headline)
                if line.isMonthOverride { Text("This month only").font(.caption).foregroundStyle(.secondary) }
                if line.isSynthetic { Text("Sum of category budgets").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(line.budget > 0 ? "Edit" : "Set Total Budget…") { editing = BudgetEditRequest(focus: nil) }
                    .buttonStyle(.link)
            }
            if line.budget > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.money(line.remaining))
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundStyle(line.remaining < 0 ? Palette.expense : .primary)
                    Text(line.remaining < 0 ? "over budget" : "left").foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", line.ratio * 100)).font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(line.ratio > 1 ? Palette.expense : Palette.income)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        ProgressBar(ratio: line.ratio, tint: line.ratio > 1 ? Palette.expense : Palette.income, height: 14)
                        if elapsed > 0 && elapsed < days {
                            Rectangle().fill(Color.primary.opacity(0.6)).frame(width: 2, height: 22)
                                .offset(x: geo.size.width * elapsed / days - 1)
                                .help("Today")
                        }
                    }
                }
                .frame(height: 22)
                HStack {
                    stat("Budget", line.budget, .primary)
                    stat("Spent", line.spent, Palette.expense)
                    stat("Remaining", line.remaining, line.remaining < 0 ? Palette.expense : Palette.income)
                    if elapsed > 0 && elapsed < days && line.remaining > 0 {
                        stat("Per day left", line.remaining / (days - elapsed + 1), .secondary)
                    }
                }
            } else {
                Text("You've spent \(model.money(line.spent)) in \(Fmt.monthTitle(model.month)). Set a total budget to track it.")
                    .foregroundStyle(.secondary)
            }
        }
        .card(padding: 18)
    }

    private func stat(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(model.money(value)).font(.callout.weight(.medium).monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BudgetRow: View {
    @Environment(AppModel.self) private var model
    var line: BudgetLine
    var compact = false

    var body: some View {
        let over = line.ratio > 1
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if line.categoryId == nil {
                    Image(systemName: "sum").frame(width: compact ? 20 : 26)
                } else {
                    CategoryIcon(icon: line.icon, size: compact ? 20 : 26, tint: Palette.expense)
                }
                Text(line.name).font(compact ? .callout : .body.weight(.medium))
                if line.isMonthOverride {
                    Image(systemName: "calendar.badge.clock").font(.caption).foregroundStyle(.secondary).help("Budget for this month only")
                }
                Spacer()
                Text("\(model.money(line.spent)) / \(model.money(line.budget))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", line.ratio * 100))
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(over ? Palette.expense : .primary)
                    .frame(width: 48, alignment: .trailing)
            }
            ProgressBar(ratio: line.ratio, tint: over ? Palette.expense : Palette.income, height: compact ? 6 : 8)
            if !compact {
                Text(line.remaining >= 0 ? "\(model.money(line.remaining)) left" : "\(model.money(-line.remaining)) over")
                    .font(.caption)
                    .foregroundStyle(over ? Palette.expense : .secondary)
            }
        }
        .padding(.vertical, compact ? 2 : 6)
    }
}

struct BudgetEditRequest: Identifiable {
    let id = UUID()
    /// Category to highlight; nil = Total.
    var focus: String?
}

/// Edits every budget at once, either as the default for every month or for the selected month only.
struct BudgetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var request: BudgetEditRequest

    enum Scope: Hashable { case everyMonth, thisMonth }
    @UIState private var scope: Scope = .everyMonth
    @UIState private var values: [String: String] = [:]
    @UIState private var original: [String: String] = [:]
    @UIState private var saving = false
    @UIState private var error: String?
    @FocusState private var focused: String?

    var body: some View {
        let cats = model.snapshot.topCategories(.expense)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Edit Budgets").font(.title2.weight(.semibold))
                Picker("Apply to", selection: $scope) {
                    Text("Every month (default)").tag(Scope.everyMonth)
                    Text("\(Fmt.monthTitle(model.month)) only").tag(Scope.thisMonth)
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                Text(scope == .everyMonth
                     ? "Defaults apply to every month unless a month has its own amount."
                     : "Overrides the default for \(Fmt.monthTitle(model.month)). Leave empty to use the default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            Form {
                row(key: "", icon: "", name: "Total")
                Section("Categories") {
                    ForEach(cats) { c in row(key: c.id, icon: c.icon, name: c.name) }
                }
            }
            .formStyle(.grouped)
            if let error { Text(error).foregroundStyle(Palette.expense).font(.callout).padding(.horizontal, 20) }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving)
            }
            .padding(16)
        }
        .frame(width: 480, height: 600)
        .onAppear { load(); focused = request.focus ?? "" }
        .onChange(of: scope) { load() }
    }

    private func row(key: String, icon: String, name: String) -> some View {
        HStack {
            if key.isEmpty { Image(systemName: "sum").frame(width: 24) } else { CategoryIcon(icon: icon, size: 24, tint: Palette.expense) }
            Text(name).fontWeight(key.isEmpty ? .semibold : .regular)
            Spacer()
            TextField("", text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }), prompt: Text(placeholder(key)))
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
                .focused($focused, equals: key)
        }
    }

    /// In month scope an empty field falls back to the default, shown as the prompt.
    private func placeholder(_ key: String) -> String {
        guard scope == .thisMonth else { return "No budget" }
        let def = model.snapshot.budgets.values.first { ($0.categoryId ?? "") == key && $0.month == nil }
        return def.map { model.money($0.amount, symbol: false) } ?? "No budget"
    }

    private func load() {
        var v: [String: String] = [:]
        let month = scope == .thisMonth ? model.month.key : nil
        for b in model.snapshot.budgets.values where b.month == month {
            v[b.categoryId ?? ""] = Money.format(b.amount, currency: model.currency, symbol: false).replacingOccurrences(of: Locale.current.groupingSeparator ?? ",", with: "")
        }
        values = v
        original = v
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let month = scope == .thisMonth ? model.month : nil
        let keys = Set(values.keys).union(original.keys)
        do {
            for key in keys where (values[key] ?? "") != (original[key] ?? "") {
                let text = values[key] ?? ""
                let amount = text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Money.parse(text)
                guard let amount else { error = "\u{201C}\(text)\u{201D} isn't a valid amount."; return }
                if amount == 0 && (original[key] ?? "").isEmpty { continue } // nothing to remove
                try await model.setBudget(categoryId: key.isEmpty ? nil : key, month: month, amount: amount)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
