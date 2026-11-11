import Foundation
import AVFoundation
import UIKit

private let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "aiff", "aif", "caf", "alac"]

struct Track: Identifiable, Hashable {
    let id: String
    let url: URL
    var title: String
    var artist: String
    var album: String
    var downloaded: Bool
}

struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let tracks: [Track]
    static func == (l: Album, r: Album) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Meta: Codable {
    var title: String?
    var artist: String?
    var album: String?
}

struct RawFile {
    let id: String
    let url: URL
    let downloaded: Bool
    let folder: String?
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var albums: [Album] = []
    @Published private(set) var artists: [String] = []
    @Published private(set) var folderName: String?
    @Published private(set) var pendingDownloads = 0
    @Published private(set) var isScanning = false

    private var rootURL: URL?
    private var metaCache: [String: Meta] = [:]
    private var scanTask: Task<Void, Never>?
    private let bookmarkKey = "musicFolderBookmark"

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("meta.json")
    }

    // MARK: Dossier

    func restore() {
        guard rootURL == nil, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return }
        if let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode([String: Meta].self, from: d) {
            metaCache = c
        }
        open(url, saveBookmark: stale)
    }

    func setFolder(_ url: URL) {
        metaCache = [:]
        open(url, saveBookmark: true)
    }

    private func open(_ url: URL, saveBookmark: Bool) {
        rootURL?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else { return }
        if saveBookmark, let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        rootURL = url
        folderName = url.lastPathComponent
        tracks = []
        rescan()
    }

    // MARK: Scan

    func rescan() {
        guard let root = rootURL else { return }
        scanTask?.cancel()
        isScanning = true
        scanTask = Task { [weak self] in
            var attempts = 0
            while !Task.isCancelled {
                let raws = await Task.detached(priority: .utility) { LibraryStore.scan(root) }.value
                guard let self else { return }
                self.rebuild(raws)
                await self.enrich(raws)
                let pending = raws.filter { !$0.downloaded }.count
                self.pendingDownloads = pending
                attempts += 1
                if pending == 0 || attempts >= 60 { break }
                try? await Task.sleep(for: .seconds(10))
            }
            self?.isScanning = false
        }
    }

    nonisolated static func scan(_ root: URL) -> [RawFile] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey], options: [.skipsPackageDescendants]) else { return [] }
        var out: [RawFile] = []
        for case let url as URL in en {
            var name = url.lastPathComponent
            var real = url
            var downloaded = true
            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(7))
                real = url.deletingLastPathComponent().appendingPathComponent(name)
                downloaded = false
            } else if name.hasPrefix(".") {
                continue
            }
            let ext = (name as NSString).pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }
            if downloaded,
               let st = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
               st == .notDownloaded {
                downloaded = false
            }
            if !downloaded { try? fm.startDownloadingUbiquitousItem(at: real) }
            let parent = real.deletingLastPathComponent()
            let folder: String? = parent.path == root.path ? nil : parent.lastPathComponent
            let id = real.path.replacingOccurrences(of: root.path, with: "")
            out.append(RawFile(id: id, url: real, downloaded: downloaded, folder: folder))
        }
        return out
    }

    private func enrich(_ raws: [RawFile]) async {
        let todo = raws.filter { $0.downloaded && metaCache[$0.id] == nil }
        guard !todo.isEmpty else { return }
        let size = 24
        var i = 0
        while i < todo.count {
            if Task.isCancelled { return }
            let chunk = Array(todo[i..<min(i + size, todo.count)])
            let results = await withTaskGroup(of: (String, Meta).self) { group in
                for f in chunk { group.addTask { (f.id, await LibraryStore.readMeta(f.url)) } }
                var out: [(String, Meta)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (id, m) in results { metaCache[id] = m }
            rebuild(raws)
            i += size
        }
        if let d = try? JSONEncoder().encode(metaCache) { try? d.write(to: cacheURL) }
    }

    nonisolated static func readMeta(_ url: URL) async -> Meta {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return Meta() }
        func value(_ id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first else { return nil }
            guard let s = try? await item.load(.stringValue) else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return Meta(title: await value(.commonIdentifierTitle),
                    artist: await value(.commonIdentifierArtist),
                    album: await value(.commonIdentifierAlbumName))
    }

    private func rebuild(_ raws: [RawFile]) {
        let built = raws.map { r -> Track in
            let m = metaCache[r.id]
            let base = (r.url.lastPathComponent as NSString).deletingPathExtension
            return Track(id: r.id, url: r.url,
                         title: m?.title ?? base,
                         artist: m?.artist ?? "Artiste inconnu",
                         album: m?.album ?? r.folder ?? "Titres divers",
                         downloaded: r.downloaded)
        }
        tracks = built.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        albums = Dictionary(grouping: built, by: \.album).map { name, ts in
            let sorted = ts.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
            let arts = Set(ts.map(\.artist))
            return Album(id: name, title: name, artist: arts.count == 1 ? arts.first! : "Artistes divers", tracks: sorted)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        artists = Array(Set(built.map(\.artist))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: Pochettes

@MainActor
final class ArtworkLoader {
    static let shared = ArtworkLoader()
    private let cache = NSCache<NSString, UIImage>()

    func image(for track: Track) async -> UIImage? {
        if let c = cache.object(forKey: track.id as NSString) { return c }
        guard track.downloaded else { return nil }
        guard let data = await Self.loadData(track.url), let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: track.id as NSString)
        return img
    }

    nonisolated static func loadData(_ url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first else { return nil }
        guard let data = try? await item.load(.dataValue) else { return nil }
        return data
    }
}
