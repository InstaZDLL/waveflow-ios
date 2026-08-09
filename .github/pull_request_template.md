<!--
Thanks for the PR! A few quick reminders so review goes fast:

1. PR title follows Conventional Commits with a kebab-case scope:
     feat(player): gapless playback
     fix(scanner): skip files with no audio track
     perf(artwork): cache covers per album instead of per song
   Scopes mirror the auto-labeler rules in .github/labeler.yml.

2. Before opening, run locally (or just ⌘U in Xcode):
     xcodebuild test -project WaveFlow.xcodeproj -scheme WaveFlow \
       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
       -skip-testing:WaveFlowUITests

3. If you touched a cross-cutting pattern, update the README so future
   readers (humans and Claude) stay in sync with the codebase.
-->

## Summary

<!-- 1-3 bullets describing what changes and why. Focus on the why. -->

-
-

## How I tested

<!-- Concrete steps a reviewer could repeat. Skip "it builds" — that's CI's job.
     For anything touching playback or scanning, say which files you tested
     with: tags vary wildly in the wild, and most bugs here come from a
     missing or malformed tag rather than from the code path itself. -->

-
-

## Screenshots / clips

<!-- For UI changes. Drag-and-drop directly into the PR description on the web UI.
     Light and dark, please — the player tints itself from the artwork. -->

## Checklist

- [ ] Title uses Conventional Commits (`type(scope): subject`, kebab-case scope)
- [ ] Builds and tests pass locally
- [ ] UI changes checked in light *and* dark appearance
- [ ] Playback changes checked with the screen locked / from Control Center
- [ ] Breaking change? Called out in the summary above

## Linked issues

<!-- Use "Closes #123" / "Refs #456" so GitHub auto-closes on merge. -->

Closes #
