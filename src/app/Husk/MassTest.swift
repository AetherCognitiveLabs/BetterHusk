import SwiftUI
import UIKit

/// The developer mass test: every APK in a folder the user makes in Husk's Files folder, `DeveloperTesting`, tried one per launch
/// of Husk (one game per run is all Husk can load). Each launch takes the next APK in, waits for JIT and a few seconds more, plays
/// it, watches it for a while, writes down what happened -- it runs, it started and then stopped, it never started, or Husk itself
/// went down with it (found on the next launch) -- and closes Husk. The user opens Husk again for the next one. At the end the
/// results, with each app's diagnosis and the end of its log, are one file to share.
@MainActor
final class MassTest: ObservableObject {
    static let shared = MassTest()

    /// The user's folder. Husk never makes it: its being there, with APKs in it, is what turns the test on.
    static var folder: URL { docs.appendingPathComponent("DeveloperTesting", isDirectory: true) }
    static var resultsURL: URL { docs.appendingPathComponent("DeveloperTesting Results.txt") }
    private static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private static var stateURL: URL { docs.appendingPathComponent(".husk-masstest.json") }

    /// How long a started app is watched before it counts as running, and how long one that never starts is waited for.
    private static let watchSeconds = 45.0
    private static let startTimeout = 120.0
    /// After JIT is on: a few seconds for the rest of Husk to settle before the app is played.
    private static let settleSeconds = 5.0

    struct Result: Codable {
        var file: String
        var label: String
        var package: String
        var engine: String
        var outcome: String
        var frames: UInt
        var seconds: Double
        var diagnosis: String
        var log: [String]
    }
    struct State: Codable {
        var queue: [String]
        var index: Int
        var results: [Result]
        var appIDs: [String: String]        // APK file name -> its app in the library
        var launched: Bool                  // the current one was played in the run that wrote this
        var startedAt: Date
    }

    @Published private(set) var state: State?
    @Published var shareResults = false
    @Published private(set) var status = ""

    /// One app per run of Husk: set once this run has resumed or started the test.
    private var ranThisProcess = false

    private init() { state = Self.load() }

    var active: Bool { state.map { $0.index < $0.queue.count } ?? false }

    /// The APKs (and app bundles) in the folder, in name order; nil if the folder is not there.
    static func apks() -> [String]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        return names.filter { ["apk", "xapk", "apks", "apkm"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
    }

    // MARK: - Starting and stopping

    func start() {
        guard let files = Self.apks(), !files.isEmpty else { status = "Put APKs in the DeveloperTesting folder first."; return }
        guard !ranThisProcess, husk_native_loaded_apk() == nil else { status = "Close Husk and open it again to start: a game was already loaded in this run."; return }
        ranThisProcess = true
        state = State(queue: files, index: 0, results: [], appIDs: [:], launched: false, startedAt: Date())
        save()
        HuskLog.log("masstest", "started: \(files.count) APKs")
        runCurrent()
    }

    func stop() {
        HuskLog.log("masstest", "stopped by the user")
        if var s = state { s.queue = Array(s.queue.prefix(s.index)); s.launched = false; state = s; save() }
        writeReport()
    }

    // MARK: - Each launch

    /// At launch, before Husk opens anything else: the previous app's fate if Husk went down with it, then the next app.
    func resume(crash: CrashReport) {
        guard !ranThisProcess, var s = state, s.index < s.queue.count else { return }
        ranThisProcess = true
        if s.launched {
            // Played in the last run and never written down: Husk did not survive it.
            let file = s.queue[s.index]
            var outcome = "Husk closed without a record (iOS memory limit, or swiped away)"
            var diagnosis = ""
            var lines = Self.tail(of: CrashReport.previousLogURL, 80)
            if let r = crash.pending {
                outcome = "Husk crashed: \(r.cause.title)"
                diagnosis = r.cause.detail
                if !r.excerpt.isEmpty { lines = r.excerpt }
            }
            lines += ["--- native log ---"] + Self.tail(of: Self.docs.appendingPathComponent("husk-native-prev.log"), 120)
            let app = s.appIDs[file].flatMap { id in TranslationLayerStore.shared.apps.first { $0.id == id } }
            s.results.append(Result(file: file, label: app?.label ?? file, package: app?.packageName ?? "", engine: Self.engineName(app),
                                    outcome: outcome, frames: 0, seconds: 0, diagnosis: diagnosis, log: lines))
            s.index += 1
            s.launched = false
            state = s
            save()
            crash.pending = nil
            HuskLog.log("masstest", "\(file): \(outcome)")
        }
        if active { runCurrent() } else { writeReport(); shareResults = true }
    }

    private func runCurrent() {
        guard var s = state, s.index < s.queue.count else { writeReport(); shareResults = true; return }
        let file = s.queue[s.index]
        status = "Testing \(s.index + 1) of \(s.queue.count): \(file)"
        HuskLog.log("masstest", status)
        Task {
            // Taken into the library once; a later launch for the same APK (after a crash) finds it there.
            var id = s.appIDs[file]
            if id == nil || !FileManager.default.fileExists(atPath: TranslationLayer.root.appendingPathComponent(id!).path) {
                let url = Self.folder.appendingPathComponent(file)
                id = await Task.detached(priority: .userInitiated) { TranslationLayerStore.importCopy(url) }.value
            }
            guard let appID = id else { record(file: file, app: nil, outcome: "Could not be imported (not an APK Husk can read)", frames: 0, seconds: 0); return }
            s.appIDs[file] = appID
            state = s
            save()
            TranslationLayerStore.shared.reload()
            // JIT first (this test is about the phone), then a few seconds more.
            while !Launcher.jitOn { try? await Task.sleep(nanoseconds: 500_000_000) }
            try? await Task.sleep(nanoseconds: UInt64(Self.settleSeconds * 1e9))
            guard let app = TranslationLayerStore.shared.apps.first(where: { $0.id == appID }) else {
                record(file: file, app: nil, outcome: "Imported, but not in the library", frames: 0, seconds: 0); return
            }
            if let d = AppDiagnosis.preflight(app), d.blocksLaunch {
                record(file: file, app: app, outcome: "Not started: \(d.title)", frames: 0, seconds: 0, diagnosis: d.detail); return
            }
            var st = state!
            st.launched = true
            state = st
            save()
            HuskLog.flushNow()
            let router = Router.shared
            router.tab = .library
            router.library = [.game(appID)]
            router.autoPlay = appID
            await watch(file: file, app: app)
        }
    }

    /// What the runtime says while the app runs: started, frames, stopped.
    private func watch(file: String, app: TLApp) async {
        let t0 = Date()
        var startedAt: Date?
        while true {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let st = husk_unity_state(), frames = husk_unity_frames()
            let started = st != 0 || husk_native_loaded_apk() != nil
            if started, startedAt == nil { startedAt = Date() }
            let ran = startedAt.map { Date().timeIntervalSince($0) } ?? 0
            if st == Int32(HUSK_UNITY_FAILED) || st == Int32(HUSK_UNITY_ENDED) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let f = husk_unity_frames()
                let outcome = st == Int32(HUSK_UNITY_FAILED) ? "Could not start"
                            : f > 30 ? "Started, then stopped" : "Crashed at start"
                record(file: file, app: app, outcome: outcome, frames: f, seconds: ran)
                return
            }
            if startedAt != nil, ran >= Self.watchSeconds {
                let outcome = st == Int32(HUSK_UNITY_RUNNING)
                    ? (frames >= 300 ? "Runs" : frames > 0 ? "Runs, but drew few frames (\(frames))" : "Runs, but drew nothing")
                    : st == Int32(HUSK_UNITY_STARTING) ? "Still loading after \(Int(ran)) s" : "Running (no frame count for this kind of app)"
                record(file: file, app: app, outcome: outcome, frames: frames, seconds: ran)
                return
            }
            if startedAt == nil, Date().timeIntervalSince(t0) > Self.startTimeout {
                record(file: file, app: app, outcome: "Never started (\(Int(Self.startTimeout)) s)", frames: 0, seconds: 0)
                return
            }
        }
    }

    /// Writes one app's result and closes Husk, so the next launch is a fresh process for the next app.
    private func record(file: String, app: TLApp?, outcome: String, frames: UInt, seconds: Double, diagnosis: String? = nil) {
        guard var s = state else { return }
        var log: [String] = []
        if let c = husk_tl_attempt_log() { log = String(cString: c).components(separatedBy: "\n").suffix(150).map { String($0) }; free(c) }
        let d = diagnosis ?? AppDiagnosis.ofCurrentRun().map { "\($0.title): \($0.detail)" + ($0.evidence.map { " [\($0)]" } ?? "") } ?? ""
        s.results.append(Result(file: file, label: app?.label ?? file, package: app?.packageName ?? "", engine: Self.engineName(app),
                                outcome: outcome, frames: frames, seconds: seconds, diagnosis: d, log: log))
        s.index += 1
        s.launched = false
        state = s
        save()
        writeReport()
        HuskLog.log("masstest", "\(file): \(outcome)")
        HuskLog.flushNow()
        CrashReport.gameEnded()
        // A moment for the files to land, then out: one app per run of Husk.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
    }

    // MARK: - Files

    private static func engineName(_ app: TLApp?) -> String {
        guard let app else { return "" }
        if let w = app.report?.webKind { return "web (\(w))" }
        return app.report?.nativeEngine.map { "\($0)" } ?? "classic"
    }

    private static func tail(of url: URL, _ n: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").suffix(n).map { String($0) }
    }

    /// The human-readable results: a summary table, then each app in full.
    func writeReport() {
        guard let s = state else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let commit = Bundle.main.object(forInfoDictionaryKey: "HuskBuildCommit") as? String ?? "?"
        var out = "Husk mass test -- build \(build) (\(commit)), \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)\n"
        out += "Started \(f.string(from: s.startedAt)); \(s.results.count) of \(s.queue.count) tested\n\n"
        for r in s.results { out += "\(r.outcome.padding(toLength: 44, withPad: " ", startingAt: 0))  \(r.file)  [\(r.engine)]\n" }
        for r in s.results {
            out += "\n==================== \(r.file)\n"
            out += "label: \(r.label)\npackage: \(r.package)\nengine: \(r.engine)\noutcome: \(r.outcome)\nframes: \(r.frames)  watched: \(Int(r.seconds)) s\n"
            if !r.diagnosis.isEmpty { out += "diagnosis: \(r.diagnosis)\n" }
            out += "--- log (last lines) ---\n" + r.log.joined(separator: "\n") + "\n"
        }
        try? out.write(to: Self.resultsURL, atomically: true, encoding: .utf8)
    }

    private func save() {
        guard let s = state, let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }
    private static func load() -> State? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }
}

/// Settings > About > Mass Test (with Developer Info on).
struct MassTestView: View {
    @ObservedObject private var test = MassTest.shared
    @State private var share = false

    var body: some View {
        let files = MassTest.apks()
        List {
            Section {
                if let files {
                    Text(files.isEmpty ? "The DeveloperTesting folder is empty." : "\(files.count) APKs in DeveloperTesting.")
                } else {
                    Text("Make a folder named DeveloperTesting in Husk's folder (Files > On My iPhone > Husk) and put the APKs to test in it.")
                        .foregroundStyle(.secondary)
                }
                if let s = test.state {
                    Text(test.active ? "In progress: \(s.results.count) of \(s.queue.count) done." : "Last test: \(s.results.count) of \(s.queue.count) done.")
                }
                if !test.status.isEmpty { Text(test.status).font(.caption).foregroundStyle(.secondary) }
            } footer: {
                Text("Each app is played once JIT is on, watched for 45 seconds, and written down; then Husk closes. Open Husk again for the next one. At the end the results file is offered to share.")
            }
            Section {
                if test.active {
                    Button("Stop", role: .destructive) { test.stop() }
                } else {
                    Button("Start Mass Test") { test.start() }.disabled((files ?? []).isEmpty)
                }
                if FileManager.default.fileExists(atPath: MassTest.resultsURL.path) {
                    Button("Share Results") { test.writeReport(); share = true }
                }
            }
        }
        .navigationTitle("Mass Test")
        .huskForm()
        .sheet(isPresented: $share) { ShareSheet(items: [MassTest.resultsURL]) }
    }
}
