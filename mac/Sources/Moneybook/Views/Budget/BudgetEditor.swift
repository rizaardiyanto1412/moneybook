import MoneybookCore
import SwiftUI

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
