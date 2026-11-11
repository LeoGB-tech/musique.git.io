import SwiftUI
import UniformTypeIdentifiers

func fmt(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s)
    return String(format: "%d:%02d", t / 60, t % 60)
}

// MARK: Racine

struct RootView: View {
    @EnvironmentObject var library: LibraryStore
    var body: some View {
        if library.folderName == nil {
            SetupView()
        } else {
            TabView {
                ListenTab().tabItem { Label("Écouter", systemImage: "play.circle.fill") }
                LibraryTab().tabItem { Label("Bibliothèque", systemImage: "music.note.house.fill") }
                SearchTab().tabItem { Label("Recherche", systemImage: "magnifyingglass") }
            }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var picking = false
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list").font(.system(size: 64)).foregroundStyle(.red)
            Text("Ma Musique").font(.largeTitle.bold())
            Text("Choisis le dossier iCloud Drive qui contient la musique.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Choisir le dossier") { picking = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(32)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
            if case .success(let url) = r { library.setFolder(url) }
        }
    }
}

// MARK: Composants

struct ArtworkView: View {
    let track: Track?
    var corner: CGFloat = 8
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Rectangle().fill(Color(.systemGray5))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").foregroundStyle(.secondary).font(.title)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: track?.id) {
            if let t = track { image = await ArtworkLoader.shared.image(for: t) } else { image = nil }
        }
    }
}

struct SongRow: View {
    @EnvironmentObject var player: PlayerController
    let track: Track
    let list: [Track]
    var showArtwork = true
    var body: some View {
        Button { player.play(track, in: list) } label: {
            HStack(spacing: 12) {
                if showArtwork { ArtworkView(track: track, corner: 6).frame(width: 46, height: 46) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).lineLimit(1)
                        .foregroundStyle(player.current?.id == track.id ? Color.red : Color.primary)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !track.downloaded {
                    Image(systemName: "icloud.and.arrow.down").foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct AlbumGrid: View {
    let albums: [Album]
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 16)]
    var body: some View {
        LazyVGrid(columns: cols, spacing: 20) {
            ForEach(albums) { a in
                NavigationLink(value: a) {
                    VStack(alignment: .leading, spacing: 4) {
                        ArtworkView(track: a.tracks.first, corner: 10)
                        Text(a.title).font(.subheadline).lineLimit(1).foregroundStyle(.primary)
                        Text(a.artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

struct MiniPlayerInset: ViewModifier {
    @EnvironmentObject var player: PlayerController
    @State private var showNow = false
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let t = player.current {
                    HStack(spacing: 12) {
                        HStack(spacing: 12) {
                            ArtworkView(track: t, corner: 6).frame(width: 44, height: 44)
                            Text(t.title).lineLimit(1).font(.subheadline)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { showNow = true }
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                        }
                        Button { player.next() } label: { Image(systemName: "forward.fill").font(.title3) }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 8)
                }
            }
            .sheet(isPresented: $showNow) { NowPlayingView() }
    }
}

extension View {
    func miniPlayer() -> some View { modifier(MiniPlayerInset()) }
}

// MARK: Onglets

struct ListenTab: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerController
    var body: some View {
        NavigationStack {
            ScrollView {
                if library.tracks.isEmpty {
                    ContentUnavailableView("Aucune musique", systemImage: "music.note",
                                           description: Text(library.isScanning ? "Analyse du dossier…" : "Aucun fichier audio trouvé dans ce dossier."))
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        if library.pendingDownloads > 0 {
                            Label("Téléchargement depuis iCloud : \(library.pendingDownloads) titre(s) restant(s)", systemImage: "icloud.and.arrow.down")
                                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                        }
                        Button { player.shuffle(library.tracks) } label: {
                            Label("Lecture aléatoire", systemImage: "shuffle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal)
                        AlbumGrid(albums: library.albums)
                    }
                }
            }
            .refreshable { library.rescan() }
            .navigationTitle("Écouter")
            .navigationDestination(for: Album.self) { AlbumDetail(album: $0) }
        }
        .miniPlayer()
    }
}

struct LibraryTab: View {
    @EnvironmentObject var library: LibraryStore
    @State private var picking = false
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { ArtistsView() } label: { Label("Artistes", systemImage: "music.mic") }
                NavigationLink { ScrollView { AlbumGrid(albums: library.albums) }.navigationTitle("Albums") } label: { Label("Albums", systemImage: "square.stack") }
                NavigationLink { SongsView() } label: { Label("Titres", systemImage: "music.note") }
            }
            .navigationTitle("Bibliothèque")
            .navigationDestination(for: Album.self) { AlbumDetail(album: $0) }
            .toolbar {
                Menu {
                    Button("Actualiser", systemImage: "arrow.clockwise") { library.rescan() }
                    Button("Changer de dossier", systemImage: "folder") { picking = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
                if case .success(let url) = r { library.setFolder(url) }
            }
        }
        .miniPlayer()
    }
}

struct ArtistsView: View {
    @EnvironmentObject var library: LibraryStore
    var body: some View {
        List(library.artists, id: \.self) { a in
            NavigationLink(a) { ArtistDetail(name: a) }
        }
        .navigationTitle("Artistes")
    }
}

struct ArtistDetail: View {
    @EnvironmentObject var library: LibraryStore
    let name: String
    var body: some View {
        let list = library.tracks.filter { $0.artist == name }
        List(list) { SongRow(track: $0, list: list) }
            .listStyle(.plain)
            .navigationTitle(name)
    }
}

struct SongsView: View {
    @EnvironmentObject var library: LibraryStore
    var body: some View {
        List(library.tracks) { SongRow(track: $0, list: library.tracks) }
            .listStyle(.plain)
            .navigationTitle("Titres")
    }
}

struct SearchTab: View {
    @EnvironmentObject var library: LibraryStore
    @State private var q = ""
    var body: some View {
        NavigationStack {
            let results = q.isEmpty ? [] : library.tracks.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                $0.artist.localizedCaseInsensitiveContains(q) ||
                $0.album.localizedCaseInsensitiveContains(q)
            }
            List(results) { SongRow(track: $0, list: results) }
                .listStyle(.plain)
                .navigationTitle("Recherche")
                .searchable(text: $q, prompt: "Titres, artistes, albums")
        }
        .miniPlayer()
    }
}

struct AlbumDetail: View {
    @EnvironmentObject var player: PlayerController
    let album: Album
    var body: some View {
        List {
            VStack(spacing: 8) {
                ArtworkView(track: album.tracks.first, corner: 12).frame(width: 240, height: 240).shadow(radius: 8)
                Text(album.title).font(.title3.bold()).multilineTextAlignment(.center)
                Text(album.artist).foregroundStyle(.red)
                HStack {
                    Button { if let f = album.tracks.first { player.play(f, in: album.tracks) } } label: {
                        Label("Lecture", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                    Button { player.shuffle(album.tracks) } label: {
                        Label("Aléatoire", systemImage: "shuffle").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            ForEach(album.tracks) { SongRow(track: $0, list: album.tracks, showArtwork: false) }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Lecteur plein écran

struct NowPlayingView: View {
    @EnvironmentObject var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(Color.secondary).frame(width: 40, height: 5).padding(.top, 10)
                .onTapGesture { dismiss() }
            Spacer()
            ArtworkView(track: player.current, corner: 14).padding(.horizontal, 32).shadow(radius: 20)
            VStack(spacing: 4) {
                Text(player.current?.title ?? "").font(.title2.bold()).lineLimit(1)
                Text(player.current?.artist ?? "").foregroundStyle(.red).lineLimit(1)
            }
            VStack {
                Slider(value: Binding(get: { player.position }, set: { player.seek(to: $0) }),
                       in: 0...max(player.duration, 1))
                HStack {
                    Text(fmt(player.position))
                    Spacer()
                    Text("-" + fmt(player.duration - player.position))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            HStack(spacing: 48) {
                Button { player.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44))
                }
                Button { player.next() } label: { Image(systemName: "forward.fill").font(.title) }
            }
            .foregroundStyle(.primary)
            Spacer()
        }
    }
}
