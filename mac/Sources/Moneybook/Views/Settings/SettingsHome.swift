import AppKit
import MoneybookCore
import SwiftUI

/// Settings tab: connection card and Money Manager's icon grid (web/js/views/more.js).
struct SettingsHome: View {
    @Environment(AppModel.self) private var model

    private let tiles: [(String, String, Drawer?)] = [
        ("Configuration", "gearshape", .configuration), ("Accounts", "creditcard", .accountsAdmin),
        ("Budget", "chart.pie", .budgetSetting), ("Category", "list.bullet", .categories(.expense)),
        ("Sync", "arrow.triangle.2.circlepath", nil), ("AI Assistant", "sparkles", .aiHelp),
    ]

    var body: some View {
        VStack(spacing: 0) {
            MBHeader(title: "Settings").background(MB.chrome)
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Circle().fill(dot).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host).font(.system(size: 14, weight: .medium))
                            Text(status).font(.system(size: 12)).foregroundStyle(MB.fg3)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(MB.line, lineWidth: 0.5))
                    .padding(.horizontal, 30)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { model.open(.configuration) }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 6), spacing: 0) {
                        ForEach(tiles, id: \.0) { title, symbol, drawer in
                            Tile(title: title, symbol: symbol) {
                                if let drawer { model.open(drawer) } else { Task { await model.sync() } }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)

                    Text("Moneybook for Mac").font(.system(size: 12)).foregroundStyle(MB.fg3).padding(.top, 8)
                }
            }
        }
    }

    private var host: String { URL(string: model.serverURL)?.host ?? (model.serverURL.isEmpty ? "No server" : model.serverURL) }
    private var dot: Color {
        switch model.connection {
        case .online: .green
        case .offline: MB.exp
        default: MB.fg3
        }
    }
    private var status: String {
        switch model.connection {
        case .offline(let msg): return msg
        case .unconfigured: return "Click to set up the server and API token"
        case .connecting: return "Connecting…"
        case .online:
            let t = model.lastSync?.formatted(date: .omitted, time: .shortened) ?? "never"
            return "Synced \(t) · \(model.snapshot.transactions.count) transactions"
        }
    }
}

/// `.cgrid button`: icon over label.
private struct Tile: View {
    var title: String
    var symbol: String
    var action: () -> Void
    @UIState private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 24, weight: .light)).frame(height: 27)
                Text(title).font(.system(size: 12.5))
            }
            .foregroundStyle(MB.fgNote)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(hover ? MB.bg2 : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// A settings side panel holding some of the native settings sections.
struct SettingsPage: View {
    var title: String
    var parts: [SettingsView.Part]
    var body: some View {
        VStack(spacing: 0) {
            DrawerHeader(title: title)
            SettingsView(parts: parts)
        }
    }
}

/// Budget amounts for the month; click a line to edit.
struct BudgetSettingView: View {
    @Environment(AppModel.self) private var model
    @UIState private var editing: BudgetEditRequest?

    var body: some View {
        let lines = Ledger.budgetLines(model.snapshot, month: model.month)
        VStack(spacing: 0) {
            DrawerHeader(title: "Budget Setting") {
                HeaderTextButton(title: "Edit") { editing = BudgetEditRequest(focus: nil) }
            }
            MonthSwitcher(label: Fmt.monthLabel(model.month), onPrev: { model.month = model.month.adding(months: -1) },
                          onNext: { model.month = model.month.adding(months: 1) }, onLabel: { model.goToToday() })
                .bottomLine()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(lines) { line in
                        HStack(spacing: 12) {
                            if !line.icon.isEmpty { Text(line.icon).font(.system(size: 20)).frame(width: 28) }
                            Text(line.categoryId == nil ? "Total" : line.name).fontWeight(line.categoryId == nil ? .semibold : .regular)
                            Spacer()
                            Text(line.budget > 0 ? model.money(line.budget) : "—").monospacedDigit().foregroundStyle(MB.fg2)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(MB.fg3)
                        }
                        .font(.system(size: 15))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .bottomLine()
                        .rowHover()
                        .onTapGesture { editing = BudgetEditRequest(focus: line.categoryId) }
                    }
                }
            }
        }
        .sheet(item: $editing) { BudgetEditor(request: $0) }
    }
}

/// How to connect an AI assistant over MCP.
struct AIHelpView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let url = model.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/mcp"
        VStack(spacing: 0) {
            DrawerHeader(title: "AI Assistant")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your AI assistant can add and read transactions through MCP. Add this server as a custom MCP connector:")
                    Text(url)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MB.bg2, in: RoundedRectangle(cornerRadius: 8))
                    Button("Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    }
                    Text("Authenticate with your API token as a Bearer token. Expenses it adds show up here within about 10 seconds, marked with ✦.")
                        .foregroundStyle(MB.fg2)
                }
                .font(.system(size: 15))
                .lineSpacing(3)
                .padding(16)
            }
        }
    }
}
