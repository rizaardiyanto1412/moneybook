import AppKit
import MoneybookCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`); harmless inside the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        AppModel.shared.start()
        if let dir = SnapshotRunner.directory {
            Task { await SnapshotRunner.run(model: AppModel.shared, dir: dir) }
        } else if SelfTest.enabled {
            Task { await SelfTest.run(model: AppModel.shared) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}

extension AppModel {
    static let shared = AppModel()
}

@main
struct MoneybookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("Moneybook", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1200, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands { MoneybookCommands(model: model) }

        Settings {
            SettingsView(standalone: true)
                .environment(model)
                .frame(width: 640, height: 640)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    var model: AppModel
    var body: some View {
        let spent = Ledger.totals(Ledger.transactions(in: model.currentPeriod, model.snapshot)).expense
        HStack(spacing: 3) {
            Image(systemName: "wallet.bifold")
            Text(Money.format(spent, currency: model.currency))
        }
    }
}

struct MoneybookCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Transaction") { model.section = .transactions; model.newTransaction() }
                .keyboardShortcut("n")
            Button("New Income") { model.section = .transactions; model.newTransaction(type: .income) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("New Transfer") { model.section = .transactions; model.newTransaction(type: .transfer) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        CommandMenu("Go") {
            Button("Previous Period") { model.step(-1) }.keyboardShortcut("[")
            Button("Next Period") { model.step(1) }.keyboardShortcut("]")
            Button("Today") { model.goToToday() }.keyboardShortcut("t")
            Divider()
            ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { i, s in
                Button(s.title) { model.section = s }.keyboardShortcut(KeyEquivalent(Character(String(i + 1))))
            }
            Divider()
            Button("Sync Now") { Task { await model.sync() } }.keyboardShortcut("r")
        }
    }
}
