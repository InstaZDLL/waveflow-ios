# Contributing to WaveFlow for iOS

Thanks for helping on the iOS client. The main
[WaveFlow CONTRIBUTING guide](https://github.com/InstaZDLL/WaveFlow/blob/main/CONTRIBUTING.md)
(commit conventions, PR process, the family's shared expectations) applies here
too — this file only adds the iOS-specific bits.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting set up

Open `WaveFlow.xcodeproj` in Xcode. The app is Swift + SwiftUI + AVFoundation
with **no third-party dependencies** — everything comes from the system
frameworks, so there is nothing to install.

## Before you open a PR

Build and run the tests (or just ⌘U in Xcode):

```bash
xcodebuild test -project WaveFlow.xcodeproj -scheme WaveFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skip-testing:WaveFlowUITests
```

Check UI changes in **both light and dark** appearance — the player tints itself
from the artwork — and verify playback changes with the screen locked and from
Control Center.

## Commit conventions

[Conventional Commits](https://www.conventionalcommits.org/) with **kebab-case**
scopes and a **lowercase** subject, same as the rest of the family. Scopes mirror
the areas in [`.github/labeler.yml`](.github/labeler.yml):

- `feat(ui): drag-to-reorder in the queue`
- `fix(playback): keep the album context when tapping a track`
- `refactor(data): fold artwork extraction into the scanner`

## Staying coherent with the other clients

The desktop, Android, and iOS clients are meant to stay coherent. When you add a
user-facing behavior, check whether desktop or Android already does it and match
that behavior rather than inventing a new one.

## Reporting bugs and security issues

- Bugs and feature requests: use the [issue templates](.github/ISSUE_TEMPLATE/).
- Security vulnerabilities: **do not** open a public issue — follow
  [SECURITY.md](.github/SECURITY.md).

## License

WaveFlow for iOS is **GPL-3.0-only**. By submitting a pull request you agree that
your contribution is licensed under those terms.
