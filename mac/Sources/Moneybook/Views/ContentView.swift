import AppKit
import MoneybookCore
import SwiftUI

/// The web app's desktop layout: sidebar with Add, centred content pane, side panels over a dimmed list.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            Sidebar()
            detail
                .frame(maxWidth: 1040)
                .background(MB.bg)
                .overlay(alignment: .leading) { MB.line.frame(width: 0.5) }
                .overlay(alignment: .trailing) { MB.line.frame(width: 0.5) }
                .frame(maxWidth: .infinity)
                .background(MB.desk)
        }
        .overlay {
            panels
                .animation(.easeOut(duration: 0.16), value: model.drawers)
                .animation(.easeOut(duration: 0.16), value: model.editor?.id)
        }
        .ignoresSafeArea()
        .foregroundStyle(MB.fg)
        .tint(MB.accent)
        .onChange(of: model.section) { model.drawers = [] }
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
        case .settings: SettingsHome()
        }
    }

    /// Pushed pages and the entry form slide in from the right over a dimmed window.
    @ViewBuilder private var panels: some View {
        let open = !model.drawers.isEmpty || model.editor != nil
        ZStack(alignment: .trailing) {
            if open {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if model.editor != nil { model.editor = nil } else { model.closeDrawer() }
                    }
                    .transition(.opacity)
            }
            if let top = model.drawers.last {
                DrawerPanel { DrawerContent(drawer: top) }
                    .disabled(model.editor != nil)
                    .id(top)
                    .transition(.move(edge: .trailing))
            }
            if let request = model.editor {
                DrawerPanel { TransactionEditor(request: request) }
                    .id(request.id)
                    .transition(.move(edge: .trailing))
            }
        }
    }
}

/// A 480pt panel on the right edge (`.page.push` on desktop).
struct DrawerPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(width: 480)
            .frame(maxHeight: .infinity)
            .background(MB.bg)
            // A gradient edge instead of a blurred shadow: much cheaper to draw while the panel slides.
            .overlay(alignment: .leading) {
                LinearGradient(colors: [.black.opacity(0.12), .clear], startPoint: .trailing, endPoint: .leading)
                    .frame(width: 14)
                    .offset(x: -14)
                    .allowsHitTesting(false)
            }
    }
}

struct DrawerContent: View {
    var drawer: Drawer
    var body: some View {
        switch drawer {
        case .account(let id): AccountDetailView(accountId: id)
        case .category(let id, let type, let period, let label): CategoryDetailView(categoryId: id, type: type, period: period, label: label)
        case .note(let note, let type, let period): NoteDetailView(note: note, type: type, period: period)
        case .week(let p): WeekDetailView(period: p)
        case .day(let d): DayDetailView(day: d)
        case .search: SearchView()
        case .configuration: SettingsPage(title: "Configuration", parts: [.connection, .preferences])
        case .accountsAdmin: SettingsPage(title: "Accounts", parts: [.accounts, .groups])
        case .categories: SettingsPage(title: "Category", parts: [.categories])
        case .budgetSetting: BudgetSettingView()
        case .aiHelp: AIHelpView()
        }
    }
}

/// `.tabbar` on desktop: brand, Add, and the four tabs.
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                Text("Moneybook").font(.system(size: 17, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 18)

            Button { model.newTransaction() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                    Text("Add").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(MB.accent, in: RoundedRectangle(cornerRadius: 9))
                .shadow(color: MB.accent.opacity(0.3), radius: 3, y: 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New transaction (⌘N)")
            .padding(.bottom, 14)

            ForEach(SidebarSection.allCases) { s in
                SidebarItem(section: s)
            }
            Spacer()
            SyncStatusView().padding(.horizontal, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 44)
        .padding(.bottom, 16)
        .frame(width: 224)
        .frame(maxHeight: .infinity)
        .background(MB.chrome)
        .overlay(alignment: .trailing) { MB.line.frame(width: 0.5) }
    }
}

private struct SidebarItem: View {
    @Environment(AppModel.self) private var model
    var section: SidebarSection
    @UIState private var hover = false

    var body: some View {
        let on = model.section == section
        Button { model.section = section } label: {
            HStack(spacing: 12) {
                Image(systemName: section.symbol).font(.system(size: 16)).frame(width: 21)
                Text(section.title).font(.system(size: 14.5, weight: on ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(on ? MB.accent : MB.fgNote)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(on ? MB.accent.opacity(0.11) : hover ? MB.bg2 : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct SyncStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.medium))
                if let detail { Text(detail).font(.caption2).foregroundStyle(MB.fg2).lineLimit(2) }
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
