# WaveFlow for iOS

Native iOS client for [WaveFlow](https://github.com/InstaZDLL/WaveFlow) — a
local-first music player. Swift + SwiftUI + AVFoundation.

> **Status:** usable offline. Plays, browses and organises the files you import
> into the app — library, albums, artists, search and local playlists. Sync with
> the WaveFlow server (liked, ratings, streaming) comes later, once the server
> side is finalised.

## Where the music comes from

iOS has no `MediaStore`. There is no API to enumerate "the music on the phone",
and the Apple Music library (`MPMediaLibrary`) is mostly DRM-protected — those
tracks can only be played through the system player, with no real control over
playback.

So WaveFlow reads its own `Documents` folder instead, the way VLC and Doppler
do. You fill it either from inside the app (**+**, which opens the document
picker) or from the Files app under **On My iPhone → WaveFlow**. It's also
where downloads will land once server sync arrives.

## Stack

- **Language:** Swift 6.2, with `MainActor` isolation by default
  (`SWIFT_DEFAULT_ACTOR_ISOLATION`) — UI code is implicitly on the main actor,
  and the file scanner is explicitly `nonisolated`
- **UI:** SwiftUI (WaveFlow emerald accent), `@Observable` for state
- **Audio:** `AVPlayer` + `AVAudioSession` + `MPNowPlayingInfoCenter` /
  `MPRemoteCommandCenter` — background playback and lock-screen controls
- **Library source:** the app's `Documents` folder, tags read via `AVURLAsset`
- **Local store:** SwiftData, playlists only — the library itself is derived
  from the folder on every scan, never persisted
- **DI:** manual, three `@State` objects owned by `WaveFlowApp`
- **Minimum:** iOS 26

## Project layout

```
WaveFlow/
├─ WaveFlowApp.swift        Entry point + manual DI container
├─ Info.plist               Background audio, file sharing
├─ Model/
│  ├─ Song.swift            Domain model, source-agnostic
│  ├─ Album.swift / Artist.swift  Derived from the song list
│  ├─ Library.swift         Loaded library; derived views computed once
│  ├─ Grouping.swift        [Song] → albums / artists
│  ├─ Search.swift          In-memory filtering, prefix matches first
│  ├─ Playlist.swift        Local playlist, order held by the array itself
│  └─ PlaybackQueue.swift   Traversal order, shuffle, repeat — no AVFoundation
├─ Data/
│  ├─ AppPaths.swift                 Documents + artwork cache locations
│  ├─ MusicRepository.swift          Library abstraction (AsyncThrowingStream)
│  ├─ DocumentsMusicRepository.swift Folder scan + DispatchSource watch
│  ├─ LibraryScanner.swift           AVAsset tag reading, artwork extraction
│  ├─ LibraryStore.swift             App-scoped library, loaded once
│  ├─ MusicImporter.swift            Document picker → Documents
│  ├─ PlaylistRepository.swift       Playlist abstraction (AsyncThrowingStream)
│  ├─ InMemoryPlaylistRepository.swift  No-persistence implementation
│  ├─ SwiftDataPlaylistRepository.swift Persisted implementation, one model actor
│  ├─ PlaylistEntity.swift           The SwiftData model, kept out of the domain
│  ├─ PlaylistPersistence.swift      Opening the store, degrading in three tiers
│  └─ PlaylistStore.swift            App-scoped playlists, writes serialised
├─ Playback/
│  └─ PlaybackController.swift  AVPlayer, Now Playing, remote commands
└─ UI/
   ├─ RootView.swift          Tabs + mini player + full-screen player
   ├─ Theme.swift             Emerald palette
   ├─ DurationFormat.swift    m:ss / h:mm:ss
   ├─ Labels.swift            Count labels
   ├─ Components/             ArtworkView, SongRow, MediaRow, LibraryStateContainer
   ├─ Library/LibraryScreen.swift   Song list
   ├─ Browse/                 Albums, Artists, their details, shared header
   ├─ Search/SearchScreen.swift     Songs, albums and artists in one list
   ├─ Playlists/              List, detail, rename dialog, add-to sheet and menu
   └─ Player/
      ├─ ArtworkAccent.swift  Dominant colour from cover
      ├─ MiniPlayer.swift     Bottom accessory of the tab bar
      └─ NowPlayingScreen.swift  Full-screen player
```

One `LibraryStore` at the app level holds the loaded library, one
`PlaybackController` owns the queue, and one `PlaylistStore` observes the
persisted playlists; all three are injected through the environment. Adding a
screen means reading them, never starting a second scan or a second stream.

The `WaveFlow/` folder is a *file system synchronized group*: any `.swift` file
dropped in it is picked up by Xcode automatically, with no project file edit.
`Info.plist` is the one membership exception — see `.coderabbit.yaml` for why.

## Notes on the port

Coming from [waveflow-android](https://github.com/InstaZDLL/waveflow-android),
the pieces that needed a real translation rather than a line-by-line port:

| Android | iOS |
|---|---|
| `MediaStore` query | `Documents` scan + `AVURLAsset` metadata |
| `ContentObserver` | `DispatchSource` on the folder, 600 ms debounce |
| Media3 `MediaSessionService` | `UIBackgroundModes: audio` + Now Playing fed by hand |
| ExoPlayer queue | `PlaybackQueue`, a plain value type — `AVQueuePlayer` doesn't expose the traversal order that shuffle, repeat and *previous* need |
| Coil | `AsyncImage` over an on-disk artwork cache, one file per album |
| `Palette` | 1×1 downsample of the cover, saturation boosted and brightness clamped |
| ViewModels + `StateFlow` | `@Observable` classes on the main actor |
| Bottom bar + floating card | `TabView` + `tabViewBottomAccessory` (iOS 26) |
| Room `position` column | The array's own order; positions can't collide or go sparse |
| Permanent drag handle per row | Edit mode — iOS won't reorder a list outside it |

Real-world tags are the main source of bugs here. Most `.m4a` rips carry no
`albumArtist` (`aART`) tag and put every guest in `artist`, so an EP with two
featurings splits into three albums unless the primary artist is derived — see
`String.primaryArtist`.

## Build

Open `WaveFlow.xcodeproj` in **Xcode 26** and run, or from the command line:

```bash
xcodebuild -project WaveFlow.xcodeproj -scheme WaveFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

No signing team is needed for the simulator.

## Tests

```bash
xcodebuild test -project WaveFlow.xcodeproj -scheme WaveFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skip-testing:WaveFlowUITests
```

Swift Testing, eleven suites. Eight run anywhere: `GroupingTests`,
`DurationFormatTests`, `SearchTests` and `PlaylistTests` (ported from Android),
plus `TagNormalizationTests` for the tag helpers the grouping identifiers are
built on, `PlaybackQueueTests` for the traversal order — that one has no Android
counterpart, where the queue belongs to ExoPlayer — `InMemoryPlaylistRepositoryTests`
for the playlist store contract, and `PlaylistStoreTests` for the layer above it:
write ordering, and failures confined to a message instead of a crash.

Three need a Mac: `SwiftDataPlaylistRepositoryTests`, `PlaylistPersistenceTests`
— the store must open, or degrade, but never keep the app from starting — and
`LibraryScannerTests`.

That last one builds its own audio: silence encoded to AAC, then remuxed with its
tags by a passthrough export. A committed `.m4a` fixture would be an opaque blob,
and the very tags under test wouldn't appear anywhere in the source.

CI runs the same command, resolving the Xcode version and the simulator at
runtime so runner image updates don't break it. It only runs when something that
can affect the build changed — sources, tests, the Xcode project, or the
workflow itself. A docs-only or config-only pull request skips the macOS job,
which bills at 10× the Linux rate; the same gate applies to CodeQL's Swift
analysis, the slowest job of the lot.

### Without a Mac

Everything that only depends on Foundation — all of `Model/`, plus `AppPaths`,
`MusicRepository`, `DurationFormat` and `Labels` — builds and runs on Linux with
a plain Swift toolchain. `Tools/LinuxHarness` is a SwiftPM package whose sources
are relative symlinks into the repo, so the whole test suite runs there:

```bash
cd Tools/LinuxHarness && swift test
```

It never builds the app, and Xcode ignores it — `Tools/` sits outside the
synchronized `WaveFlow/` group. SwiftUI, AVFoundation, MediaPlayer, UIKit and
CryptoKit are absent on Linux; anything touching those is left to CI.

## Roadmap

- [x] Local file playback (`Documents` + `AVPlayer`)
- [x] Import from the Files app / document picker
- [x] Full-screen player (seek, shuffle, repeat, artwork-tinted background)
- [x] Album / artist browsing
- [x] Background playback + lock-screen controls
- [x] Tests for grouping, duration formatting and tag normalisation
- [x] Search across songs, albums and artists
- [x] Scanner test over a temporary folder
- [x] Local playlists: SwiftData store, screens, add from anywhere
- [x] Drag-to-reorder inside a playlist
- [ ] WaveFlow server sync (playlists, liked, ratings)
- [ ] Streaming from the WaveFlow server (HMAC signed URLs)
- [ ] CarPlay

## License

[GPL-3.0](LICENSE) — same as WaveFlow desktop and Android.
