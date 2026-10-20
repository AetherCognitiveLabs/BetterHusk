// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UniformTypeIdentifiers

/// The JIT walkthrough: pick a way in, follow its numbered steps, end with JIT on.
///
/// Three ways in. Pairing on this iPhone (iOS 27) and a pairing file made on a
/// computer both lead to Built-in StikJIT and share the last two steps,
/// LocalDevVPN and enabling. StikDebug has its own short page. Presented from
/// onboarding, Settings › JIT, and whenever Start finds JIT not set up.
struct JITSetupFlow: View {
    enum Step: Hashable { case pairOnDevice, importFile, connect, enable, stikDebug, trollStore, jailbreak, liveContainer }

    @ObservedObject private var jit = JITCoordinator.shared
    @ObservedObject private var pairing = OnDevicePairing.shared
    @State private var path: [Step] = []
    @State private var importing = false
    @Environment(\.dismiss) private var dismiss

    private var device: String { OnDevicePairing.deviceKind }

    var body: some View {
        NavigationStack(path: $path) {
            choose
                .huskDestination(for: Step.self) { step in
                    switch step {
                    case .pairOnDevice: pairOnDevice
                    case .importFile: importFile
                    case .connect: connect
                    case .enable: enable
                    case .stikDebug: stikDebug
                    case .trollStore: trollStore
                    case .jailbreak: jailbreak
                    case .liveContainer: liveContainer
                    }
                }
        }
        .tint(Theme.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList, .data]) { result in
            switch result {
            case .success(let url): jit.importPairingFile(url)
            case .failure(let failure):
                HuskLog.log("jit", "pairing import failed: \(failure.localizedDescription)")
            }
        }
        .onAppear {
            jit.refreshPairingStatus()
            pairing.reset()
            // A failed enable from the Library lands on the step that can fix it. Inside LiveContainer that step is its
            // own: the built-in helper cannot be started there, so sending it to the pairing pages would dead-end.
            if JITBootstrap.isInsideLiveContainer, !JITBootstrap.ready {
                path = [.liveContainer]
            } else if jit.error != nil, jit.hasPairing, jit.resolvedMethod == .builtIn {
                path = [.enable]
            }
            HuskLog.log("ui", "JIT walkthrough opened")
        }
        // Swiping the sheet away, or a copy shown from onboarding, must not
        // leave a request to show it again behind.
        .onDisappear { jit.showSetup = false }
    }

    private func close() {
        jit.showSetup = false
        dismiss()
    }

    // MARK: Choose

    private var choose: some View {
        page(symbol: "bolt.fill", title: "Turn on JIT",
             subtitle: String(localized: "Android needs memory it can write and then run, which on iOS only an attached debugger can grant. Choose how your \(device) gets one.")) {
            VStack(spacing: 10) {
                let builtIn = HuskBuiltInJIT.unavailableReason
                if JITBootstrap.isInsideLiveContainer {
                    way(String(localized: JITBootstrap.ready ? "LiveContainer — JIT is on" : "LiveContainer detected"), symbol: "shippingbox",
                        detail: String(localized: "BetterHusk is running inside LiveContainer. JIT comes the way LiveContainer gives it to apps — its own launch options or an attached debugger."),
                        done: JITBootstrap.ready,
                        recommended: recommendedStep == .liveContainer) { path.append(.liveContainer) }
                }
                way(String(localized: "Pair on this \(device)"), symbol: "iphone.radiowaves.left.and.right",
                    detail: builtIn ?? (!OnDevicePairing.isSupported ? "Needs iOS 27 or later."
                        : jit.pairingSource == .onDevice ? String(localized: "Paired on this \(device).")
                        : "No computer needed. Pairs from Settings in a minute."),
                    done: jit.pairingSource == .onDevice,
                    enabled: builtIn == nil && OnDevicePairing.isSupported,
                    recommended: recommendedStep == .pairOnDevice) { path.append(.pairOnDevice) }
                way("Use a pairing file", symbol: "doc.badge.plus",
                    detail: builtIn ?? (jit.pairingSource == .imported ? "Pairing file imported."
                        : "Import a pairing file made on a computer."),
                    done: jit.pairingSource == .imported,
                    enabled: builtIn == nil,
                    recommended: recommendedStep == .importFile) { path.append(.importFile) }
                way("Use StikDebug", symbol: "ant",
                    detail: JITBootstrap.isStikDebugInstalled ? "StikDebug is installed."
                        : "Enable JIT through the StikDebug app.",
                    done: jit.method == .stikDebug,
                    recommended: recommendedStep == .stikDebug) { path.append(.stikDebug) }
                way("Use TrollStore", symbol: "sparkles",
                    detail: JITBootstrap.isTrollStoreInstalled ? "TrollStore is installed."
                        : "For a BetterHusk installed through TrollStore.",
                    done: jit.method == .trollStore,
                    recommended: recommendedStep == .trollStore) { path.append(.trollStore) }
                way("Use a jailbreak", symbol: "lock.open",
                    detail: JITBootstrap.debuggedAtLaunch ? "JIT was already on when BetterHusk opened."
                        : JITBootstrap.isJailbroken ? "A jailbreak was found. Turn on Allow JIT in Apps."
                        : "Dopamine can give every app JIT with one setting.",
                    done: jit.method == .jailbreak || JITBootstrap.debuggedAtLaunch,
                    recommended: recommendedStep == .jailbreak) { path.append(.jailbreak) }
            }
            if jit.hasPairing && HuskBuiltInJIT.isAvailable {
                Button { path.append(.connect) } label: {
                    Label("Continue with the current pairing", systemImage: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.top, 4)
            }
        } actions: {
            Button("Not now") { close() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textDim)
        }
    }

    /// The one path that fits this device best, said so on its card.
    private var recommendedStep: Step {
        if JITBootstrap.isInsideLiveContainer { return .liveContainer }
        if HuskBuiltInJIT.isAvailable && OnDevicePairing.isSupported { return .pairOnDevice }
        if JITBootstrap.isStikDebugInstalled { return .stikDebug }
        if JITBootstrap.isTrollStoreInstalled { return .trollStore }
        if JITBootstrap.isJailbroken { return .jailbreak }
        return HuskBuiltInJIT.isAvailable ? .importFile : .stikDebug
    }

    private func way(_ title: String, symbol: String, detail: String, done: Bool,
                     enabled: Bool = true, recommended: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title.l10n).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                        if recommended {
                            Text("Recommended")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accentSoft, in: Capsule())
                        }
                    }
                    Text(detail.l10n).font(.system(size: 13)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: done ? 18 : 13, weight: .semibold))
                    .foregroundStyle(done ? .green : Theme.textDim.opacity(0.7))
            }
            .padding(14)
            .contentShape(Rectangle())
            .huskCard()
        }
        .buttonStyle(CardButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    // MARK: Pair on this device

    private var pairedOnDevice: Bool {
        if case .paired = pairing.phase { return true }
        return false
    }

    private var pairOnDevice: some View {
        page(symbol: "iphone.radiowaves.left.and.right", title: String(localized: "Pair on this \(device)"),
             subtitle: String(localized: "BetterHusk pretends to be a computer on your Wi-Fi, and your \(device) pairs with it the way it would with a Mac.")) {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "Turn on Wi-Fi, tap **Start pairing** below and allow Local Network access.",
                      done: pairing.phase != .idle)
                point(2, String(localized: "Open **Settings › Privacy & Security › Developer Mode**, scroll down and tap **Pair with \(OnDevicePairing.hostName)**."),
                      done: pairing.isShowingPin || pairedOnDevice)
                point(3, "Enter the code BetterHusk shows. It also appears in a banner and a notification, "
                       + "so you don't have to switch back.",
                      done: pairedOnDevice)
                point(4, "Come back to BetterHusk.", done: pairedOnDevice)
            }
            .padding(16).huskCard()
            pairingStatus
        } actions: {
            switch pairing.phase {
            case .idle, .failed:
                Button { pairing.start() } label: {
                    Label("Start pairing", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(PrimaryButtonStyle())
            case .waiting, .pin:
                Button("Cancel pairing", role: .cancel) { pairing.cancel() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            case .paired:
                Button("Continue") { path.append(.connect) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder private var pairingStatus: some View {
        switch pairing.phase {
        case .idle:
            EmptyView()
        case .waiting:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.accent)
                    Text("Waiting for your \(device)…").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.system(size: 14, weight: .semibold))
                if pairing.backgroundLimited {
                    Text("This installation can only wait about 30 seconds in the background, so go to Settings straight away.")
                        .font(.system(size: 13)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).huskCard()
        case .pin(let pin):
            VStack(spacing: 8) {
                Text("Enter this code on your \(device)").font(.system(size: 14))
                    .foregroundStyle(Theme.textDim)
                Text(pin).font(.system(size: 40, weight: .bold, design: .monospaced)).tracking(6)
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .accessibilityLabel("Pairing code \(pin.map(String.init).joined(separator: " "))")
            }
            .frame(maxWidth: .infinity)
            .padding(18).huskCard(high: true)
        case .paired(let name):
            outcome(String(localized: "Paired with \(name)"), ok: true)
        case .failed(let message):
            outcome(message, ok: false)
        }
    }

    // MARK: Import a pairing file

    private var importFile: some View {
        page(symbol: "doc.badge.plus", title: "Use a pairing file",
             subtitle: String(localized: "A pairing file made on a computer lets BetterHusk talk to this \(device) the same way.")) {
            VStack(alignment: .leading, spacing: 14) {
                point(1, String(localized: "On a computer, make this \(device)'s pairing file with the [StikDebug pairing-file guide](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md)."),
                      done: jit.pairingSource == .imported)
                point(2, String(localized: "Save it to Files, or AirDrop it to this \(device)."),
                      done: jit.pairingSource == .imported)
                point(3, "Tap **Choose pairing file** and pick it.", done: jit.pairingSource == .imported)
            }
            .padding(16).huskCard()
            Label("The pairing file stays in BetterHusk's Documents folder and is only sent to BetterHusk's own helper.",
                  systemImage: "lock.fill")
                .font(.system(size: 13)).foregroundStyle(Theme.textDim)
            if let error = jit.error { outcome(error, ok: false) }
        } actions: {
            if jit.pairingSource == .imported {
                Button("Continue") { path.append(.connect) }.buttonStyle(PrimaryButtonStyle())
                Button("Choose another file") { importing = true }
                    .font(.system(size: 15, weight: .medium))
            } else {
                Button { importing = true } label: { Label("Choose pairing file", systemImage: "folder") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: LocalDevVPN

    private var connect: some View {
        page(symbol: "network.badge.shield.half.filled", title: "Connect LocalDevVPN",
             subtitle: String(localized: "BetterHusk's helper reaches this \(device)'s debugging service through a local VPN. Nothing leaves your \(device).")) {
            VStack(alignment: .leading, spacing: 14) {
                point(1, String(localized: "Install [LocalDevVPN](\(LocalDevVPN.appStore.absoluteString)) from the App Store."),
                      done: LocalDevVPN.isInstalled)
                point(2, "Tap **Connect LocalDevVPN**. It switches the VPN on and comes straight back to BetterHusk.")
                point(3, "Leave it connected whenever you turn JIT on.")
            }
            .padding(16).huskCard()
        } actions: {
            Button(LocalDevVPN.actionTitle) { LocalDevVPN.open() }
                .buttonStyle(PrimaryButtonStyle())
            Button("It's connected") { path.append(.enable) }
                .font(.system(size: 15, weight: .medium))
        }
    }

    // MARK: Enable

    private var attached: Bool { jit.attachGeneration > 0 || JITBootstrap.debuggedFlag }

    private var enable: some View {
        page(symbol: "bolt.badge.checkmark", title: "Turn on JIT",
             subtitle: String(localized: "The first check downloads and mounts Apple's Developer Disk Image, which can take a minute.")) {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "Tap **Check setup**. BetterHusk checks LocalDevVPN and prepares the Developer Disk Image.",
                      done: jit.prepared || attached)
                point(2, "Tap **Enable JIT**. BetterHusk's helper attaches and Android can start.", done: attached)
            }
            .padding(16).huskCard()

            if jit.busy {
                HStack(spacing: 11) {
                    ProgressView().tint(Theme.accent)
                    Text(jit.status ?? "Working…").font(.system(size: 14)).foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                }
                .padding(16).huskCard(high: true)
            } else if attached {
                outcome(String(localized: "JIT is on. Android can start."), ok: true)
            } else if let error = jit.error {
                VStack(alignment: .leading, spacing: 10) {
                    outcome(error, ok: false)
                    if jit.connectionProblem == .pairing {
                        Button(OnDevicePairing.isSupported ? "Pair again" : "Import a new pairing file") {
                            path = [OnDevicePairing.isSupported ? .pairOnDevice : .importFile]
                        }
                        .font(.system(size: 14, weight: .semibold))
                    }
                    if jit.connectionProblem != nil {
                        Button(LocalDevVPN.actionTitle) { LocalDevVPN.open() }
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            } else if let status = jit.status {
                outcome(status, ok: true)
            }

            if !attached {
                Button("Reset Developer Disk Image", role: .destructive) { jit.resetDDI() }
                    .font(.system(size: 13, weight: .medium))
                    .disabled(jit.busy)
                    .padding(.top, 4)
            }
        } actions: {
            if attached {
                Button("Done") { close() }.buttonStyle(PrimaryButtonStyle())
            } else if jit.prepared {
                Button { jit.enableBuiltIn() } label: { Label("Enable JIT", systemImage: "bolt.fill") }
                    .buttonStyle(PrimaryButtonStyle(enabled: !jit.busy))
                    .disabled(jit.busy)
            } else {
                Button("Check setup") { jit.prepareBuiltIn() }
                    .buttonStyle(PrimaryButtonStyle(enabled: !jit.busy))
                    .disabled(jit.busy)
            }
        }
    }

    // MARK: StikDebug

    private var stikDebug: some View {
        page(symbol: "ant", title: "Use StikDebug",
             subtitle: "StikDebug is a separate app that attaches to BetterHusk. BetterHusk sends it the JIT script "
                     + "itself, so nothing needs configuring for BetterHusk inside StikDebug.") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "Install [StikDebug](https://github.com/StikDebug/StikDebug/releases/latest).",
                      done: JITBootstrap.isStikDebugInstalled)
                point(2, String(localized: "Import this \(device)'s pairing file into StikDebug."))
                point(3, String(localized: "Install and connect [LocalDevVPN](\(LocalDevVPN.appStore.absoluteString))."))
                point(4, "Whenever Android starts, BetterHusk opens StikDebug, which attaches and comes back.")
            }
            .padding(16).huskCard()
        } actions: {
            Button("Use StikDebug") {
                jit.method = .stikDebug
                HuskLog.log("ui", "JIT method set to StikDebug")
                close()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: TrollStore

    private var trollStore: some View {
        page(symbol: "sparkles", title: "Use TrollStore",
             subtitle: "TrollStore can enable JIT for apps it installed, with no pairing file, "
                     + "VPN or computer.") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "Install BetterHusk.ipa through TrollStore, on an iOS version TrollStore supports. It carries the "
                       + "entitlements TrollStore keeps, so the same file works there and in a sideloader.",
                      done: JITBootstrap.isInstalledWithTrollStore)
                point(2, "In TrollStore's Settings, turn on URL Scheme. TrollStore ignores enable-jit requests without it.")
                point(3, "Whenever Android or a game starts, BetterHusk asks TrollStore to enable JIT. TrollStore opens BetterHusk, "
                       + "attaches to it for a moment and lets go, which leaves it allowed to run code it wrote.")
            }
            .padding(16).huskCard()
            if !JITBootstrap.isTrollStoreInstalled {
                Label("TrollStore was not found on this \(device). It installs on iOS 14.0 to 17.0.", systemImage: "info.circle")
                    .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button("Use TrollStore") {
                jit.method = .trollStore
                HuskLog.log("ui", "JIT method set to TrollStore")
                close()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Jailbreak

    private var jailbreak: some View {
        page(symbol: "lock.open", title: "Use a jailbreak",
             subtitle: "On a device jailbroken with Dopamine, JIT is a setting: the jailbreak marks every app as "
                     + "debugged when it opens, and a debugged app may run code it wrote. BetterHusk needs nothing else.") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "Open Dopamine and go to its Settings.", done: JITBootstrap.isJailbroken)
                point(2, "Turn on Allow JIT in Apps.")
                point(3, "Close BetterHusk completely and open it again. The setting applies to apps as they start.",
                      done: JITBootstrap.debuggedAtLaunch)
            }
            .padding(16).huskCard()
            if JITBootstrap.debuggedAtLaunch {
                Label("BetterHusk was marked as debugged when it opened, so JIT is on.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(.green)
            } else if !JITBootstrap.isJailbroken {
                Label("No jailbreak was found on this \(device).", systemImage: "info.circle")
                    .font(.system(size: 13)).foregroundStyle(Theme.textDim)
            }
        } actions: {
            Button("Use the jailbreak") {
                jit.method = .jailbreak
                HuskLog.log("ui", "JIT method set to jailbreak")
                close()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: LiveContainer

    /// BetterHusk hosted by LiveContainer shares LiveContainer's process, so a debugger that attaches to it attaches to
    /// BetterHusk too -- and its own helper extension cannot be started there, which is why only the container's own
    /// options and StikDebug are offered.
    private var liveContainer: some View {
        page(symbol: "shippingbox", title: "LiveContainer",
             subtitle: "BetterHusk is running inside LiveContainer. Both share one process, so JIT for one is JIT for "
                     + "the other -- it just has to be switched on from outside, the way LiveContainer does it.") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "In **LiveContainer**, open BetterHusk's settings and turn on **JIT** for it (or launch it with JIT).",
                      done: JITBootstrap.ready)
                point(2, "Or attach **StikDebug** -- it marks the process LiveContainer and BetterHusk share.",
                      done: JITBootstrap.ready)
                point(3, "Come back here. This page notices on its own.", done: JITBootstrap.ready)
            }
            .padding(16).huskCard()
            if JITBootstrap.ready || jit.attachGeneration > 0 {
                outcome(String(localized: "JIT is on. Games and Android can start."), ok: true)
            } else if let error = jit.error {
                outcome(error, ok: false)
            }
        } actions: {
            if JITBootstrap.ready || jit.attachGeneration > 0 {
                Button("Done") { close() }.buttonStyle(PrimaryButtonStyle())
            } else {
                if JITBootstrap.isStikDebugInstalled {
                    Button {
                        jit.method = .stikDebug
                        jit.enable()
                    } label: { Label("Attach with StikDebug", systemImage: "ant") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Button("Not now") { close() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    // MARK: Pieces

    private func page<Content: View, Actions: View>(
        symbol: String, title: String, subtitle: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions) -> some View {
        ZStack {
            Theme.backdrop
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 56, height: 56)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(title.l10n).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(subtitle.l10n).font(.system(size: 15)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    content()
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) { actions() }
                .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 16)
                .background(Theme.backdrop)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Close") { close() }
            }
        }
    }

    private func point(_ number: Int, _ text: String, done: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.18) : Theme.accentSoft)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 26, height: 26)
            Text(text.l10n)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func outcome(_ text: String, ok: Bool) -> some View {
        Label(text.l10n, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(ok ? .green : .red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).huskCard()
    }
}
