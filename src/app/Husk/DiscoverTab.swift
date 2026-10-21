// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Apps from the repositories you add, to install into Android. Pushed from Settings, so it has no navigation stack of its own.
struct DiscoverView: View {
    @ObservedObject private var manager = SourceManager.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var tlStore = TranslationLayerStore.shared

    @State private var showingSources = false
    @State private var showingAddSource = false
    @State private var newSourceURL = ""
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    /// The Translation Layer app the Open button is about to play.
    @State private var playing: TLApp?

    var body: some View {
        Group {
            if manager.isLoading && manager.sources.isEmpty {
                ProgressView("Fetching Repositories…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.sources.isEmpty {
                EmptyState(title: "No Repositories",
                           message: "Add a source to start discovering apps.",
                           systemImage: "tray",
                           actionTitle: "Add Source",
                           action: { showingAddSource = true })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .background(Theme.backdrop)
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search \(totalAppCount) apps")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await manager.fetchSources() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Menu {
                    Button { showingAddSource = true } label: {
                        Label("Add Source", systemImage: "plus")
                    }
                    Button { showingSources = true } label: {
                        Label("Manage Repositories", systemImage: "list.bullet")
                    }
                } label: { Label("Repositories", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showingSources) { sourcesSheet }
        .sheet(isPresented: $showingAddSource) { addSourceSheet }
        // A route:tl install opens in the same game screen the Library uses.
        .fullScreenCover(item: $playing) { app in TLAttemptView(app: app) }
        .onAppear {
            if manager.sources.isEmpty && !manager.isLoading {
                Task { await manager.fetchSources() }
            }
        }
        .task(id: searchText) {
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                debouncedSearchText = searchText
            } catch {}
        }
    }

    private var list: some View {
        List {
            ForEach(manager.sources) { source in
                let filtered = filteredApps(for: source)
                if !filtered.isEmpty {
                    sourceSection(source, apps: filtered)
                }
            }
            if !manager.fetchErrors.isEmpty {
                Section {
                    ForEach(manager.fetchErrors.keys.sorted(), id: \.self) { url in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url).font(.footnote).lineLimit(1)
                                Text(manager.fetchErrors[url] ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                } header: { Text("Could Not Load") }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var totalAppCount: Int {
        manager.sources.reduce(0) { $0 + $1.apps.count }
    }

    // MARK: - Helpers

    private func filteredApps(for source: AppSource) -> [SourceApp] {
        if debouncedSearchText.isEmpty { return source.apps }
        let query = debouncedSearchText.lowercased()
        return source.apps.filter {
            $0.name.lowercased().contains(query) ||
            $0.bundleIdentifier.lowercased().contains(query)
        }
    }

    private func sourceSection(_ source: AppSource, apps: [SourceApp]) -> some View {
        let displayApps = debouncedSearchText.isEmpty ? Array(apps.prefix(50)) : apps
        return Section {
            ForEach(displayApps) { app in appRow(app) }
        } header: {
            Text(source.name)
        } footer: {
            if debouncedSearchText.isEmpty && apps.count > 50 {
                Text("Search to see \(apps.count - 50) more apps.")
            }
        }
    }

    private func appRow(_ app: SourceApp) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: app.iconURL)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else if phase.error != nil {
                    Image(systemName: "app.dashed").font(.title).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.body.weight(.medium)).lineLimit(1)
                Text(app.localizedDescription)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let error = manager.downloadErrors[app.bundleIdentifier] {
                    Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            // "Installed" means either place an install can land: the guest's
            // package list, or the Translation Layer's library.
            let tlApp = tlStore.apps.first { $0.packageName == app.bundleIdentifier }
            let isInstalled = host.packages.contains { $0.id == app.bundleIdentifier } || tlApp != nil
            let progress = manager.downloadProgress[app.bundleIdentifier]

            if isInstalled {
                Button("Open") {
                    if let tlApp {
                        playing = tlApp
                        return
                    }
                    // The identifier came from a remote repo index: it reaches a
                    // shell inside the guest, so only a real package name may go.
                    let pkg = app.bundleIdentifier
                    let safe = pkg.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }
                    guard safe else { return }
                    let intent = "am start -n \(pkg)/\(pkg).MainActivity"
                    _ = try? GuestBridge.shared.shell(intent, timeout: 5)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            } else if let progress = progress {
                // The stop glyph always suggested a cancel; now it is one.
                Button { manager.cancelDownload(bundleIdentifier: app.bundleIdentifier) } label: {
                    ZStack {
                        Circle().stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 3)
                        Circle().trim(from: 0, to: progress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "stop.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Cancel Download")
            } else {
                Button("Get") { manager.downloadAndInstall(app: app) }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }

    // MARK: - Add Source Sheet

    private var addSourceSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://f-droid.org/repo/index-v1.json", text: $newSourceURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Source URL")
                } footer: {
                    Text("Paste any F-Droid-compatible repository index URL.")
                }

                Section("Presets") {
                    ForEach([
                        ("F-Droid", "https://f-droid.org/repo/index-v1.json"),
                        ("IzzyOnDroid", "https://apt.izzysoft.de/fdroid/repo/index-v1.json"),
                        ("Guardian Project", "https://guardianproject.info/fdroid/repo/index-v1.json"),
                    ], id: \.0) { name, url in
                        Button { newSourceURL = url } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name).foregroundStyle(.primary)
                                    Text(url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if newSourceURL == url {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { newSourceURL = ""; showingAddSource = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let url = newSourceURL
                        newSourceURL = ""
                        showingAddSource = false
                        guard !url.isEmpty, URL(string: url) != nil else { return }
                        Task { await manager.addSource(urlString: url) }
                    }
                    .disabled(newSourceURL.isEmpty)
                    .huskBold()
                }
            }
        }
    }

    // MARK: - Manage Sources Sheet

    private var sourcesSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(manager.sourceURLs, id: \.self) { url in
                        VStack(alignment: .leading, spacing: 2) {
                            if let source = manager.sources.first(where: { $0.identifier == url }) {
                                Text(source.name).font(.body.weight(.medium))
                                Text("\(source.apps.count) apps").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { manager.sourceURLs.remove(atOffsets: $0) }
                } header: { Text("Active Repositories") }
            }
            .navigationTitle("Repositories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { showingSources = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSources = false; showingAddSource = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}
