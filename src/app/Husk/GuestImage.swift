// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Compression

/// Manages the Android guest that lives in Documents.
///
/// The guest is LineageOS built to boot directly under QEMU
/// (github.com/jqssun/android-lineage-qemu), not Android inside a container
/// inside another Linux. That removes Debian, LXC, Waydroid, cage, dbus and
/// pipewire from underneath it -- along with every failure that only existed
/// because of them -- and the arm64only build is the one that project
/// recommends for iOS, where there is no hypervisor and QEMU is emulating.
///
/// Three files make up the guest. Only the system disk is downloaded; the other
/// two are a few hundred kilobytes each and ride in the IPA:
///
///   vda  system, 5 GiB virtual  -- downloaded, compressed clusters
///   vdb  userdata, 16 GiB virtual, empty -- seeded from the bundle
///   efi_vars  UEFI variable store (qcow2, 64 MiB virtual) -- seeded
@MainActor
final class GuestImage: ObservableObject {
    static let shared = GuestImage()

    enum State: Equatable {
        case missing
        case downloading(progress: Double, received: Int64, total: Int64)
        case installing
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .missing

    /// Published alongside the IPA. Kept as a constant here so a rebuilt guest can
    /// be rolled out without shipping a new app binary.
    /// A qcow2 with compressed clusters (`qemu-img convert -c`). QEMU reads those
    /// transparently, so there is no decompression step in the app at all -- which
    /// matters because iOS's Compression framework offers LZFSE/LZ4/LZMA/zlib and
    /// neither zstd nor bzip2, so any external container would have meant shipping
    /// a decompressor.
    /// Bumped whenever the guest image itself changes. Without this the app keeps
    /// whatever it downloaded first: the disk exists, so nothing re-fetches it, and
    /// a guest missing a newly-added component fails in ways that look like app
    /// bugs rather than a stale image.
    /// The single "Dependencies" release that holds every downloadable asset.
    ///
    /// Fixed, so bumping a generation does not need a new GitHub release --
    /// the version lives in the asset name instead.
    static let dependenciesTag = "lineage-v2"
    /// Asset generation. Bumping this re-downloads the guest and its snapshot.
    ///
    /// v5 adds an init script that marks the device provisioned. Without it
    /// Android shows no launcher and adbd refuses every shell, because an
    /// unprovisioned device runs ADB in trade-in mode.
    ///
    /// v10 adds the command bridge -- an init service running a netcat listener
    /// on port 5599 whose child is a shell in `u:r:shell:s0`. That is what the
    /// library talks to, so an install carrying an older guest has no library at
    /// all and must re-fetch.
    /// v12 declares android.hardware.ethernet in /system/etc/permissions, so
    /// EthernetService starts and claims eth0. Without a registered network,
    /// netd's per-uid routing has no default to point at and the command bridge
    /// goes silent about a minute after every boot.
    static let imageVersion = "v12"

    /// Version shared by the blank userdata seed and downloaded snapshots.
    private static let userdataSeedVersion = "v10"

    /// Whether to fetch the pre-booted snapshot rather than boot from cold.
    static var wantsSnapshot: Bool {
        UserDefaults.standard.object(forKey: "husk.downloadSnapshot") as? Bool ?? true
    }

    /// A machine that has already finished booting, gzipped.
    ///
    /// Booting Android here takes five to twelve minutes and has to survive
    /// Android's own watchdog killing system_server partway through. The same
    /// boot was done once on a Mac and saved; restoring it took 8.8 seconds.
    /// Two gigabytes of download buys that.
    /// The snapshot arrives in pieces.
    ///
    /// GitHub refuses a release asset of 2 GiB or more -- "size must be less
    /// than 2147483648" -- and the pre-booted machine is 3 GiB of guest RAM
    /// that still compresses to just over the limit at maximum effort. So it is
    /// published split. The split is on plain byte offsets and not a container
    /// of any kind, so concatenating the pieces in order reproduces the gzip
    /// stream byte for byte and nothing downstream needs to know it happened.
    static let snapshotPartCount = 2
    static var snapshotPartURLs: [URL] {
        (0..<snapshotPartCount).map { i in
            URL(string: GuestManifest.releaseBase
                      + "\(dependenciesTag)/vdb-snapshot-\(imageVersion).qcow2.gz."
                      + String(format: "%02d", i))!
        }
    }

    /// RAM and resolution the shipped snapshot was taken with.
    ///
    /// Not adjustable. QEMU refuses a restore whose RAM size differs by a byte
    /// -- "Size mismatch: huskram" -- so a device that probed its way to 5120
    /// could not load a snapshot saved at 4096. These are the numbers the
    /// snapshot on the release was built against.
    static let snapshotGuestMiB = 4096
    static let snapshotXres = 360
    static let snapshotYres = 800

    static var imageURL: URL {
        URL(string: GuestManifest.releaseBase
                  + "\(dependenciesTag)/vda-\(imageVersion).qcow2")!
    }

    nonisolated var versionStampPath: String {
        // Named for this guest, not the old one. It used to be
        // "husk-guest.version", which cleanUpPreviousGuest() deletes as Waydroid
        // leftovers -- so every launch wiped the stamp, decided the image was
        // unversioned, and downloaded 1.1 GB again.
        documents.appendingPathComponent("lineage-guest.version").path
    }

    // nonisolated: QEMU's own thread builds its command line from these, and they
    // are pure path arithmetic with no mutable state to protect.
    nonisolated private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    nonisolated var diskPath: String { documents.appendingPathComponent("lineage-vda.qcow2").path }
    /// Present when userdata came from the shipped pre-booted snapshot.
    nonisolated var snapshotStampPath: String {
        documents.appendingPathComponent("husk-shipped-snapshot").path
    }
    /// Whether a valid pre-booted snapshot is present. Version freshness is
    /// checked separately against the remote manifest.
    ///
    /// Existence alone was not enough. The stamp survived an image version bump,
    /// so an install that already had the v1 snapshot skipped downloading the v5
    /// one -- while the userdata that snapshot lived in had just been re-seeded
    /// empty by the same bump. The app then pinned the machine for a restore
    /// that could not happen and cold-booted, which looks exactly like the
    /// snapshot feature silently not existing.
    nonisolated var hasShippedSnapshot: Bool {
        // The stamp files can outlive the disk they describe. A snapshot only
        // counts as installed while its qcow2 is present and valid.
        guard Self.validate(path: userdataPath).problem == nil else { return false }
        // A recorded digest is the modern answer. Comparing the stamp to
        // imageVersion, as this used to, quietly tied "do I have a snapshot" to
        // "is the app's generation string current" -- so publishing a new image
        // made every install believe its perfectly good snapshot had vanished,
        // and with it the pinned RAM and resolution a restore depends on.
        if installedSnapshotDigest != nil { return true }
        // Installs from before digests existed recorded a generation name here
        // instead. Their snapshot is still on disk and still restorable.
        return (try? String(contentsOfFile: snapshotStampPath, encoding: .utf8)) != nil
    }

    // MARK: digests

    /// SHA-256 of the system image this install actually wrote to disk, and of
    /// the snapshot archive it actually unpacked.
    ///
    /// Recorded at install time rather than computed on demand, because only the
    /// system image is still the bytes that were downloaded -- userdata is
    /// rewritten the instant Android runs, so hashing it later answers a
    /// different question than "is this the snapshot the release is offering".
    nonisolated var imageDigestPath: String {
        documents.appendingPathComponent("lineage-guest.sha256").path
    }
    nonisolated var snapshotDigestPath: String {
        documents.appendingPathComponent("husk-shipped-snapshot.sha256").path
    }
    /// The machine the installed snapshot was saved on, as JSON. Travels with
    /// the snapshot so a restore is never attempted at the wrong RAM size.
    nonisolated var snapshotPinsPath: String {
        documents.appendingPathComponent("husk-snapshot-pins.json").path
    }

    nonisolated private func recorded(at path: String) -> String? {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated var installedImageDigest: String?    { recorded(at: imageDigestPath) }
    nonisolated var installedSnapshotDigest: String? { recorded(at: snapshotDigestPath) }

    /// RAM and resolution the installed snapshot needs, falling back to the
    /// values this app was built against when nothing was recorded.
    nonisolated var snapshotPins: (mib: Int, xres: Int, yres: Int, smp: Int, cpu: String) {
        let fallback = (Self.snapshotGuestMiB, Self.snapshotXres, Self.snapshotYres,
                        Self.defaultSmp, Self.defaultCpu)
        guard let data = FileManager.default.contents(atPath: snapshotPinsPath),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mib = j["guestMiB"] as? Int,
              let x = j["xres"] as? Int, let y = j["yres"] as? Int
        else { return fallback }
        return (mib, x, y,
                j["smp"] as? Int ?? Self.defaultSmp,
                j["cpu"] as? String ?? Self.defaultCpu)
    }

    /// What this build uses when a snapshot does not say otherwise.
    static let defaultSmp = 4
    static let defaultCpu = "max,pauth-impdef=on,sve=off,sme=off"

    /// What the release is offering that this install does not have.
    @Published private(set) var update: GuestUpdate = .none
    @Published private(set) var manifest: GuestManifest?

    /// Compare what is installed against what the release publishes.
    ///
    /// Digests, not version names. The app used to decide this by writing the
    /// generation it believed it had installed into a stamp file and comparing
    /// strings, which cannot detect either of the two ways it has actually gone
    /// wrong: a stamp that outlived the files it described, and an asset
    /// published under a new name carrying the old bytes.
    func checkForUpdates() async {
        guard let m = await GuestManifest.fetch() else { return }
        manifest = m
        snapshotPinsToRecord = m.snapshot

        let haveImage = FileManager.default.fileExists(atPath: diskPath)

        // An install from before digests were recorded has the image but no
        // record of what it hashed to, which is indistinguishable from having
        // the wrong one. Hash it once instead of assuming the worst -- assuming
        // costs the person a three-gigabyte download of what they already have.
        if haveImage, installedImageDigest == nil {
            let path = diskPath
            let digest = await Task.detached(priority: .utility) {
                DigestWriter.ofFile(at: path)
            }.value
            if let digest {
                try? digest.write(toFile: imageDigestPath, atomically: true, encoding: .utf8)
                HuskLog.log("guest", "hashed the existing image: \(digest.prefix(12))…")
            }
        }

        // Not downloaded is not out of date: someone who only plays games in the Translation Layer never asked for Android,
        // and the Android page's Download button is where it starts.
        guard haveImage else {
            HuskLog.log("guest", "no Android image installed; not offering an update")
            update = .none
            return
        }
        if installedImageDigest != m.image.sha256 {
            HuskLog.log("guest", "image differs: have "
                      + "\(installedImageDigest?.prefix(12) ?? "nothing"), "
                      + "release has \(m.image.sha256.prefix(12))")
            offer(.image(bytes: m.image.size + m.snapshot.size), release: m.image.sha256)
            return
        }
        if Self.wantsSnapshot,
           (!hasShippedSnapshot || installedSnapshotDigest != m.snapshot.sha256) {
            HuskLog.log("guest", "snapshot differs: have "
                      + "\(installedSnapshotDigest?.prefix(12) ?? "nothing"), "
                      + "release has \(m.snapshot.sha256.prefix(12))")
            offer(.snapshot(bytes: m.snapshot.size), release: m.snapshot.sha256)
            return
        }
        HuskLog.log("guest", "guest is up to date with \(m.generation)")
        update = .none
    }

    /// Settings > Saved machine: whether to ask at all.
    nonisolated static let askUpdatesKey = "husk.guest.askUpdates"
    private static let declinedKey = "husk.guest.updateDeclined"
    private var offered: String?

    /// Ask about a release once: not when asking is turned off, and not again after "Not now" for that same release.
    private func offer(_ u: GuestUpdate, release digest: String) {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.askUpdatesKey) as? Bool ?? true else {
            HuskLog.log("guest", "update prompts are off; not asking")
            return
        }
        guard d.string(forKey: Self.declinedKey) != digest else {
            HuskLog.log("guest", "this release was declined before; not asking again")
            return
        }
        offered = digest
        update = u
    }

    /// Take whatever the update prompt offered.
    func applyUpdate() {
        switch update {
        case .image:    update = .none; download()
        case .snapshot: update = .none; downloadSnapshotNow()
        case .none:     break
        }
    }

    func dismissUpdate() {
        if update.isSomething, let offered { UserDefaults.standard.set(offered, forKey: Self.declinedKey) }
        update = .none
    }

    nonisolated var userdataPath: String { documents.appendingPathComponent("lineage-vdb.qcow2").path }
    nonisolated var varsPath: String { documents.appendingPathComponent("lineage-efi-vars.fd").path }
    nonisolated var firmwarePath: String { documents.appendingPathComponent("edk2-aarch64-code.fd").path }

    /// Written the first time a userdata disk carries Android all the way to
    /// sys.boot_completed. Its presence is the difference between "an install
    /// that lost its /data" (keep, let the user decide) and "a /data that was
    /// never built" (safe to re-seed without asking).
    nonisolated var userdataBootedStampPath: String {
        documents.appendingPathComponent("lineage-vdb.booted").path
    }
    /// Written by the serial tailer when init gives up on building /data and
    /// reboots into recovery ("init_user0_failed"). Read on the next launch:
    /// the guest cannot fix this itself -- recovery's mke2fs refuses to
    /// clobber a half-built filesystem, which is the "Data wipe failed" loop
    /// reported in #128.
    nonisolated var userdataBrokenStampPath: String {
        documents.appendingPathComponent("lineage-vdb.broken").path
    }
    /// How many automatic userdata re-seeds happened without a successful boot
    /// between them. Capped so a deterministic fault does not wipe and retry
    /// forever.
    nonisolated var userdataReseedCountPath: String {
        documents.appendingPathComponent("lineage-vdb.reseeds").path
    }
    /// Auto-reseed attempts before giving up and surfacing the failure.
    nonisolated static let userdataReseedLimit = 2
    /// Below this physical size a userdata disk cannot hold a working Android
    /// /data -- a fresh seed is ~192 KB and a half-built ext4 stays well under
    /// it, while any install that ever completed first boot holds gigabytes.
    /// It is the second guard against wiping a real install that predates the
    /// .booted stamp.
    nonisolated static let establishedUserdataBytes: Int64 = 768 * 1024 * 1024

    private var task: URLSessionDownloadTask?

    /// The guest image and the snapshot parts download through background sessions: leaving the page, the Control
    /// Center or the app itself no longer abandons a gigabyte of progress -- iOS keeps the transfer and hands its
    /// events back, even after relaunching Husk to deliver them.
    nonisolated static let imageSessionID = "com.betterhusk.guest-downloads"

    /// iOS woke Husk to answer for a background download; stored here, and the delegate calls it once events are handled.
    var backgroundCompletion: (() -> Void)?

    private var imageSession: URLSession?
    /// Bytes a failed download kept: trying again continues from where it stopped instead of from the start.
    private var resumeData: Data?

    /// Bump whenever the set or order of virtio devices in the Phase 1 command
    /// line changes. Any change renumbers the PCI bus and invalidates recorded
    /// UEFI boot entries.
    nonisolated static let deviceLayoutSignature = "v4-lineage-gpu-xhci-2blk-net-serial-rng-balloon-vmstatenode"

    /// qcow2 magic: "QFI\xfb". Checked because a download that "succeeded" is not
    /// the same as a download that produced an image -- a 404 body lands on disk
    /// just as happily as 755 MB of guest would.
    private static let qcow2Magic: [UInt8] = [0x51, 0x46, 0x49, 0xFB]

    /// Anything smaller than this is definitionally not a guest image. The real
    /// one is ~755 MB; the failure that prompted this check was 9 bytes of
    /// "Not Found".
    private static let minimumPlausibleSize: Int64 = 64 * 1024 * 1024

    /// True if the file at `path` looks like a qcow2 of plausible size.
    nonisolated static func validate(path: String) -> (size: Int64?, problem: String?) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.int64Value else {
            return (nil, "file is missing")
        }
        guard size >= minimumPlausibleSize else {
            // Show a little of it: when this fires the content is usually a short
            // error page, and quoting it names the real problem immediately.
            var hint = ""
            if size > 0, size < 512,
               let d = fm.contents(atPath: path),
               let text = String(data: d, encoding: .utf8) {
                hint = " — content was: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            return (nil, "only \(size) bytes, expected at least "
                        + "\(minimumPlausibleSize / (1024 * 1024)) MB\(hint)")
        }
        guard let fh = FileHandle(forReadingAtPath: path),
              let head = try? fh.read(upToCount: 4), head.count == 4 else {
            return (nil, "could not read the file header")
        }
        try? fh.close()
        guard Array(head) == qcow2Magic else {
            let hex = head.map { String(format: "%02x", $0) }.joined(separator: " ")
            return (nil, String(localized: "not a qcow2 image (header was \(hex), expected 51 46 49 fb)"))
        }
        return (size, nil)
    }

    /// Reads the fields a broken userdata disk would lie about: qcow2 version,
    /// backing chain, and the virtual size the guest will actually see.
    ///
    /// `validate(path:)`'s magic+size check answers "did the download produce
    /// an image" for the 755 MB system disk, but it is the wrong tool for
    /// userdata: a healthy empty seed is ~192 KB, and a qcow2 whose header
    /// parses while claiming 0 bytes of disk -- or one that still names a
    /// backing file we never ship -- passes magic+size while handing the guest
    /// a block device mke2fs cannot format (#128).
    ///
    /// Returns a description of the problem, or nil when the header is sound.
    /// Big-endian throughout: qcow2 fields are network order.
    nonisolated static func inspectUserdataHeader(path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else {
            return "could not open the userdata image"
        }
        defer { try? fh.close() }
        guard let head = try? fh.read(upToCount: 80), head.count >= 80 else {
            return "userdata image is truncated (header is incomplete)"
        }
        guard Array(head[0..<4]) == qcow2Magic else {
            return "userdata image is not qcow2"
        }
        func be32(_ o: Int) -> UInt32 {
            head.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }.bigEndian
        }
        func be64(_ o: Int) -> UInt64 {
            head.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt64.self) }.bigEndian
        }
        let version = be32(4)
        guard version == 2 || version == 3 else {
            return String(localized: "unsupported qcow2 version \(version)")
        }
        // Our seeds and snapshots are self-contained; a backing file entry is
        // never legitimate and means the image points at bytes that are not here.
        guard be64(8) == 0 else {
            return "userdata image has a backing file, which BetterHusk never ships"
        }
        let virtualSize = be64(32)
        guard virtualSize >= 1 << 30 else {
            return String(localized: "userdata image declares only \(virtualSize) bytes of disk")
        }
        // qcow2 v3 incompatible_features (offset 72). Bits 0 and 1 (dirty,
        // corrupt) may legitimately be set -- a jetsam-killed guest never gets
        // to clear its dirty flag, and wiping the disk over that would be the
        // bug. Bit 2 onward (external data file, zstd compression, extended
        // L2) means QEMU cannot use this image for our purpose at all.
        if version == 3 {
            let incompat = be64(72)
            if incompat & ~UInt64(0x3) != 0 {
                return "userdata image needs qcow2 features QEMU cannot use "
                     + "(incompatible_features 0x\(String(incompat, radix: 16)))"
            }
        }
        return nil
    }

    /// Records that the userdata disk on disk just carried Android to
    /// sys.boot_completed=1. Called from the serial tailer; the stamps are
    /// plain files precisely so they survive the app being killed mid-run.
    /// Static and nonisolated: the tailer runs on its own thread, and asking
    /// it to hop through the main actor for a file write would be the wrong
    /// kind of dependency for an emergency marker.
    nonisolated static func noteUserdataBooted() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let booted = docs.appendingPathComponent("lineage-vdb.booted").path
        let isNew = !fm.fileExists(atPath: booted)
        if isNew {
            fm.createFile(atPath: booted, contents: Data())
        }
        // A disk that reached the desktop is by definition not stuck mid-build.
        // Cleared on every boot_completed, not just the first: a transient
        // init_user0_failed that a retry recovered from must not leave a
        // .broken stamp accusing a working disk forever.
        try? fm.removeItem(atPath: docs.appendingPathComponent("lineage-vdb.broken").path)
        try? fm.removeItem(atPath: docs.appendingPathComponent("lineage-vdb.reseeds").path)
        if isNew {
            HuskLog.log("guest", "userdata reached boot_completed; marked healthy")
        }
    }

    /// Records that init gave up building /data ("init_user0_failed") and the
    /// guest is about to loop through a recovery that cannot repair it. The
    /// actual wipe happens in prepareFirmware() on the next launch -- QEMU in
    /// this process cannot be re-initialised, so mid-run rescue is impossible;
    /// what the run CAN do is leave the evidence the next launch acts on.
    nonisolated static func noteUserdataBuildFailed() {
        let fm = FileManager.default
        let path = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lineage-vdb.broken").path
        if fm.fileExists(atPath: path) { return }
        fm.createFile(atPath: path, contents: Data())
        HuskLog.log("guest", "init_user0_failed: userdata marked broken; "
                           + "the next launch will re-seed it if it never booted")
    }

    /// Every file the Android machine keeps: the system and userdata disks, the UEFI variables and firmware copy, the guest RAM
    /// file, the saved machine and the records about them. All of it comes back with the next download, and none of it is needed
    /// to run apps on the translation layer.
    nonisolated var androidFiles: [String] {
        let runner = QemuRunner.shared
        return [diskPath, userdataPath, userdataPath + ".seed", userdataBootedStampPath,
                userdataBrokenStampPath, userdataReseedCountPath,
                varsPath, varsPath + ".layout", firmwarePath, versionStampPath, imageDigestPath,
                snapshotStampPath, snapshotDigestPath, snapshotPinsPath, runner.guestRamPath, runner.snapshotSizePath,
                runner.snapshotDisplayPath, runner.memoryStrategyPath]
    }

    /// Bytes the Android files take on disk.
    nonisolated var androidBytes: Int64 {
        androidFiles.reduce(0) { total, path in
            let size = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
            return total + Int64(size)
        }
    }

    /// Delete Android's files (#123: people who only use the translation layer). Returns the bytes freed.
    @discardableResult
    func removeAll() -> Int64 {
        let freed = androidBytes
        for path in androidFiles { try? FileManager.default.removeItem(atPath: path) }
        HuskLog.log("guest", "removed Android's files (\(freed / 1_048_576) MiB); the next start downloads them again")
        state = .missing
        return freed
    }

    func refresh() {
        adoptPendingDownloads()
        if case .downloading = state { return }
        if case .installing = state { return }
        removeStaleDownloads()

        guard FileManager.default.fileExists(atPath: diskPath) else {
            state = .missing
            return
        }
        // Validate every time, not just after downloading: a previous run may have
        // installed a corrupt file before this check existed, and the symptom of
        // that ("Image is not in qcow2 format") points at QEMU rather than here.
        // A valid image of the wrong version is still the wrong image.
        let installed = try? String(contentsOfFile: versionStampPath, encoding: .utf8)
        if installed != Self.imageVersion {
            HuskLog.log("guest", "installed guest is \(installed ?? "unversioned"), "
                               + "need \(Self.imageVersion); re-downloading")
            try? FileManager.default.removeItem(atPath: diskPath)
            state = .missing
            return
        }

        let check = Self.validate(path: diskPath)
        if let why = check.problem {
            HuskLog.log("guest", "existing guest disk is INVALID (\(why)); removing it")
            try? FileManager.default.removeItem(atPath: diskPath)
            state = .failed(String(localized: "The runtime on disk is not a valid image (\(why)). Tap to retry."))
            return
        }

        // A userdata that init_user0_failed'd out of the repair budget boots
        // into a recovery that loops forever with no way forward. That is a
        // state worth naming on screen instead of letting it look like a guest
        // that merely starts slow (#128).
        let fm = FileManager.default
        if fm.fileExists(atPath: userdataBrokenStampPath) {
            if !fm.fileExists(atPath: userdataBootedStampPath),
               (Int((try? String(contentsOfFile: userdataReseedCountPath,
                                 encoding: .utf8)) ?? "") ?? 0) >= Self.userdataReseedLimit {
                state = .failed("Android's data partition could not be repaired "
                              + "automatically. Remove Android in Settings and install it "
                              + "again — and if it fails the same way, please send "
                              + "guest-serial.log with the report.")
                return
            }
            if fm.fileExists(atPath: userdataBootedStampPath), !hasShippedSnapshot {
                // A disk that once booted and now fails is the user's own
                // /data gone bad. Deliberately NOT a .failed state: blocking
                // Start here would be a dead end, because a boot that somehow
                // recovers is also the only thing that clears the stamp. The
                // guest may still get somewhere; if it does not, Remove
                // Android in Settings is the way out.
                HuskLog.log("guest", "userdata previously booted but now marked "
                                   + "broken; leaving the disk and the decision to the user")
            }
        }

        HuskLog.log("guest", "guest disk present and valid: \(check.size ?? 0) bytes")
        state = .ready
    }

    /// Create the UEFI variable store beside the bundled firmware.
    ///
    /// The firmware itself ships raw in the app bundle. It is 64 MiB, but almost
    /// entirely zeros, so the IPA's own zip compresses it to about a megabyte --
    /// cheaper than carrying a decompressor for it.
    /// Remove what the previous guest architecture left in Documents.
    ///
    /// The Waydroid disk grew to over 4 GB once Android had been written into it
    /// and is now dead weight on the user's phone. Its diagnostics file is worse
    /// than dead: the bridge still folds it into the log every poll, replaying
    /// Debian and Waydroid text long after either existed, which reads exactly
    /// like a live guest saying the wrong thing.
    private func cleanUpPreviousGuest() {
        let fm = FileManager.default
        let stale = ["husk-guest.qcow2", "husk-guest.version",
                     "edk2-vars.fd", "edk2-vars.fd.layout",
                     "share/diagnostics.txt"]
        var freed: Int64 = 0
        for name in stale {
            let path = documents.appendingPathComponent(name).path
            guard fm.fileExists(atPath: path) else { continue }
            let size = ((try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
            try? fm.removeItem(atPath: path)
            freed += size
        }
        if freed > 0 {
            HuskLog.log("guest", "removed \(freed / (1024 * 1024)) MiB left by the previous "
                               + "guest (Debian/Waydroid)")
        }
    }

    func prepareFirmware() throws {
        cleanUpPreviousGuest()
        let fm = FileManager.default
        if !fm.fileExists(atPath: firmwarePath) {
            guard let src = Bundle.main.path(forResource: "edk2-aarch64-code", ofType: "fd") else {
                throw NSError(domain: "husk", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "edk2-aarch64-code.fd missing from the app bundle"])
            }
            // Copied rather than used in place: pflash wants a plain file and the
            // bundle is read-only, and keeping both volumes together in Documents
            // makes the pair easy to reason about.
            try fm.copyItem(atPath: src, toPath: firmwarePath)
            HuskLog.log("guest", "firmware staged to Documents")
        }
        // The UEFI variable store records boot entries as PCI device paths. Adding
        // or removing a virtio device renumbers the bus, so entries written under a
        // previous device layout stop resolving -- and the firmware then falls
        // through to PXE and drops to the EFI Shell instead of booting the disk.
        // The symptom looks nothing like its cause, so the store is stamped with a
        // signature of the layout and rebuilt whenever that changes.
        let stamp = URL(fileURLWithPath: varsPath + ".layout")
        let current = Self.deviceLayoutSignature
        let previous = try? String(contentsOf: stamp, encoding: .utf8)

        if !fm.fileExists(atPath: varsPath) || previous != current {
            if previous != nil, previous != current {
                HuskLog.log("guest", "device layout changed (\(previous ?? "?") -> \(current)); "
                                   + "resetting the UEFI variable store so it re-discovers the disk")
            } else {
                HuskLog.log("guest", "staging UEFI variable store")
            }
            // Seeded from the image's own variable store rather than created
            // blank. It already holds the boot entry for this Android build,
            // which saves the firmware a discovery pass -- and if our PCI layout
            // does not match the one it was recorded under, the entry simply
            // fails to resolve and the firmware falls back to scanning for
            // \EFI\BOOT\BOOTAA64.EFI, which is where it would have ended up
            // starting from empty anyway.
            guard let seed = Bundle.main.path(forResource: "lineage-efi-vars-seed", ofType: "fd") else {
                throw NSError(domain: "husk", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "lineage-efi-vars-seed.fd missing from the app bundle"])
            }
            try? fm.removeItem(atPath: varsPath)
            try fm.copyItem(atPath: seed, toPath: varsPath)
            try? current.write(to: stamp, atomically: true, encoding: .utf8)
        }

        // Userdata. Empty on arrival -- 16 GiB virtual, 192 KB on disk -- and
        // written by Android from its first boot onward, so it is copied out of
        // the read-only bundle once and then left alone. Deliberately NOT tied
        // to the device layout signature: that changes for reasons that have
        // nothing to do with /data, and resetting it factory-resets the guest.
        //
        // It has its own version instead, bumped only when userdata is known to
        // be unusable. It is at v2 because a kernel panic killed the guest
        // partway through building /data, and what it left behind made Android
        // reboot into recovery on every subsequent start
        // ("init_user0_failed"). Nothing short of a clean partition fixes that.
        let seedStamp = URL(fileURLWithPath: userdataPath + ".seed")
        // v3: the guest image changed, so userdata built against the old /system --
        // including a multi-gigabyte snapshot of it -- has to go.
        let seedVersion = Self.userdataSeedVersion
        let seededWith = try? String(contentsOf: seedStamp, encoding: .utf8)
        if fm.fileExists(atPath: userdataPath), seededWith != seedVersion {
            if hasShippedSnapshot {
                // Snapshot installs use the same userdata disk but historically
                // did not write this seed stamp. Repair the stamp instead of
                // replacing a valid, downloaded snapshot with an empty disk.
                try seedVersion.write(to: seedStamp, atomically: true, encoding: .utf8)
                HuskLog.log("guest", "preserving installed snapshot and repairing its "
                                   + "userdata seed stamp")
            } else {
                // Check for the replacement before deleting existing data. A
                // missing resource must not turn an upgrade into a missing disk.
                guard let seed = Bundle.main.path(forResource: "lineage-vdb-seed", ofType: "qcow2") else {
                    throw NSError(domain: "husk", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "lineage-vdb-seed.qcow2 missing from the app bundle"])
                }
                HuskLog.log("guest", "userdata seed \(seededWith ?? "unversioned") -> \(seedVersion); "
                                   + "starting from a clean partition")
                try? fm.removeItem(atPath: userdataPath)
                // The health stamps describe the disk just thrown away; keeping
                // them would protect the fresh seed as if it had ever booted.
                try? fm.removeItem(atPath: userdataBootedStampPath)
                try? fm.removeItem(atPath: userdataBrokenStampPath)
                try? fm.removeItem(atPath: userdataReseedCountPath)
                try fm.copyItem(atPath: seed, toPath: userdataPath)
                try seedVersion.write(to: seedStamp, atomically: true, encoding: .utf8)
                HuskLog.log("guest", "userdata disk staged to Documents")
            }
        }
        if !fm.fileExists(atPath: userdataPath) {
            guard let seed = Bundle.main.path(forResource: "lineage-vdb-seed", ofType: "qcow2") else {
                throw NSError(domain: "husk", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "lineage-vdb-seed.qcow2 missing from the app bundle"])
            }
            // No disk means no health history; stamps older than the file are lies.
            try? fm.removeItem(atPath: userdataBootedStampPath)
            try? fm.removeItem(atPath: userdataBrokenStampPath)
            try? fm.removeItem(atPath: userdataReseedCountPath)
            try fm.copyItem(atPath: seed, toPath: userdataPath)
            try seedVersion.write(to: seedStamp, atomically: true, encoding: .utf8)
            HuskLog.log("guest", "userdata disk staged to Documents")
        }

        try repairUserdataIfNeeded()
    }

    /// Re-seeds a userdata disk that demonstrably cannot be used. Two triggers,
    /// same repair, because both leave the guest dead-ending in a recovery
    /// that cannot fix itself:
    ///
    ///   - the serial console reported init_user0_failed on the previous run
    ///     (the .broken stamp), which is the state the comment above describes:
    ///     a kernel panic mid-build left a /data that boots init into failure
    ///     and makes recovery's mke2fs refuse to overwrite it (#128);
    ///   - the qcow2 header itself is bad, which hands QEMU a block device
    ///     that was never going to format no matter what the guest does.
    ///
    /// Both repairs are gated on the disk being disposable: no successful boot
    /// on record, no shipped snapshot riding on it, and physically too small to
    /// hold a real /data. A disk that ever worked is the user's data, and no
    /// automatic path may take that decision for them -- those are logged and
    /// left alone.
    private func repairUserdataIfNeeded() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: userdataPath) else { return }

        var why: String?
        if fm.fileExists(atPath: userdataBrokenStampPath) {
            why = "the previous boot ended in init_user0_failed"
        } else if let problem = Self.inspectUserdataHeader(path: userdataPath) {
            why = problem
        }
        guard let why = why else { return }

        if fm.fileExists(atPath: userdataBootedStampPath) || hasShippedSnapshot {
            HuskLog.log("guest", "userdata needs repair (\(why)) but it once booted "
                               + "or holds a snapshot; leaving the user's data alone")
            return
        }
        let onDisk = ((try? fm.attributesOfItem(atPath: userdataPath))?[.size] as? NSNumber)?
            .int64Value ?? 0
        if onDisk >= Self.establishedUserdataBytes {
            HuskLog.log("guest", "userdata needs repair (\(why)) but holds "
                               + "\(onDisk / 1_048_576) MiB; leaving it alone")
            return
        }

        let reseeds = Int((try? String(contentsOfFile: userdataReseedCountPath,
                                       encoding: .utf8)) ?? "") ?? 0
        guard reseeds < Self.userdataReseedLimit else {
            HuskLog.log("guest", "userdata needs repair (\(why)) but has already been "
                               + "re-seeded \(reseeds)x without a successful boot")
            return
        }

        guard let seed = Bundle.main.path(forResource: "lineage-vdb-seed", ofType: "qcow2") else {
            throw NSError(domain: "husk", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "lineage-vdb-seed.qcow2 missing from the app bundle"])
        }
        HuskLog.log("guest", "userdata is unusable (\(why)); re-seeding a clean "
                           + "partition (attempt \(reseeds + 1)/\(Self.userdataReseedLimit))")
        try fm.removeItem(atPath: userdataPath)
        try fm.copyItem(atPath: seed, toPath: userdataPath)
        try Self.userdataSeedVersion.write(toFile: userdataPath + ".seed",
                                           atomically: true, encoding: .utf8)
        try "\(reseeds + 1)".write(toFile: userdataReseedCountPath,
                                  atomically: true, encoding: .utf8)
        try? fm.removeItem(atPath: userdataBrokenStampPath)
    }

    /// One background session for the image and the snapshot parts alike: leaving the page, the Control Center or the
    /// app itself no longer abandons a gigabyte of progress -- iOS keeps the transfer and hands its events back, even
    /// after relaunching Husk to deliver them. Snapshot parts are tagged "part-N" and routed to the active fetcher.
    @discardableResult
    private func imageDownloadSession() -> URLSession {
        if let imageSession { return imageSession }
        let config = URLSessionConfiguration.background(withIdentifier: Self.imageSessionID)
        config.sessionSendsLaunchEvents = true
        let router = DownloadDelegate(owner: self)
        downloadDelegate = router
        let session = URLSession(configuration: config, delegate: router, delegateQueue: nil)
        imageSession = session
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                for t in tasks {
                    guard let found = t as? URLSessionDownloadTask, found.state != .canceling else { continue }
                    if found.taskDescription?.hasPrefix("part-") == true {
                        // Only an orphaned part gets cancelled: one belonging to a fetcher that died with the last
                        // run cannot rejoin the hash cleanly. A LIVE fetcher's part is still its own business --
                        // cancelling it here would strand the fetcher waiting on a task that never finishes.
                        if self.fetcher == nil { found.cancel() }
                        continue
                    }
                    self.task = found
                    if case .downloading = self.state {} else {
                        self.state = .downloading(progress: 0, received: found.countOfBytesReceived,
                                                  total: found.countOfBytesExpectedToReceive)
                    }
                    HuskLog.log("guest", "reattached to a guest-image download that outlived the last run "
                                         + "(\(found.countOfBytesReceived / 1_048_576) MiB in)")
                }
            }
        }
        return session
    }

    /// The delegate that answers the session: kept so snapshot parts can be routed to whichever fetcher is live.
    private var downloadDelegate: DownloadDelegate?

    /// Recreate the download sessions so a transfer still running in the background has a delegate to answer again.
    /// Called at launch and whenever the Android page is shown.
    func adoptPendingDownloads() { imageDownloadSession() }

    func download() {
        if case .downloading = state { return }
        state = .downloading(progress: 0, received: 0, total: 0)
        HuskLog.log("guest", "downloading guest image from \(Self.imageURL.absoluteString)")

        let session = imageDownloadSession()
        // The manifest names the file, so publishing a new image needs no new
        // app build. The constant is only the fallback for a first run that
        // could not reach the release.
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
            HuskLog.log("guest", "resuming where the earlier attempt stopped")
        } else {
            task = session.downloadTask(with: manifest?.imageURL ?? Self.imageURL)
        }
        task?.resume()
    }

    /// Fetch the pre-booted machine on demand, reporting progress like any other
    /// download.
    ///
    /// This exists because the automatic fetch only ran as the tail of a fresh
    /// guest-image download. Anyone who already had the image -- which is most
    /// people, and was the case that reported this -- turned the setting on and
    /// watched nothing happen, because there was no download for it to follow.
    /// True while the current download is the snapshot rather than the image.
    @Published private(set) var isFetchingSnapshot = false

    func downloadSnapshotNow() {
        if case .downloading = state { return }
        if hasShippedSnapshot {
            // A valid but older snapshot may be on disk when the manifest
            // offers a replacement. Do not let the presence check block that
            // update; only skip when the installed digest matches the release.
            guard let expected = manifest?.snapshot.sha256 else {
                HuskLog.log("guest", "snapshot already installed; release manifest unavailable")
                return
            }
            if installedSnapshotDigest == expected {
                HuskLog.log("guest", "snapshot already installed")
                return
            }
        }
        if let short = snapshotSpaceShortfall() {
            HuskLog.log("guest", "not fetching the pre-booted snapshot: \(short)")
            failed(String(localized: "Not enough free space for the pre-booted snapshot: \(short)."))
            return
        }
        isFetchingSnapshot = true
        state = .downloading(progress: 0, received: 0, total: 0)
        HuskLog.log("guest", "downloading pre-booted snapshot (about 2 GB)")
        fetcher = SnapshotFetcher(
            urls: manifest?.partURLs ?? Self.snapshotPartURLs,
            session: imageDownloadSession(),
            progress: { [weak self] got, total in
                Task { @MainActor in self?.progressed(received: got, total: total) }
            },
            completion: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.fetcher = nil
                    switch result {
                    case .success(let joined):
                        if let want = self.manifest?.snapshot.sha256, want != joined.digest {
                            try? FileManager.default.removeItem(at: joined.url)
                            self.isFetchingSnapshot = false
                            self.failed(String(localized: "The snapshot did not match the release (sha256 \(joined.digest.prefix(12)), expected \(want.prefix(12)))."))
                            return
                        }
                        self.finishedSnapshot(tempURL: joined.url, digest: joined.digest)
                    case .failure(let why):
                        self.isFetchingSnapshot = false
                        self.failed(why.localizedDescription)
                    }
                }
            })
        fetcher?.start()
    }

    /// Held so the fetcher outlives this call. The session's delegate needs to know it too: snapshot parts arriving
    /// off the main thread are routed to it there, before the temp file they report is removed.
    private var fetcher: SnapshotFetcher? {
        didSet { downloadDelegate?.fetcher = fetcher }
    }

    /// Unpack a downloaded snapshot over userdata.
    fileprivate func finishedSnapshot(tempURL: URL, digest: String?) {
        state = .installing
        HuskLog.log("guest", "unpacking snapshot (about 4 GB once expanded)")
        DispatchQueue.global(qos: .userInitiated).async {
            let dest = URL(fileURLWithPath: self.userdataPath)
            do {
                try? FileManager.default.removeItem(at: dest)
                try Self.gunzip(from: tempURL, to: dest)
                try? FileManager.default.removeItem(at: tempURL)
                try Self.userdataSeedVersion.write(toFile: self.userdataPath + ".seed",
                                                   atomically: true, encoding: .utf8)
                try Self.imageVersion.write(toFile: self.snapshotStampPath,
                                            atomically: true, encoding: .utf8)
                if let digest {
                    try? digest.write(toFile: self.snapshotDigestPath,
                                      atomically: true, encoding: .utf8)
                }
                self.recordSnapshotPins()
                let size = (try? FileManager.default
                    .attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
                HuskLog.log("guest", "snapshot ready (\(size ?? 0) bytes); "
                                   + "Android will be restored, not booted")
                DispatchQueue.main.async { self.isFetchingSnapshot = false; self.state = .ready }
            } catch {
                HuskLog.log("guest", "snapshot unpack failed: \(error)")
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.removeItem(atPath: self.snapshotStampPath)
                DispatchQueue.main.async {
                    self.isFetchingSnapshot = false
                    self.state = .failed(String(localized: "Could not unpack the snapshot: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// Fetch the pre-booted machine and unpack it over userdata.
    ///
    /// Runs after the system image is in place, because the snapshot is only
    /// meaningful alongside the image it was booted from.
    func downloadSnapshot(completion: @escaping (Bool) -> Void) {
        HuskLog.log("guest", "downloading pre-booted snapshot (about 2 GB, "
                           + "\(Self.snapshotPartCount) parts)")
        let expected = manifest?.snapshot.sha256
        fetcher = SnapshotFetcher(
            urls: manifest?.partURLs ?? Self.snapshotPartURLs,
            session: imageDownloadSession(),
            progress: { [weak self] got, total in
                Task { @MainActor in self?.progressed(received: got, total: total) }
            },
            completion: { [weak self] result in
                guard let self else { completion(false); return }
                Task { @MainActor in self.fetcher = nil }
                guard case .success(let fetched) = result else {
                    if case .failure(let why) = result {
                        HuskLog.log("guest", "snapshot download failed: "
                                           + why.localizedDescription)
                    }
                    completion(false); return
                }
                if let want = expected, want != fetched.digest {
                    try? FileManager.default.removeItem(at: fetched.url)
                    HuskLog.log("guest", "snapshot rejected: sha256 "
                              + "\(fetched.digest.prefix(12)) but the release says "
                              + "\(want.prefix(12))")
                    completion(false); return
                }
                let dest = URL(fileURLWithPath: self.userdataPath)
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try Self.gunzip(from: fetched.url, to: dest)
                    try? FileManager.default.removeItem(at: fetched.url)
                    try? fetched.digest.write(toFile: self.snapshotDigestPath,
                                              atomically: true, encoding: .utf8)
                    try Self.userdataSeedVersion.write(toFile: self.userdataPath + ".seed",
                                                       atomically: true, encoding: .utf8)
                    self.recordSnapshotPins()
                    let size = (try? FileManager.default
                        .attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
                    HuskLog.log("guest", "snapshot unpacked (\(size ?? 0) bytes)")
                    completion(true)
                } catch {
                    HuskLog.log("guest", "snapshot unpack failed: \(error)")
                    try? FileManager.default.removeItem(at: dest)
                    completion(false)
                }
            })
        fetcher?.start()
    }

    /// What unpacking the snapshot takes on disk at its peak: the joined archive and the expanded disk side by side (#75, #128:
    /// a phone that ran out partway used to crash, because the old FileHandle.write raises instead of throwing, and the next
    /// launch offered the download again). nil when it fits.
    private func snapshotSpaceShortfall() -> String? {
        let archive = manifest?.snapshot.size ?? 2_200_000_000
        let expanded: Int64 = 5_000_000_000
        let margin: Int64 = 500_000_000
        let current = ((try? FileManager.default.attributesOfItem(atPath: userdataPath))?[.size] as? NSNumber)?.int64Value ?? 0
        let need = archive + expanded + margin - current
        guard let free = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        else { return nil }
        guard free < need else { return nil }
        let gb = { (b: Int64) in String(format: "%.1f GB", Double(b) / 1e9) }
        return String(localized: "it needs \(gb(need)) free and the device has \(gb(free))")
    }

    /// The staging files of a download or unpack that a previous run did not live to finish: gigabytes in tmp that iOS only
    /// clears when it decides to, and that left the next attempt even shorter of space.
    private func removeStaleDownloads() {
        guard fetcher == nil, task == nil else { return }
        let tmp = FileManager.default.temporaryDirectory
        // A staged image is not stale: it is a download that finished and was never installed -- iOS can
        // deliver didFinish and suspend us before finished() runs. Deleting it makes the gigabyte download
        // again for no reason; validating and installing it costs a hash pass and saves the whole transfer.
        let stagedImage = tmp.appendingPathComponent("husk-guest-download.qcow2")
        if FileManager.default.fileExists(atPath: stagedImage.path) {
            state = .installing
            DispatchQueue.global(qos: .utility).async {
                let digest = DigestWriter.ofFile(at: stagedImage.path)
                Task { @MainActor in self.finished(tempURL: stagedImage, digest: digest) }
            }
        }
        let snapshotStaged = tmp.appendingPathComponent("husk-snapshot-download.gz").path
        if let size = (try? FileManager.default.attributesOfItem(atPath: snapshotStaged))?[.size] as? NSNumber {
            try? FileManager.default.removeItem(atPath: snapshotStaged)
            HuskLog.log("guest", "removed husk-snapshot-download.gz (\(size.int64Value >> 20) MiB) left by an earlier run")
        }
    }

    /// Remember the machine the installed snapshot expects.
    ///
    /// QEMU refuses a restore whose RAM differs by a byte ("Size mismatch:
    /// huskram"), so these have to describe the snapshot on disk rather than
    /// whatever this build of the app happens to prefer.
    nonisolated fileprivate func recordSnapshotPins() {
        guard let snap = snapshotPinsToRecord else { return }
        var json: [String: Any] = ["guestMiB": snap.guestMiB,
                                   "xres": snap.xres, "yres": snap.yres]
        if let smp = snap.smp { json["smp"] = smp }
        if let cpu = snap.cpu { json["cpu"] = cpu }
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            try? data.write(to: URL(fileURLWithPath: snapshotPinsPath))
            HuskLog.log("guest", "snapshot needs \(snap.guestMiB) MiB at "
                               + "\(snap.xres)x\(snap.yres)")
        }
    }

    /// Captured when the manifest is fetched, because the pins are needed on a
    /// background queue where the main-actor `manifest` cannot be read.
    nonisolated(unsafe) fileprivate var snapshotPinsToRecord: GuestManifest.Snapshot?

    /// Streaming gunzip.
    ///
    /// Apple's Compression framework speaks raw DEFLATE, not the gzip
    /// container, so the header is parsed and skipped by hand. Streamed in
    /// chunks because the output is nearly four gigabytes and will not be held
    /// in memory on a phone.
    static func gunzip(from src: URL, to dst: URL) throws {
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let output = try FileHandle(forWritingTo: dst)
        defer { try? output.close() }

        // Gzip header: magic, method, flags, mtime, xfl, os -- then optional
        // extra field, name, comment and header CRC, in that order.
        var head = try input.read(upToCount: 10) ?? Data()
        guard head.count == 10, head[0] == 0x1f, head[1] == 0x8b, head[2] == 8 else {
            throw NSError(domain: "husk", code: 1, userInfo:
                [NSLocalizedDescriptionKey: "not a gzip file"])
        }
        let flg = head[3]
        if flg & 0x04 != 0 {                                  // FEXTRA
            let n = try input.read(upToCount: 2) ?? Data()
            let len = Int(n[0]) | (Int(n[1]) << 8)
            _ = try input.read(upToCount: len)
        }
        for mask in [UInt8(0x08), UInt8(0x10)] where flg & mask != 0 {   // FNAME, FCOMMENT
            while let b = try input.read(upToCount: 1), b.count == 1, b[0] != 0 {}
        }
        if flg & 0x02 != 0 { _ = try input.read(upToCount: 2) }          // FHCRC
        head = Data()

        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
                                        dst_size: 0,
                                        src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
                                        src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE,
                                      COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw NSError(domain: "husk", code: 2, userInfo:
                [NSLocalizedDescriptionKey: "inflate init failed"])
        }
        defer { compression_stream_destroy(&stream) }

        let chunk = 1 << 20
        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { outBuf.deallocate() }
        var finished = false

        while !finished {
            let data = try input.read(upToCount: chunk) ?? Data()
            let last = data.isEmpty
            try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                stream.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress
                    ?? UnsafePointer<UInt8>(bitPattern: 1)!
                stream.src_size = data.count
                repeat {
                    stream.dst_ptr = outBuf
                    stream.dst_size = chunk
                    let st = compression_stream_process(&stream, last ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                    let produced = chunk - stream.dst_size
                    if produced > 0 {
                        try output.write(contentsOf: Data(bytes: outBuf, count: produced))
                    }
                    if st == COMPRESSION_STATUS_END { finished = true; break }
                    if st == COMPRESSION_STATUS_ERROR {
                        throw NSError(domain: "husk", code: 3, userInfo:
                            [NSLocalizedDescriptionKey: "inflate failed"])
                    }
                } while stream.src_size > 0 || (last && !finished)
            }
            if last { finished = true }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        resumeData = nil
        // A snapshot fetch in flight holds part tasks on the same session -- "cancel" means those too.
        if fetcher != nil {
            imageSession?.getAllTasks { tasks in
                tasks.filter { $0.taskDescription?.hasPrefix("part-") == true }
                     .forEach { $0.cancel() }
            }
            fetcher = nil
            isFetchingSnapshot = false
        }
        // What is on disk decides the state -- during a snapshot fetch the image is already installed,
        // so missing would be the wrong thing to show.
        state = .missing
        refresh()
        HuskLog.log("guest", "download cancelled")
    }

    fileprivate func finished(tempURL: URL, digest: String?) {
        state = .installing
        HuskLog.log("guest", "download complete; installing")
        // A download that arrived is not a download that arrived intact. When
        // the release says what the bytes should hash to, insist on it -- a
        // truncated image otherwise installs cleanly and fails much later,
        // inside QEMU, as something that looks nothing like a bad download.
        if let want = manifest?.image.sha256, let got = digest, want != got {
            try? FileManager.default.removeItem(at: tempURL)
            HuskLog.log("guest", "image rejected: sha256 \(got.prefix(12)) but the "
                               + "release says \(want.prefix(12))")
            state = .failed("The downloaded image did not match the release. Tap to retry.")
            return
        }
        // Validate BEFORE installing, so a bad download never becomes the thing
        // QEMU is asked to boot.
        let check = Self.validate(path: tempURL.path)
        if let why = check.problem {
            try? FileManager.default.removeItem(at: tempURL)
            HuskLog.log("guest", "downloaded file rejected: \(why)")
            state = .failed(String(localized: "Download did not produce a disk image: \(why)"))
            return
        }
        let size = check.size ?? 0
        do {
                let dest = URL(fileURLWithPath: diskPath)
                try? FileManager.default.removeItem(at: dest)
                // Moved, not copied: the image is over a gigabyte and the device
                // does not need two of them on disk at once.
                try FileManager.default.moveItem(at: tempURL, to: dest)
                try? Self.imageVersion.write(toFile: versionStampPath,
                                             atomically: true, encoding: .utf8)
                if let digest {
                    try? digest.write(toFile: imageDigestPath, atomically: true, encoding: .utf8)
                }
                // A new system image usually invalidates the snapshot taken
                // against the old one -- but not always, and the manifest is
                // what knows. v11 differs from v10 only in a GRUB toggle read
                // before Android exists, which a restored machine never reads;
                // the same snapshot restores onto it perfectly well. Dropping
                // the stamp unconditionally would have charged everyone two
                // gigabytes for a two-byte change.
                if let published = manifest?.snapshot.sha256,
                   installedSnapshotDigest == published {
                    HuskLog.log("guest", "snapshot is unchanged in the manifest; keeping it")
                } else {
                    try? FileManager.default.removeItem(atPath: snapshotDigestPath)
                }
                HuskLog.log("guest", "guest image ready (\(size) bytes, \(Self.imageVersion))")
                // The snapshot only makes sense next to the image it was booted
                // from, so it is fetched after, not alongside.
                if Self.wantsSnapshot, !hasShippedSnapshot, let short = snapshotSpaceShortfall() {
                    HuskLog.log("guest", "not fetching the pre-booted snapshot: \(short); Android will boot from cold")
                    state = .ready
                } else if Self.wantsSnapshot, !hasShippedSnapshot {
                    state = .installing
                    downloadSnapshot { ok in
                        DispatchQueue.main.async {
                            if ok {
                                try? Self.imageVersion.write(toFile: self.snapshotStampPath,
                                                            atomically: true, encoding: .utf8)
                                HuskLog.log("guest", "pre-booted snapshot installed; "
                                                   + "first launch will restore instead of booting")
                            } else {
                                HuskLog.log("guest", "no snapshot; Android will boot from cold")
                            }
                            self.state = .ready
                        }
                    }
                } else {
                    state = .ready
                }
        } catch {
            HuskLog.log("guest", "FAIL: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    fileprivate func progressed(received: Int64, total: Int64) {
        let p = total > 0 ? Double(received) / Double(total) : 0
        state = .downloading(progress: p, received: received, total: total)
    }

    fileprivate func failed(_ message: String) {
        HuskLog.log("guest", "download FAILED: \(message)")
        state = .failed(message)
    }

    /// A download that stopped short of "cancelled": keep whatever iOS kept of it so the next try continues.
    fileprivate func downloadStopped(_ message: String, resumeData: Data?) {
        self.resumeData = resumeData
        failed(resumeData != nil
               ? String(localized: "\(message) Trying again continues where it stopped.")
               : message)
    }

    /// All events for a background transfer are handled; answer iOS so it can suspend Husk again.
    fileprivate func backgroundEventsHandled() {
        backgroundCompletion?()
        backgroundCompletion = nil
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var owner: GuestImage?
    /// Snapshot parts ("part-N" task descriptions) are routed here: the fetcher's logic
    /// runs on this delegate queue, where the delivered temp file is still valid.
    weak var fetcher: SnapshotFetcher?
    init(owner: GuestImage) { self.owner = owner }

    private static func isPart(_ task: URLSessionTask) -> Bool {
        task.taskDescription?.hasPrefix("part-") == true
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if Self.isPart(downloadTask) {
            if let fetcher {
                fetcher.downloaded(downloadTask, to: location)
            } else {
                // The fetcher that asked for it is gone; nothing can safely claim the bytes.
                try? FileManager.default.removeItem(at: location)
            }
            return
        }
        // A download task reports "finished" for any completed HTTP exchange,
        // including a 404 -- whose body then lands on disk as if it were the file
        // asked for. This is exactly how a 9-byte "Not Found" once became the
        // guest disk image. Check the status before treating it as the payload.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let body = (try? String(contentsOf: location, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = body.isEmpty ? "" : " — server said: \(body.prefix(200))"
            let url = downloadTask.originalRequest?.url?.absoluteString ?? "?"
            Task { @MainActor in
                self.owner?.failed(String(localized: "HTTP \(http.statusCode) from \(url)\(detail)"))
            }
            return
        }

        // The temp file is deleted when this returns, so move it somewhere stable
        // before handing it over.
        let stable = FileManager.default.temporaryDirectory
            .appendingPathComponent("husk-guest-download.qcow2")
        try? FileManager.default.removeItem(at: stable)
        do {
            try FileManager.default.moveItem(at: location, to: stable)
        } catch {
            Task { @MainActor in
                self.owner?.failed(String(localized: "could not stage download: \(error.localizedDescription)"))
            }
            return
        }
        // Hashed here rather than on the main actor: this delegate callback is
        // already off the main thread, and a gigabyte is not something to digest
        // while the UI waits.
        let digest = DigestWriter.ofFile(at: stable.path)
        Task { @MainActor in self.owner?.finished(tempURL: stable, digest: digest) }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if Self.isPart(downloadTask) {
            fetcher?.wrote(downloadTask, totalBytesWritten: totalBytesWritten,
                           totalBytesExpectedToWrite: totalBytesExpectedToWrite)
            return
        }
        Task { @MainActor in
            self.owner?.progressed(received: totalBytesWritten,
                                   total: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if Self.isPart(task) {
            fetcher?.completed(task, error: error)
            return
        }
        guard let error else { return }
        let nsError = error as NSError
        // "Cancel Download" reports through the same channel -- it is not a failure to show in red.
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        let resume = nsError.userInfo["NSURLSessionDownloadTaskResumeData"] as? Data
        Task { @MainActor in self.owner?.downloadStopped(error.localizedDescription, resumeData: resume) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in self.owner?.backgroundEventsHandled() }
    }
}

/// Downloads the snapshot's parts in order and joins them into one file.
///
/// One part at a time, deliberately. Two gigabytes arriving in parallel would
/// need both in flight at once, and this runs on a phone that is about to be
/// asked for another four gigabytes to unpack into.
private final class SnapshotFetcher {
    private let urls: [URL]
    private let onProgress: (Int64, Int64) -> Void
    private let onDone: (Result<Joined, Error>) -> Void

    /// The joined archive and what it hashed to.
    struct Joined { let url: URL; let digest: String }

    /// Hashed as the parts are appended. The alternative is a second full pass
    /// over two gigabytes once the download finishes, for no extra information.
    private let hasher = DigestWriter()

    /// Where the joined archive is built up.
    private let staged = FileManager.default.temporaryDirectory
        .appendingPathComponent("husk-snapshot-download.gz")

    private var index = 0
    /// Bytes belonging to parts already appended, so progress does not restart
    /// at zero every time a part finishes.
    private var bytesDone: Int64 = 0

    /// The guest download session, shared with the image download. Its delegate routes
    /// part tasks here -- it is not this fetcher's to invalidate.
    private let session: URLSession

    init(urls: [URL], session: URLSession,
         progress: @escaping (Int64, Int64) -> Void,
         completion: @escaping (Result<Joined, Error>) -> Void) {
        self.urls = urls
        self.session = session
        self.onProgress = progress
        self.onDone = completion
    }

    func start() {
        // Parts a previous fetcher never finished still belong to this session.
        // Their bytes can no longer join correctly -- the running hash would not
        // cover them -- so they are cancelled and fetched again.
        session.getAllTasks { [weak self] stale in
            stale.filter { $0.taskDescription?.hasPrefix("part-") == true }
                 .forEach { $0.cancel() }
            guard let self else { return }
            try? FileManager.default.removeItem(at: self.staged)
            FileManager.default.createFile(atPath: self.staged.path, contents: nil)
            self.next()
        }
    }

    private func next() {
        guard index < urls.count else {
            let size = (try? FileManager.default
                .attributesOfItem(atPath: staged.path)[.size] as? Int) ?? 0
            let digest = hasher.finish()
            HuskLog.log("guest", "snapshot download complete (\(size ?? 0) bytes, "
                               + "sha256 \(digest.prefix(12))…)")
            onDone(.success(Joined(url: staged, digest: digest)))
            return
        }
        HuskLog.log("guest", "fetching snapshot part \(index + 1) of \(urls.count)")
        let task = session.downloadTask(with: urls[index])
        // Which part this is must survive a relaunch: a stale part arriving late
        // otherwise appends out of order and corrupts the join.
        task.taskDescription = "part-\(index)"
        task.resume()
    }

    private func fail(_ message: String) {
        try? FileManager.default.removeItem(at: staged)
        onDone(.failure(NSError(domain: "husk", code: 10,
                                userInfo: [NSLocalizedDescriptionKey: message])))
    }

    /// A part arrived. Called on the session's delegate queue: the temp file is
    /// removed when this returns, so it is joined here and now.
    func downloaded(_ downloadTask: URLSessionDownloadTask, to location: URL) {
        // A cancelled task can still deliver its file. A part whose description does
        // not match the part being fetched now belongs to an abandoned run -- its
        // bytes would corrupt the join, so it goes straight to the bin.
        guard downloadTask.taskDescription == "part-\(index)" else {
            try? FileManager.default.removeItem(at: location)
            return
        }
        // A completed exchange is not a successful one: a 404 body lands on disk
        // looking exactly like the file that was asked for.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            fail(String(localized: "HTTP \(http.statusCode) fetching \(downloadTask.originalRequest?.url?.lastPathComponent ?? "a snapshot part")"))
            return
        }
        do {
            let input = try FileHandle(forReadingFrom: location)
            defer { try? input.close() }
            let output = try FileHandle(forWritingTo: staged)
            defer { try? output.close() }
            try output.seekToEnd()
            while let chunk = try input.read(upToCount: 4 << 20), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
                hasher.update(chunk)
                bytesDone += Int64(chunk.count)
            }
        } catch {
            fail(String(localized: "could not join snapshot part \(index + 1): \(error.localizedDescription)"))
            return
        }
        try? FileManager.default.removeItem(at: location)
        index += 1
        next()
    }

    func wrote(_ downloadTask: URLSessionDownloadTask,
               totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // A stale part reporting bytes is not progress on the part being fetched now.
        guard downloadTask.taskDescription == "part-\(index)" else { return }
        // The parts are near enough the same size that one of them stands in for
        // the rest; the alternative is a HEAD request per part before starting,
        // which buys a smoother bar and nothing else.
        let remaining = Int64(urls.count - index - 1)
        let estimate = totalBytesExpectedToWrite > 0
            ? bytesDone + totalBytesExpectedToWrite * (remaining + 1)
            : 0
        onProgress(bytesDone + totalBytesWritten, estimate)
    }

    func completed(_ task: URLSessionTask, error: Error?) {
        // A stale task's error is its own business -- it must not kill the part in flight now.
        guard task.taskDescription == "part-\(index)" else { return }
        if let error, (error as NSError).code != NSURLErrorCancelled {
            fail(error.localizedDescription)
        }
    }
}
