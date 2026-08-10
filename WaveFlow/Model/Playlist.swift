import Foundation

/// Une playlist créée dans l'application.
///
/// Première donnée qui n'a aucune source hors de l'appareil : elle ne se
/// déduit d'aucun tag, contrairement aux albums et aux artistes. C'est aussi
/// elle qui portera la synchronisation avec le serveur WaveFlow — d'où
/// [createdAt] et [updatedAt], que l'interface n'affiche pas mais dont une
/// résolution de conflits aura besoin.
///
/// - Note: là où Android tient deux tables Room et une colonne `position`,
///   l'ordre est ici porté par le tableau lui-même. Les positions ne peuvent
///   donc ni se trouer après un retrait, ni entrer en collision — la couche de
///   persistance les recalculera à l'écriture, elles ne sont pas du domaine.
nonisolated struct Playlist: Identifiable, Hashable, Sendable {

    /// Identifiant propre à l'application, tiré au sort plutôt qu'attribué par
    /// le stockage : la synchronisation devra rapprocher deux playlists créées
    /// sur deux appareils, ce qu'une clé auto-incrémentée locale ne permet
    /// pas.
    let id: UUID

    private(set) var name: String

    /// Contenu, dans l'ordre de lecture.
    ///
    /// Ce sont des [Song.id] — des chemins relatifs à `Documents`. Un
    /// identifiant peut ne plus rien désigner si le fichier a été retiré de
    /// l'appareil ; c'est [songs(in:)] qui décide quoi en faire, la playlist
    /// n'oublie rien d'elle-même.
    private(set) var songIds: [String]

    let createdAt: Date

    private(set) var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        songIds: [String] = [],
        createdAt: Date,
        updatedAt: Date? = nil,
    ) {
        self.id = id
        self.name = name
        self.songIds = songIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// Morceaux de la playlist, résolus contre la bibliothèque chargée.
    ///
    /// Un identifiant sans morceau correspondant est ignoré plutôt que retiré :
    /// un fichier absent aujourd'hui peut être réimporté demain, et une
    /// bibliothèque encore en cours de chargement viderait sinon toutes les
    /// playlists.
    func songs(in library: Library) -> [Song] {
        songIds.compactMap { library.songsByID[$0] }
    }

    /// Renomme la playlist. Un nom blanc est refusé : une playlist sans nom
    /// n'est plus désignable dans l'interface.
    mutating func rename(to newName: String, at date: Date) {
        guard let trimmed = newName.nonBlank, trimmed != name else { return }

        name = trimmed
        updatedAt = date
    }

    /// Ajoute un morceau en fin de playlist. Sans effet s'il y figure déjà.
    mutating func add(_ songId: String, at date: Date) {
        guard !songIds.contains(songId) else { return }

        songIds.append(songId)
        updatedAt = date
    }

    mutating func remove(_ songId: String, at date: Date) {
        guard let index = songIds.firstIndex(of: songId) else { return }

        songIds.remove(at: index)
        updatedAt = date
    }

    /// Réordonne la playlist selon `requested`.
    ///
    /// L'ordre complet plutôt qu'un couple (morceau, destination) : c'est ce
    /// que l'écran connaît après un glisser-déposer, et cela reste vrai même
    /// si la playlist a changé entre-temps.
    ///
    /// `requested` est normalisé avant d'être retenu — les identifiants
    /// étrangers à la playlist sont écartés, les doublons aussi, et les
    /// morceaux que l'appelant a omis sont replacés à la suite dans leur ordre
    /// actuel. L'omission n'est pas un cas d'école : l'écran ne liste que les
    /// morceaux résolus contre la bibliothèque, et un fichier disparu de
    /// `Documents` est absent de la liste affichée sans l'être de la playlist.
    /// Sans cette reprise, un glisser-déposer le supprimerait au passage.
    mutating func reorder(to requested: [String], at date: Date) {
        let stored = Set(songIds)

        var ordered: [String] = []
        var seen = Set<String>()
        for songId in requested where stored.contains(songId) && !seen.contains(songId) {
            ordered.append(songId)
            seen.insert(songId)
        }
        ordered += songIds.filter { !seen.contains($0) }

        // `updatedAt` n'est touché que si l'ordre a réellement changé : c'est
        // un horodatage de résolution de conflits, un glissé sans effet ne doit
        // pas faire croire à une modification.
        guard ordered != songIds else { return }

        songIds = ordered
        updatedAt = date
    }
}
