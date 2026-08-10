# WaveFlow for iOS

Native iOS client for [WaveFlow](https://github.com/InstaZDLL/WaveFlow) — a
local-first music player. Swift + SwiftUI + AVFoundation.

> **Status:** early foundation. Plays files you import into the app today; sync
> with the WaveFlow server (playlists, liked, streaming) comes later, once the
> server side is finalised.

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
- **Local store:** none yet; SwiftData when playlists land
- **DI:** manual, two `@State` objects owned by `WaveFlowApp`
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
│  └─ Search.swift          In-memory filtering, prefix matches first
├─ Data/
│  ├─ AppPaths.swift                 Documents + artwork cache locations
│  ├─ MusicRepository.swift          Library abstraction (AsyncThrowingStream)
│  ├─ DocumentsMusicRepository.swift Folder scan + DispatchSource watch
│  ├─ LibraryScanner.swift           AVAsset tag reading, artwork extraction
│  ├─ LibraryStore.swift             App-scoped library, loaded once
│  └─ MusicImporter.swift            Document picker → Documents
├─ Playback/
│  └─ PlaybackController.swift  Queue, AVPlayer, Now Playing, remote commands
└─ UI/
   ├─ RootView.swift          Tabs + mini player + full-screen player
   ├─ Theme.swift             Emerald palette
   ├─ DurationFormat.swift    m:ss / h:mm:ss
   ├─ Labels.swift            Count labels
   ├─ Components/             ArtworkView, SongRow, MediaRow, LibraryStateContainer
   ├─ Library/LibraryScreen.swift   Song list
   ├─ Browse/                 Albums, Artists, their details, shared header
   ├─ Search/SearchScreen.swift     Songs, albums and artists in one list
   └─ Player/
      ├─ ArtworkAccent.swift  Dominant colour from cover
      ├─ MiniPlayer.swift     Bottom accessory of the tab bar
      └─ NowPlayingScreen.swift  Full-screen player
```

One `LibraryStore` at the app level holds the loaded library, and one
`PlaybackController` owns the queue; both are injected through the environment.
Adding a screen means reading those two, never starting a second scan.

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
| ExoPlayer queue | Queue held by `PlaybackController` — `AVQueuePlayer` doesn't expose the traversal order that shuffle, repeat and *previous* need |
| Coil | `AsyncImage` over an on-disk artwork cache, one file per album |
| `Palette` | 1×1 downsample of the cover, saturation boosted and brightness clamped |
| ViewModels + `StateFlow` | `@Observable` classes on the main actor |
| Bottom bar + floating card | `TabView` + `tabViewBottomAccessory` (iOS 26) |

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

Swift Testing, four suites: `GroupingTests`, `DurationFormatTests` and
`SearchTests` (ported from Android), plus `TagNormalizationTests` for the tag
helpers the grouping identifiers are built on. Still missing: a
`LibraryScanner` test over a temporary folder — that one needs AVFoundation, so
it needs a Mac.

CI runs the same command on every push and pull request, resolving the Xcode
version and the simulator at runtime so runner image updates don't break it.

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
- [ ] Scanner test over a temporary folder
- [ ] Local playlists (SwiftData): create, rename, delete, add / remove tracks
- [ ] Drag-to-reorder inside a playlist
- [ ] WaveFlow server sync (playlists, liked, ratings)
- [ ] Streaming from the WaveFlow server (HMAC signed URLs)
- [ ] CarPlay

## License

[GPL-3.0](LICENSE) — same as WaveFlow desktop and Android.
