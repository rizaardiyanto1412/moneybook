import MoneybookCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: Binding($model.section)) {
                ForEach(SidebarSection.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .top) { SidebarMonthCard().padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6) }
            .safeAreaInset(edge: .bottom) { SyncStatusView().padding(12) }
        } detail: {
            detail
                .toolbar { toolbarContent }
                .toolbar(removing: .title)
        }
        .sheet(item: $model.editor) { request in
            TransactionEditor(request: request)
        }
        .alert("Moneybook", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .transactions: TransactionsView()
        case .stats: StatsView()
        case .accounts: AccountsView()
        case .budget: BudgetView()
        case .settings: SettingsView()
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if model.section != .settings {
            ToolbarItem(placement: .navigation) {
                MonthNavigator()
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.newTransaction()
            } label: {
                Label("New Transaction", systemImage: "plus")
            }
            .help("New transaction (⌘N)")
        }
    }
}

struct MonthNavigator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            ControlGroup {
                Button { model.step(-1) } label: { Image(systemName: "chevron.left") }
                    .help(model.navigatesByYear ? "Previous year (⌘[)" : "Previous month (⌘[)")
                Button { model.step(1) } label: { Image(systemName: "chevron.right") }
                    .help(model.navigatesByYear ? "Next year (⌘])" : "Next month (⌘])")
            }
            .fixedSize()
            Text(model.navigatesByYear ? String(model.month.year) : Fmt.monthTitle(model.month))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 120, alignment: .leading)
                .help(model.navigatesByYear ? Fmt.range(model.yearPeriod) : Fmt.range(model.period))
            if !model.isCurrentMonth {
                Button("Today") { model.goToToday() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .help("Jump to the current month (⌘T)")
            }
        }
        .padding(.horizontal, 4)
    }
}

struct SyncStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.medium))
                if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
            if model.isSyncing { ProgressView().controlSize(.mini) }
        }
        .help(helpText)
        .contentShape(Rectangle())
        .onTapGesture { Task { await model.sync() } }
    }

    private var color: Color {
        switch model.connection {
        case .online: .green
        case .connecting: .yellow
        case .offline: .orange
        case .unconfigured: .gray
        }
    }
    private var title: String {
        switch model.connection {
        case .online: "Synced"
        case .connecting: "Connecting…"
        case .offline: "Offline"
        case .unconfigured: "Not connected"
        }
    }
    private var detail: String? {
        switch model.connection {
        case .online: model.lastSync.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" }
        case .offline: "Showing cached data"
        case .unconfigured: "Set up the server in Settings"
        case .connecting: nil
        }
    }
    private var helpText: String {
        if case .offline(let msg) = model.connection { return msg + "\nClick to retry." }
        return "Click to sync now (⌘R)"
    }
}

/// "This month" glance at the top of the sidebar: spent so far against income.
struct SidebarMonthCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let t = Ledger.totals(Ledger.transactions(in: model.currentPeriod, model.snapshot))
        VStack(alignment: .leading, spacing: 6) {
            Text("Spent in \(Fmt.monthName(model.currentMonth))").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(model.money(t.expense))
                .font(.money(18, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if t.income > 0 {
                ProgressBar(ratio: t.expense / t.income, tint: t.expense > t.income ? Palette.expense : .accentColor, height: 4)
                Text("\(model.money(max(t.income - t.expense, 0))) left of income").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            model.goToToday()
            model.section = .transactions
        }
        .help("Open this month's transactions")
    }
}
