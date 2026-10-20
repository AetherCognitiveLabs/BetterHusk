// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// What a person can change about how one game runs here, kept in the game's own folder (`settings.json`) so it goes when the game
/// does. Like LiveContainer's per-app settings: each game has its own, and nothing here touches another game.
struct TLAppSettings: Codable, Equatable {
    /// Which way up the screen is while the game runs.
    enum Orientation: String, Codable, CaseIterable, Identifiable {
        /// What the game asks for (its manifest), landscape when it does not say.
        case auto, landscape, portrait
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Automatic"
            case .landscape: return "Landscape"
            case .portrait: return "Portrait"
            }
        }
    }

    /// How many pixels the game draws for each point of the screen. Fewer pixels run faster and take less memory.
    enum Resolution: String, Codable, CaseIterable, Identifiable {
        case low, medium, high, native
        var id: String { rawValue }
        var title: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .native: return "Native"
            }
        }
        var detail: String {
            switch self {
            case .low: return "1 pixel per point. Fastest."
            case .medium: return "1.5 pixels per point."
            case .high: return "2 pixels per point. The default."
            case .native: return "Every pixel the screen has. Sharpest, and heaviest."
            }
        }
        @MainActor var scale: CGFloat {
            switch self {
            case .low: return 1
            case .medium: return 1.5
            case .high: return 2
            case .native: return UIScreen.main.scale
            }
        }
    }

    /// When the on-screen controller is offered.
    enum PadMode: String, Codable, CaseIterable, Identifiable {
        /// For the games that cannot be played without a controller (Unreal, PC games through DXVK), when none is connected.
        case auto, always, never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Automatic"
            case .always: return "Always"
            case .never: return "Never"
            }
        }
    }

    /// Where the app opens: full screen, or a window over Husk that can be moved, resized and minimised (Multitasking).
    enum WindowMode: String, Codable, CaseIterable, Identifiable {
        /// As Settings › Multitasking says for every app.
        case auto, window, fullScreen
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Default"
            case .window: return "Window"
            case .fullScreen: return "Full Screen"
            }
        }
    }

    /// Which of the native runtime's drivers runs the game. Automatic trusts the scan; anything else forces it, for games
    /// whose first screen runs on a different engine than the game itself (a setup or launcher screen on SDL when the game
    /// needs Vulkan, say), which makes detection pick the wrong driver.
    enum Engine: String, Codable, CaseIterable, Identifiable {
        case auto, unity, cocos, minecraft, sdl, gta, ue4, godot, nativeactivity, gamemaker, java, flutter
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Automatic"
            case .unity: return "Unity"
            case .cocos: return "Cocos2d-x"
            case .minecraft: return "Minecraft / GameActivity"
            case .sdl: return "SDL"
            case .gta: return "Rockstar"
            case .ue4: return "Unreal Engine (Vulkan)"
            case .godot: return "Godot"
            case .nativeactivity: return "NativeActivity"
            case .gamemaker: return "GameMaker"
            case .java: return "Java app"
            case .flutter: return "Flutter"
            }
        }
        /// nil when automatic: the scan's answer is used.
        var override: TLNativeEngine? {
            switch self {
            case .auto: return nil
            case .unity: return .unity
            case .cocos: return .cocos
            case .minecraft: return .minecraft
            case .sdl: return .sdl
            case .gta: return .gta
            case .ue4: return .ue4
            case .godot: return .godot
            case .nativeactivity: return .nativeactivity
            case .gamemaker: return .gamemaker
            case .java: return .java
            case .flutter: return .flutter
            }
        }
    }

    var orientation: Orientation = .auto
    var window: WindowMode = .auto
    var resolution: Resolution = .high
    /// The frames-per-second readout in the top bar.
    var showStats = true
    /// Start with nothing over the picture: no bar, no controller, no readout. Three fingers tapped together bring them back.
    var cleanView = false
    /// Stop the screen from dimming and locking while the game is on.
    var keepAwake = true
    var pad: PadMode = .auto
    /// Whether the controller is showing right now (the Pad button in the top bar toggles it).
    var padShown = true
    var padOpacity = 1.0
    var haptics = true
    /// Geometry Dash only: load Geode, its mod loader (Geode.swift).
    var geode = false
    /// Whether guest code can open libvulkan.so -- the closest thing to a renderer choice we control: a game that can draw
    /// with Vulkan and OpenGL ES picks Vulkan when the library answers, OpenGL when it does not (#149). Automatic offers it
    /// on the paths that use it today plus the ones that may probe it (Java-runtime apps, NativeActivity, Godot).
    enum Renderer: String, Codable, CaseIterable, Identifiable {
        case auto, vulkan, gles
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Automatic"
            case .vulkan: return "Vulkan"
            case .gles: return "OpenGL ES"
            }
        }
    }

    /// Forced runtime driver; automatic is the scan's answer.
    var engine: Engine = .auto
    /// Forced graphics API; automatic offers Vulkan where the runtime already supports it.
    var renderer: Renderer = .auto
    /// Diagnostics: Java-runtime games log each touch's route through the windows and dump the view tree every few
    /// seconds. The output lands in the game's run log, which the Technical Details screen already shares (#139).
    var diagnostics = false

    /// Whether guest code can open libvulkan.so for this run, given the engine it will run on: forced by Graphics either
    /// way; automatic offers it on the drivers that can draw with it, and the rest keep their OpenGL ES answer.
    func vulkan(for engine: TLNativeEngine) -> Bool {
        switch renderer {
        case .vulkan: return true
        case .gles: return false
        case .auto: return engine == .sdl || engine == .ue4 || engine == .java || engine == .nativeactivity || engine == .godot || engine == .minecraft
        }
    }

    init() {}

    // Settings written by an older Husk lack the keys a newer one added; each falls back to its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orientation = try c.decodeIfPresent(Orientation.self, forKey: .orientation) ?? .auto
        resolution = try c.decodeIfPresent(Resolution.self, forKey: .resolution) ?? .high
        showStats = try c.decodeIfPresent(Bool.self, forKey: .showStats) ?? true
        cleanView = try c.decodeIfPresent(Bool.self, forKey: .cleanView) ?? false
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        pad = try c.decodeIfPresent(PadMode.self, forKey: .pad) ?? .auto
        padShown = try c.decodeIfPresent(Bool.self, forKey: .padShown) ?? true
        padOpacity = try c.decodeIfPresent(Double.self, forKey: .padOpacity) ?? 1.0
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        geode = try c.decodeIfPresent(Bool.self, forKey: .geode) ?? false
        window = try c.decodeIfPresent(WindowMode.self, forKey: .window) ?? .auto
        engine = try c.decodeIfPresent(Engine.self, forKey: .engine) ?? .auto
        renderer = try c.decodeIfPresent(Renderer.self, forKey: .renderer) ?? .auto
        diagnostics = try c.decodeIfPresent(Bool.self, forKey: .diagnostics) ?? false
    }

    private static func url(_ id: String) -> URL {
        TranslationLayer.root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("settings.json")
    }

    static func load(_ id: String) -> TLAppSettings {
        (try? Data(contentsOf: url(id))).flatMap { try? JSONDecoder().decode(TLAppSettings.self, from: $0) } ?? TLAppSettings()
    }

    func save(_ id: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // The folder is gone when the app was removed while its settings page was open.
        guard FileManager.default.fileExists(atPath: Self.url(id).deletingLastPathComponent().path),
              let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.url(id), options: .atomic)
    }
}

// MARK: - The settings page

/// One game's settings, opened from its page or from its tile's menu.
struct TLAppSettingsView: View {
    let app: TLApp

    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var geode = GeodeSupport.shared
    @State private var settings: TLAppSettings
    @State private var name: String
    @State private var dataSize: String = "…"
    @State private var confirmReset = false
    @FocusState private var nameFocused: Bool

    init(app: TLApp) {
        self.app = app
        _settings = State(initialValue: TLAppSettings.load(app.id))
        _name = State(initialValue: app.label)
    }

    /// The game is loaded in this run of Husk, so what it keeps cannot be swapped from under it.
    private var inUse: Bool {
        guard let loaded = husk_native_loaded_apk().map({ String(cString: $0) }), let apk = app.apks.first else { return false }
        return loaded == apk
    }

    private var dataDirs: [URL] {
        let dir = TranslationLayer.root.appendingPathComponent(app.id, isDirectory: true)
        return ["unity-data", "cocos-data", "minecraft-data", "sdl-data", "ue4-data", "gta-data", "na-data", "godot-data", "flutter-data", "gm-data", "web"]
            .map { dir.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AppIcon(path: app.iconPath, size: 52)
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { rename() }
                        .font(.system(size: 18, weight: .semibold))
                }
                .padding(.vertical, 2)
            } footer: {
                Text("What the game is called in Husk. The game itself is not changed.")
            }

            Section {
                Picker("Orientation", selection: $settings.orientation) {
                    ForEach(TLAppSettings.Orientation.allCases) { Text($0.title).tag($0) }
                }
                Picker("Resolution", selection: $settings.resolution) {
                    ForEach(TLAppSettings.Resolution.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Performance readout", isOn: $settings.showStats)
                Toggle("Keep the screen on", isOn: $settings.keepAwake)
            } header: {
                Text("Display")
            } footer: {
                Text("\(settings.resolution.detail) Orientation and resolution apply the next time the game starts, and a game already running in this session needs Husk closed and opened again.")
            }

            Section {
                Picker("Runs as", selection: $settings.engine) {
                    ForEach(TLAppSettings.Engine.allCases) { Text($0.title).tag($0) }
                }
                Picker("Graphics", selection: $settings.renderer) {
                    ForEach(TLAppSettings.Renderer.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Engine")
            } footer: {
                Text("BetterHusk detects \(app.label) as \(app.report?.nativeEngineName ?? "an unknown engine"). Pick another only when detection is wrong — a setup or launcher screen can look like a different engine than the game itself, and a wrong driver usually crashes. Graphics decides whether the game is told Vulkan exists here: OpenGL ES hides it, for games that prefer it but then crash. Applies the next time the game starts.")
            }

            Section {
                Toggle("Diagnostics", isOn: $settings.diagnostics)
            } footer: {
                Text("For a game that runs in Husk's own Java runtime: every touch writes the window it went to and the view that answered, and the view tree is printed every few seconds — all into the run log, which Technical Details can share. Leave it off while playing normally; the writes cost a little speed.")
            }

            Section {
                Picker("Open In", selection: $settings.window) {
                    ForEach(TLAppSettings.WindowMode.allCases) { m in
                        Text(m == .auto ? String(localized: "Default (\(AppWindows.defaultWindowed ? "Window" : "Full Screen"))") : m.title.l10n).tag(m)
                    }
                }
            } header: {
                Text("Multitasking")
            } footer: {
                Text("In a window, \(app.label) runs over Husk: move it by its title bar, resize it from the corner, and minimise it to the dock at the edge of the screen while you use the rest of Husk.")
            }

            Section {
                Toggle("Hide the interface", isOn: $settings.cleanView)
            } header: {
                Text("Screenshots")
            } footer: {
                Text("The game starts with nothing over it: no bar, no controller, no readout. Tap with three fingers at once to bring the bar back, and again to hide it. The Hide button in the bar does the same while playing.")
            }

            if app.packageName == GeodeSupport.gamePackage {
                Section {
                    Toggle("Geode", isOn: $settings.geode)
                    if settings.geode { geodeStatus }
                } header: {
                    Text("Mods")
                } footer: {
                    Text("Geode is the mod loader for Geometry Dash. With it on, Husk downloads Geode for this version of the game, and mods are found and installed in the game itself, from Geode's button on the main menu. Applies the next time the game starts.")
                }
            }

            Section {
                Picker("On-screen controller", selection: $settings.pad) {
                    ForEach(TLAppSettings.PadMode.allCases) { Text($0.title).tag($0) }
                }
                if settings.pad != .never {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Opacity")
                        Slider(value: $settings.padOpacity, in: 0.3...1)
                    }
                    Toggle("Vibrate on a press", isOn: $settings.haptics)
                }
            } header: {
                Text("Controller")
            } footer: {
                Text("Automatic offers the controller for games that cannot be played without one (Unreal Engine games), when no real controller is connected. Always offers it for any game that understands one. A paired controller is always used.")
            }

            Section {
                Button { AppClip.generate(for: app) } label: {
                    Label("Generate App Clip", systemImage: "apps.iphone.badge.plus")
                }
            } header: {
                Text("Home Screen")
            } footer: {
                Text("Puts \(app.label) on your Home Screen with its own icon. Tapping it opens Husk straight into the game. Husk downloads a profile: open Settings, tap Profile Downloaded, then Install.")
            }

            Section {
                DetailRow(label: "Saved by the game", value: dataSize, mono: false)
                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Reset Game Data", systemImage: "arrow.counterclockwise")
                }
                .disabled(inUse || dataDirs.isEmpty)
            } header: {
                Text("Data")
            } footer: {
                Text(inUse ? "The game is loaded in this session. Close Husk completely and open it again to reset its data."
                           : "Deletes what the game saved and downloaded here: saves, settings and caches. The game itself stays.")
            }
        }
        .huskForm()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings) { $0.save(app.id) }
        .onChange(of: settings.geode) { on in
            if on { Task { await geode.prepare(app) } } else { geode.remove(app) }
        }
        .onChange(of: nameFocused) { focused in if !focused { rename() } }
        .onDisappear { rename() }
        .task { dataSize = await Self.measure(dataDirs) }
        .confirmationDialog("Reset the data of \(app.label)?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Game Data", role: .destructive) {
                for dir in dataDirs { try? FileManager.default.removeItem(at: dir) }
                HuskLog.log("tl", "reset the data of \(app.label)")
                Task { dataSize = await Self.measure(dataDirs) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saves, settings and caches the game made here are deleted.")
        }
    }

    @ViewBuilder
    private var geodeStatus: some View {
        switch geode.current(app) {
        case .idle:
            Button("Download Geode") { Task { await geode.prepare(app) } }
        case .working(let what):
            HStack(spacing: 10) { ProgressView(); Text(what.l10n).foregroundStyle(.secondary) }
        case .ready(let version):
            LabeledContent("Geode", value: String(localized: "v\(version), ready"))
        case .failed(let why):
            VStack(alignment: .leading, spacing: 6) {
                Text(why.l10n).font(.footnote).foregroundStyle(.orange)
                Button("Try Again") { Task { await geode.prepare(app) } }
            }
        }
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != app.label else { return }
        store.rename(app, to: trimmed)
    }

    private static func measure(_ dirs: [URL]) async -> String {
        await Task.detached(priority: .utility) {
            var bytes: Int64 = 0
            for dir in dirs {
                let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
                while let url = walker?.nextObject() as? URL {
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if values?.isRegularFile == true { bytes += Int64(values?.fileSize ?? 0) }
                }
            }
            return bytes == 0 ? "nothing" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }.value
    }
}
