// swift-tools-version: 6.2
import PackageDescription

// Harnais de test Linux.
//
// Le projet est un projet Xcode : ce package ne le remplace pas et ne construit
// jamais l'application. Il n'existe que pour exécuter la suite de tests sans
// Mac, sur la part du code qui ne dépend d'aucun framework Apple — Foundation
// est disponible sur Linux, SwiftUI / AVFoundation / MediaPlayer / UIKit /
// CryptoKit ne le sont pas.
//
// Les sources sont des liens symboliques relatifs vers le dépôt : rien n'est
// dupliqué, et un test écrit ici s'exécute tel quel sous Xcode. Le target
// s'appelle `WaveFlow` pour que le `@testable import WaveFlow` des tests soit
// le même des deux côtés.
//
//     cd Tools/LinuxHarness && swift test
//
// Faire entrer un nouveau fichier dans le périmètre = ajouter un lien dans
// Sources/WaveFlow/ :
//
//     ln -s ../../../../WaveFlow/Model/Playlist.swift Sources/WaveFlow/
//
// Les tests, eux, sont pris automatiquement : Tests/WaveFlowTests est un lien
// vers le dossier du dépôt. Un test qui dépendrait d'un framework Apple casse
// donc ce package — l'exclure ici, et le laisser à la CI macOS.
// Alignés sur le projet Xcode (`SWIFT_VERSION = 5.0`,
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Sans eux, les diagnostics
// d'isolation divergeraient de ceux de la vraie compilation et le harnais
// validerait du code que la CI refuse.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "WaveFlow",
    // Sans plancher déclaré, SwiftPM vise macOS 10.13 et refuse tout ce qui est
    // arrivé depuis — `AsyncThrowingStream` (10.15) en tête. Linux n'a pas de
    // contrainte d'availability, le harnais passait donc là-bas et échouait
    // depuis un Mac, où il est pourtant le seul moyen de vérifier qu'on n'a pas
    // refermé le périmètre sans Mac avant de pousser. Ignoré hors plateformes
    // Apple : rien ne change sous Linux.
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "WaveFlow",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "WaveFlowTests",
            dependencies: ["WaveFlow"],
            // Le dossier de tests est lié en entier : les suites qui dépendent
            // d'un framework Apple doivent donc être retirées une par une, sans
            // quoi elles casseraient la compilation du package sous Linux.
            // Celle-ci teste le dépôt SwiftData, absent hors plateformes Apple ;
            // son équivalent vérifiable ici est
            // `InMemoryPlaylistRepositoryTests`, qui couvre le même contrat.
            exclude: [
                "SwiftDataPlaylistRepositoryTests.swift",
                "PlaylistPersistenceTests.swift",
                "LibraryScannerTests.swift",
            ],
            swiftSettings: settings,
        ),
    ],
)
