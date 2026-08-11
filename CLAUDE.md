# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Contexte machine

Le dépôt se développe en semaine depuis **Linux**, sans Mac : pas d'`xcodebuild`, pas de SDK iOS.
Une toolchain Swift complète est en revanche installée (swiftly, **Swift 6.3.3**), et elle couvre
une part réelle du code.

**Vérifiable localement** — tout ce qui ne dépend que de Foundation :

| Module | Linux |
|---|---|
| `Foundation`, `Observation`, `Testing`, `XCTest` | disponible |
| `SwiftUI`, `AVFoundation`, `MediaPlayer`, `UIKit`, `CryptoKit`, `UniformTypeIdentifiers` | absent |

Concrètement : tout `WaveFlow/Model/`, plus `AppPaths`, `MusicRepository`, `PlaylistRepository`,
`InMemoryPlaylistRepository`, `DurationFormat` et `Labels`, se typecheckent et **s'exécutent** ici. C'est exactement le périmètre des deux premiers
tests prioritaires du README (`Grouping`, `DurationFormat`) — ils peuvent être écrits et vérifiés
sans Mac.

Restent hors de portée : `LibraryScanner` (AVFoundation + CryptoKit), `PlaybackController` — mais
plus la file de lecture, extraite dans `Model/PlaybackQueue.swift` justement pour être vérifiable
ici —, tout `UI/` sauf
les deux helpers ci-dessus, `MusicImporter` (`startAccessingSecurityScopedResource` n'existe pas
dans swift-corelibs-foundation), et `LibraryStore` (`@Observable` exige un `import Observation`
explicite hors iOS, où SwiftUI le réexporte). Pour ces fichiers : relire attentivement, ne jamais
affirmer qu'un build a été vérifié, et laisser trancher la CI macOS.

### Typecheck local

```bash
swiftc -typecheck -swift-version 5 -default-isolation MainActor \
  WaveFlow/Model/*.swift WaveFlow/Data/AppPaths.swift \
  WaveFlow/Data/MusicRepository.swift WaveFlow/Data/PlaylistRepository.swift \
  WaveFlow/Data/InMemoryPlaylistRepository.swift \
  WaveFlow/UI/DurationFormat.swift WaveFlow/UI/Labels.swift
```

Les deux drapeaux reproduisent les réglages du projet Xcode (`SWIFT_VERSION = 5.0`,
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) : sans eux, les diagnostics d'isolation divergent de
ceux de la vraie compilation.

### Exécuter les tests sans Mac

```bash
cd Tools/LinuxHarness && swift test
```

`Tools/LinuxHarness/` est un package SwiftPM dont les sources sont des **liens symboliques relatifs**
vers le dépôt — rien n'est dupliqué. Le target s'appelle `WaveFlow`, donc le `@testable import
WaveFlow` des tests est le même sous Xcode et ici, et `Tests/WaveFlowTests` pointe sur le dossier de
tests du projet : un test ajouté est pris automatiquement des deux côtés.

Ce package ne construit **jamais** l'application, et Xcode l'ignore (`Tools/` est hors du groupe
synchronisé `WaveFlow/`). Pour faire entrer un fichier de plus dans le périmètre, ajouter un lien :

```bash
ln -s ../../../../WaveFlow/Model/Playlist.swift Tools/LinuxHarness/Sources/WaveFlow/
```

Un test qui dépendrait d'un framework Apple casserait ce package : l'exclure du target et le laisser
à la CI macOS.

## Commandes Xcode (macOS uniquement)

```bash
# Build simulateur (aucune équipe de signature nécessaire)
xcodebuild -project WaveFlow.xcodeproj -scheme WaveFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Tests unitaires — les tests UI sont volontairement exclus (lents, redondants)
xcodebuild test -project WaveFlow.xcodeproj -scheme WaveFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skip-testing:WaveFlowUITests

# Un seul test / une seule suite (Swift Testing)
xcodebuild test -project WaveFlow.xcodeproj -scheme WaveFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WaveFlowTests/NomDeLaSuite/nomDuTest
```

La CI résout la version d'Xcode et l'UDID du simulateur à l'exécution : ne jamais y coder en dur un
nom de simulateur ni un chemin `/Applications/Xcode*.app`.

Pas de linter local (SwiftLint tourne côté CodeRabbit, pas dans le dépôt), pas de gestionnaire de
paquets — zéro dépendance externe.

## Architecture

Portage d'[waveflow-android](https://github.com/InstaZDLL/waveflow-android). Beaucoup de commentaires
du code expliquent *pourquoi* une pièce Android a été traduite ainsi ; les lire avant de refactorer.

**Flux de données** — une seule direction, un seul scan :

```
Documents/ ──DispatchSource(600 ms debounce)──▶ DocumentsMusicRepository
                                                     │ AsyncThrowingStream<[Song]>
                                                     ▼
                                              LibraryStore (@MainActor, app-scoped)
                                                     │ Library (struct immuable)
                                                     ▼
                                    RootView ──environment──▶ écrans SwiftUI
                                                     │
                                              PlaybackController (@MainActor)
```

- **DI manuelle** : `WaveFlowApp` détient les deux seuls objets long-vivants (`LibraryStore`,
  `PlaybackController`) et les injecte via `.environment(...)`. Un nouvel écran **lit** ces deux-là ;
  il ne crée jamais son propre flux — ce serait un second scan complet du dossier.
- **`Library` est immuable et recalculée à chaque émission** : `albums`, `artists`, `songsByID` sont
  dérivés dans `init` (pas de `lazy` : une `struct` `Sendable` n'a pas de mémoïsation sûre). Toute
  propriété dérivée coûteuse doit donc être calculée là, pas dans une propriété calculée lue à chaque
  tic du lecteur.
- **`MusicRepository` reste storage-agnostique** : la sync serveur WaveFlow arrivera comme une
  seconde implémentation. Rien de spécifique au dossier `Documents` ne doit fuiter hors de
  `DocumentsMusicRepository` / `LibraryScanner`.
- **`WaveFlow/Model/` est du domaine pur** : ni AVFoundation, ni système de fichiers, ni réseau.

**Concurrence** — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` avec
`SWIFT_APPROACHABLE_CONCURRENCY` (langage mode 5, chaîne Swift 6.2) : tout est implicitement sur le
main actor sauf mention contraire. D'où le `nonisolated` explicite un peu partout sur le modèle, le
scanner et le repository — c'est ce qui les autorise à traverser les frontières d'acteur. Ne retire
jamais ce réglage du `.pbxproj`, tout le code en dépend.

**Points sensibles du domaine**, chacun protégé par un choix délibéré :

- *Identifiants dérivés* — iOS ne fournit aucun ID média (pas de `MediaStore`). `Song.id` est le
  chemin relatif à `Documents` (pas l'URL absolue : le conteneur change d'UUID à chaque
  réinstallation) ; `albumId`/`artistId` viennent des tags normalisés (`groupingKey`, insensible à la
  casse et aux accents). Ces clés servent aussi de nom de fichier au cache de pochettes — les changer
  invalide le cache et casse la navigation.
- *Tags du monde réel* — la plupart des `.m4a` n'ont pas d'`albumArtist` (`aART`) et entassent les
  invités dans `artist`. `String.primaryArtist` découpe le crédit (virgule, `feat.`, `ft.`… mais ni
  `&` ni `/` : Simon & Garfunkel, AC/DC) pour éviter qu'un EP avec deux featurings n'éclate en trois
  albums. Tout tag manquant doit avoir un repli explicite ; un fichier illisible est ignoré, jamais
  remonté en erreur pour toute la bibliothèque.
- *Scan borné* — `LibraryScanner` maintient une fenêtre de 6 `AVURLAsset` ouverts au plus (les
  descripteurs de fichiers sont finis). `DocumentsMusicRepository` sérialise les scans sous `NSLock`
  et rejoue un scan différé plutôt que d'en lancer deux en parallèle (résultats dans le désordre).
- *File de lecture tenue à la main* — `PlaybackQueue` garde les morceaux + un tableau `order` (ordre
  de traversée, permuté en aléatoire) plutôt qu'un `AVQueuePlayer`, qui n'expose pas l'ordre dont
  aléatoire / répétition / « précédent » ont besoin. C'est une `struct` du domaine, sans
  AVFoundation : elle ne joue rien, elle rend un `PlaybackStep` que `PlaybackController` traduit en
  commandes — c'est ce qui la rend testable sans simulateur. Le tirage aléatoire du morceau de
  départ reste chez l'appelant (`playShuffled`) pour que la file demeure déterministe.
  Pas de `MediaSessionService` ici :
  `UIBackgroundModes: audio` maintient l'app en vie et `MPNowPlayingInfoCenter` /
  `MPRemoteCommandCenter` sont alimentés à la main — ils doivent rester cohérents avec l'état réel du
  lecteur après chaque commande.
- *Identité des vues SwiftUI* — les `NavigationPath` des onglets vivent dans `RootView`, pas dans les
  écrans : poser `tabViewBottomAccessory` au premier morceau lancé change l'identité du `TabView` et
  jetterait l'état des vues filles. Même raison pour la sélection d'onglet ancrée dans `@State`.

## Projet Xcode

`WaveFlow/` est un **file system synchronized group** : tout `.swift` déposé dedans est pris en
compte sans toucher au `.pbxproj`. Seule exception d'appartenance : `Info.plist` — sans elle, le
groupe le recopie comme ressource et le build échoue sur un conflit de commandes.

Cible de déploiement iOS 26.5 ; le code utilise des API iOS 26 (`tabViewBottomAccessory`,
`tabBarMinimizeBehavior`). Ne pas dupliquer dans `Info.plist` une clé déjà posée par un
`INFOPLIST_KEY_*` du projet.

## Conventions

- **Tout est en français** : commentaires, doc-comments, chaînes d'interface (tutoiement côté UI :
  « Importe des fichiers… »), messages de commit. Les identifiants restent en anglais, **noms de
  tests compris** — Kotlin autorise des phrases entre backticks, Swift non, et les noms portés
  d'Android sont donc retraduits plutôt que translittérés.
- Les commentaires expliquent le *pourquoi* — souvent la contrainte iOS ou la divergence avec
  Android. Garder cette densité plutôt que de commenter le *quoi*.
- **Couleurs** : couleurs sémantiques d'iOS (`.primary`, `.secondary`…) ou palette de `Theme.swift`.
  Jamais de valeur codée en dur dans une vue.
- Commits conventionnels (`feat:`, `chore:`, `fix:`), branche par défaut `main`, PR obligatoire
  (CodeRabbit review en français, `request_changes_workflow` actif).
- Actions GitHub épinglées par SHA, permissions minimales.

## Tests

Swift Testing (`@Test` / `#expect`), dans `WaveFlowTests/`. Sept suites, toutes exécutables depuis
Linux : `GroupingTests`, `DurationFormatTests`, `SearchTests`, `PlaylistTests`,
`TagNormalizationTests` (les helpers de `Song.swift` sur lesquels reposent les identifiants de
regroupement), `PlaybackQueueTests` (ordre de traversée, aléatoire, répétition) et
`InMemoryPlaylistRepositoryTests` (le contrat du dépôt de playlists).

Reste à écrire : un test de `LibraryScanner` sur une arborescence temporaire — il exige un Mac
(AVFoundation) et des fichiers audio de fixture. Un test ne doit dépendre ni d'un vrai fichier audio
du système, ni du dossier `Documents` réel, ni de l'ordre d'exécution.
