# Contributing to GlassDeck

Thanks for taking a look. This is a small, focused app: a system monitor that
stays out of the way. Contributions that keep it that way are very welcome.

## Getting set up

```sh
git clone https://github.com/FraCata00/glassdeck.git
cd glassdeck
swift build
swift test
Scripts/bundle.sh --debug && open .build/bundle/GlassDeck.app
```

Requirements: macOS 15+ to run, and the macOS 26 SDK (Xcode 26 or later) to build
the app target, which uses the Liquid Glass APIs. `GlassDeckKit` alone builds
against older SDKs.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/), in English, checked
by CI:

```
feat(touchbar): add a full-width mode with fan speeds
fix(gpu): fall back to the parent registry entry for the device name
docs(readme): document the SMC key set
```

Types in use: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`,
`chore`. Scopes track the source layout — `cpu`, `gpu`, `memory`, `disk`,
`network`, `fans`, `battery`, `touchbar`, `ui`, `settings`, `kit`, `scripts`.

## Pull requests

- Keep `swift test` green; add tests for anything with arithmetic in it.
- New samplers belong in `GlassDeckKit`, with no AppKit or SwiftUI imports.
- Anything that can be absent on some Macs (a fan, a battery, a discrete GPU)
  must report *unavailable* rather than zero, so the UI can hide it.
- Private API use stays confined to `Sources/GlassDeck/TouchBar/DFRSupport.swift`
  and to the battery keys in `Sources/GlassDeckKit/Samplers/BluetoothSampler.swift`
  — there is no public API for a paired device's charge — and must degrade to a
  no-op when a symbol cannot be resolved. The Bluetooth keys are read through
  `responds(to:)` for that reason: `value(forKey:)` on a key that has gone away
  raises an Objective-C exception, which Swift cannot catch.
- Match the surrounding style: comments explain *why*, not *what*.

## Releasing

Maintainers only:

```sh
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

The release workflow builds a universal binary, bundles and signs it ad hoc,
attaches `GlassDeck.zip` plus its SHA-256, and publishes the GitHub release.
