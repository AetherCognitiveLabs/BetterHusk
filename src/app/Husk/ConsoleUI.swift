// SPDX-License-Identifier: GPL-2.0-or-later
// The console-style shell: the floating dock that replaces the tab bar, the platform chips, the status dot, and what Home and
// the Library need to know about an item's platform. Flat dark surfaces throughout -- no glass, no coloured washes.
import SwiftUI
import UIKit

// MARK: - palette

enum Console {
    /// The page: plain black.
    static let page = Color.black
    /// Cards and wells on the page.
    static let card = Color(white: 0.11)
    /// One step up from a card: the dock, buttons on artwork.
    static let raised = Color(white: 0.16)
    static let hairline = Color.white.opacity(0.08)
    static let textDim = Color.white.opacity(0.6)
    static let dockHeight: CGFloat = 60
}

// MARK: - platform

/// The platform chips: everything, Android (the translation layer and the emulator's apps), or PS4.
enum PlatformFilter: String, CaseIterable, Identifiable {
    case all, android, ps4
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .android: return "Android"
        case .ps4: return "PS4"
        }
    }

    func includes(_ item: LibraryItem) -> Bool {
        switch self {
        case .all: return true
        case .android: return !item.isPS4
        case .ps4: return item.isPS4
        }
    }
}

/// How an item runs, as a dot and a word: from this iPhone's own record first, then the compatibility list.
struct ItemStatus: Equatable {
    let label: String
    let color: Color

    static let plays = ItemStatus(label: "Plays", color: .green)
    static let opens = ItemStatus(label: "Opens", color: .orange)
    static let broken = ItemStatus(label: "Broken", color: .red)
    static let protected = ItemStatus(label: "Protected", color: .gray)
}

extension LibraryItem {
    var isPS4: Bool { if case .ps4 = self { return true }; return false }

    /// The platform line over the title on Home.
    var platformName: String {
        switch self {
        case .ps4: return "PlayStation 4"
        case .app: return "Android · Emulator"
        case .android: return "Android"
        case .game: return "Android"
        }
    }

    /// The dot: green Plays, orange Opens, red Broken. Nothing when nobody knows.
    @MainActor var status: ItemStatus? {
        if case .game(let g) = self, let r = GameStatusStore.shared.status(g.id)?.result {
            switch r {
            case .plays: return .plays
            case .crashed: return .opens
            case .failed: return .broken
            }
        }
        switch CompatibilityStore.shared.entry(packageName)?.status {
        case .works?: return .plays
        case .opens?: return .opens
        case .broken?: return .broken
        case .protected?: return .protected
        case nil: return nil
        }
    }

    /// "Last played 2 hours ago", or nothing for what was never opened from Husk.
    var lastPlayedText: String? {
        guard let date = lastUsed else { return nil }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
        let ago = date.timeIntervalSinceNow > -60 ? "just now" : rel.localizedString(for: date, relativeTo: Date())
        return (isGame ? "Last played " : "Last opened ") + ago
    }

    /// When it was added to Husk, from its folder: what "Recently added" sorts by.
    var addedDate: Date? {
        let path: String
        switch self {
        case .game(let g): path = TranslationLayer.root.appendingPathComponent(g.id).path
        case .ps4(let g): path = g.folder.path
        default: return nil
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.creationDate] as? Date) ?? (attrs?[.modificationDate] as? Date)
    }
}

struct StatusDot: View {
    let status: ItemStatus
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(status.color).frame(width: size, height: size)
    }
}

// MARK: - chips

/// A platform chip: white fill when selected, a dark well otherwise.
struct ConsoleChip: View {
    let title: String
    let selected: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 13 : 14, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, compact ? 11 : 14)
                .frame(height: compact ? 28 : 32)
                .background(selected ? Color.white : Color.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PlatformChips: View {
    @Binding var selection: PlatformFilter
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PlatformFilter.allCases) { f in
                ConsoleChip(title: f.title, selected: selection == f, compact: compact) {
                    withAnimation(.easeOut(duration: 0.18)) { selection = f }
                }
            }
        }
    }
}

// MARK: - dock

/// Whether the keyboard is up: the dock steps aside for it rather than riding on top of it.
@MainActor final class KeyboardWatch: ObservableObject {
    static let shared = KeyboardWatch()
    @Published private(set) var visible = false
    private var tokens: [NSObjectProtocol] = []

    private init() {
        let nc = NotificationCenter.default
        tokens.append(nc.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.visible = true }
        })
        tokens.append(nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.visible = false }
        })
    }
}

extension HuskTab {
    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .store: return "Store"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "square.grid.2x2.fill"
        case .store: return "bag.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// The floating dock: a dark capsule with the four tabs, the selected one lifted onto a lighter pill.
struct ConsoleDock: View {
    @ObservedObject private var router = Router.shared
    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HuskTab.allCases) { tab in
                let selected = router.tab == tab
                Button {
                    if selected {
                        // Tapping the tab you are on goes back to its top, as a tab bar does.
                        switch tab {
                        case .home: router.home = []
                        case .library: router.library = []
                        default: break
                        }
                    } else {
                        router.tab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selected ? theme.accentColor : Color.white.opacity(0.55))
                        if selected {
                            Text(tab.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, selected ? 14 : 12)
                    .frame(height: 42)
                    .frame(minWidth: 48)
                    .background(selected ? Console.raised.opacity(1) : Color.clear, in: Capsule())
                    .overlay(Capsule().stroke(selected ? Color.white.opacity(0.10) : .clear, lineWidth: 0.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Color(white: 0.07), in: Capsule())
        .overlay(Capsule().stroke(Console.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
        .animation(.snappy(duration: 0.22), value: router.tab)
    }
}

// MARK: - shell

/// The four tabs without the system's tab bar: each is mounted the first time it is shown and then kept, hidden, so its
/// pushed pages survive switching away -- what TabView did, minus the bar.
struct ConsoleShell: View {
    @ObservedObject private var router = Router.shared
    @ObservedObject private var keyboard = KeyboardWatch.shared
    @State private var visited: Set<HuskTab> = [Router.shared.tab]

    var body: some View {
        ZStack {
            Console.page.ignoresSafeArea()
            ForEach(HuskTab.allCases) { tab in
                if visited.contains(tab) || router.tab == tab {
                    page(tab)
                        .opacity(router.tab == tab ? 1 : 0)
                        .allowsHitTesting(router.tab == tab)
                        .accessibilityHidden(router.tab != tab)
                        .zIndex(router.tab == tab ? 1 : 0)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboard.visible {
                ConsoleDock()
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: keyboard.visible)
        .onChange(of: router.tab) { visited.insert($0) }
        // Husk's console look is dark whatever the phone is set to: artwork on black.
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func page(_ tab: HuskTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .library: LibraryScreen()
        case .store: StoreView()
        case .settings: SettingsTab()
        }
    }
}
