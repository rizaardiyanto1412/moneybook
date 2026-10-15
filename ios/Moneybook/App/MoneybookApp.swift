import MoneybookCore
import SwiftUI

@main
struct MoneybookApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(MM.accent)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.setActive(phase == .active)
        }
    }
}

enum AppTab: String, Hashable, CaseIterable {
    case trans, stats, accounts, more
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Self.initialTab

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .top) {
            if model.isSignedIn {
                // All four stacks stay alive so each keeps its place, like the tabs in Money Manager.
                ZStack {
                    ForEach(AppTab.allCases, id: \.self) { t in
                        NavigationStack { root(t) }
                            .opacity(tab == t ? 1 : 0)
                            .allowsHitTesting(tab == t)
                    }
                }
                .fullScreenCover(item: $model.editor) { EntryView(request: $0) }
                #if DEBUG
                .task {
                    let d = UserDefaults.standard
                    if d.bool(forKey: "openEditor") { model.newTransaction() }
                    if d.bool(forKey: "editLatest"), let t = model.snapshot.transactions.values.sorted(by: Ledger.sortDescending).first { model.edit(t.id) }
                }
                #endif
            } else {
                LoginView()
            }
            if let msg = model.toastMessage {
                Text(msg)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.12, opacity: 0.92), in: Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(10)
            }
        }
        .animation(.spring(duration: 0.3), value: model.toastMessage)
        .alert("Moneybook", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// Each tab's root page with the tab bar under it; pushed pages cover the bar, as in the app.
    @ViewBuilder private func root(_ t: AppTab) -> some View {
        Group {
            switch t {
            case .trans: TransactionsTab()
            case .stats: StatsTab()
            case .accounts: AccountsTab()
            case .more: SettingsTab()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(MM.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) { TabBar(selection: $tab) }
    }

    /// `-tab stats` (launch argument) opens on another tab, for simulator screenshots.
    private static var initialTab: AppTab {
        #if DEBUG
        UserDefaults.standard.string(forKey: "tab").flatMap(AppTab.init(rawValue:)) ?? .trans
        #else
        .trans
        #endif
    }
}

struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            item(.trans, todayLabel, "book")
            item(.stats, "Stats", "stats")
            item(.accounts, "Accounts", "accounts")
            item(.more, "Settings", "gear")
        }
        .frame(height: 52)
        .background(MM.tabBar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
    }

    /// Money Manager labels the first tab with today's date, e.g. "10/14".
    private var todayLabel: String { Fmt.md(Periods.today()) }

    private func item(_ t: AppTab, _ label: String, _ icon: String) -> some View {
        Button { selection = t } label: {
            VStack(spacing: 3) {
                Icon(icon, size: 25)
                Text(label).font(.system(size: 11))
            }
            .foregroundStyle(selection == t ? MM.accent : MM.tabIdle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The coral "+" above the tab bar.
struct Fab: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Icon("plus", size: 26)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(MM.accent, in: Circle())
                .shadow(color: MM.accent.opacity(0.35), radius: 4, y: 3)
        }
        .buttonStyle(FabStyle())
        .padding(.trailing, 18)
        .padding(.bottom, 18)
        .accessibilityLabel("Add transaction")
    }
}

private struct FabStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
