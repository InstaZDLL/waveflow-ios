import Foundation

/// D'où vient la musique affichée.
///
/// Deux catalogues côte à côte, jamais mêlés : RFC-003 du serveur l'interdit
/// tant qu'aucun rapprochement fiable n'existe entre un fichier local et une
/// piste distante — et ce rapprochement se fait par empreinte du fichier
/// entier, pas par titre ni par durée. Une liste unique afficherait deux fois
/// le même morceau sans savoir que c'est le même.
nonisolated enum MusicSource: String, CaseIterable, Sendable {

    case local
    case server

    var label: String {
        switch self {
        case .local: "Sur l'iPhone"
        case .server: "Serveur"
        }
    }

    var symbol: String {
        switch self {
        case .local: "iphone"
        case .server: "server.rack"
        }
    }
}
