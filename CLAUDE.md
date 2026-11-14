# GlassDeck

A macOS menu bar system monitor (CPU, GPU, memory, disk, network, fans, battery,
temperature, power) drawn in Liquid Glass, with a Touch Bar presence. No Dock
icon, no network access, no root, no helper. Swift 6 strict concurrency, SwiftPM
only (no Xcode project), no third-party dependencies.

## Commands

```sh
swift build                       # everything; the app target needs the macOS 26 SDK
swift build --target GlassDeckKit # the kit alone must also build on the macOS 15 SDK
swift test                        # Swift Testing; one test: swift test --filter "<name>"
Scripts/build-log.sh build        # same as `swift build`, diagnostics only
Scripts/bundle.sh --debug && open .build/bundle/GlassDeck.app
cd web && npm run dev             # the landing page (Vue 3 + Vuetify + Vite)
```

A change is not done until `swift build` and `swift test` are both clean.

## Layout

- `Sources/GlassDeckKit/` — the library: samplers, model, formatting, Touch Bar
  layout arithmetic. **No AppKit or SwiftUI imports**, no macOS 26 API. This is
  the only target with tests, so anything with arithmetic in it belongs here.
  - `Samplers/` — one class per source (Mach, IOKit, SMC, libproc). Not thread
    safe; all of them live inside the `MetricsEngine` actor.
  - `SystemMonitor.swift` — the `@MainActor @Observable` façade: the sampling
    loop, the history ring buffers, `snapshot` (every sample) and
    `coarseSnapshot` (at most every 2 s).
  - `Model/` — `MetricsSnapshot` and the `*Usage` value types;
    `MetricsSnapshot+Presentation.swift` holds every user-visible string.
- `Sources/GlassDeck/` — the app.
  - `System/` — `AppModel` (the singleton wiring everything), `Preferences`
    (`UserDefaults`), `ObservationLoop`, `StatusItemReadout`, alerts, hot key.
  - `UI/` — SwiftUI: `GlassPanelView` (menu bar panel), `DashboardView`
    (window), `SettingsView`, and `Theme` for every colour and radius.
  - `TouchBar/` — AppKit views drawn by hand in `draw(_:)`, plus
    `DFRSupport.swift` for the private Touch Bar hooks.
- `Tests/GlassDeckKitTests/` — kit tests only; the app target has none.
- `Resources/` — `Info.plist` template, icon, the app's string tables.
- `web/` — the GitHub Pages site. Unrelated to the Swift build.

## The rule that outranks the others: cost

This is a system monitor; it must not show up in its own process list. Profiling
shows the time goes into drawing (the status item first, then the Touch Bar),
not into sampling, which is about a tenth of it. Profile with `sample <pid> 20`
before and after touching any of this, and keep these invariants:

- **Nothing reads `monitor.snapshot` unless it is on screen.** `@Observable`
  invalidates per property, and a snapshot is new on every sample by its
  timestamp alone. Windows go through `LiveReadings` / `.tracksVisibility`
  (`UI/VisibilityGate.swift`) — `onDisappear` does not fire for a window that is
  only ordered out.
- **The status item never reads a snapshot.** It reads `StatusItemReadout`,
  which republishes only when the label would look different. One redraw of the
  status item costs tens of milliseconds.
- **Slow surfaces read `coarseSnapshot`**, never `snapshot` (alerts, the
  collapsed Touch Bar).
- **SMC reads are cached** (thermal 5 s, fans 3 s, power 2 s): each key is a
  kernel round trip. Do not add a per-tick SMC read.
- **Work that is only needed while visible is reference-counted**:
  `beginSamplingProcesses()`/`endSamplingProcesses()`, `ClockTicker` holds.
- **The loop runs at `.utility` with timer tolerance** and parks on display
  sleep. Do not raise its priority or add a second timer; no `TimelineView`,
  no `repeatForever`, no display-link animation anywhere.
- **Bluetooth is not queried until its module is switched on** — the first
  query is what raises the system permission prompt.

## Conventions

- **Comments explain why, not what**, in full sentences, British spelling
  (`colour`, `utilisation`, `synchronise`). Match the surrounding voice; a
  non-obvious decision gets its reason and, where there is one, the measurement.
- **Absent hardware is `unavailable`, never zero** (a fan, a battery, a discrete
  GPU), so the UI can hide the metric via `snapshot.supports(_:)`.
- **Private API stays where it is**: `TouchBar/DFRSupport.swift`, and the
  battery KVC keys in `Samplers/BluetoothSampler.swift` (always behind
  `responds(to:)`). Everything must degrade to a no-op if a symbol is missing.
- **macOS 26 API goes behind `#available(macOS 26.0, *)`** with a fallback that
  keeps the layout — use the helpers in `UI/GlassSurface.swift`
  (`glassSurface`, `glassButton`, `glassMorph`, `GlassStack`) rather than
  calling `glassEffect` directly.
- **Two string tables, English and Italian, both must be updated together.**
  App strings: `String(localized:)` → `Resources/Localizations/{en,it}.lproj`.
  Kit strings: `L.t("key", "fallback")` →
  `Sources/GlassDeckKit/Resources/{en,it}.lproj`. CI asserts all four tables
  reach the bundle.
- **Settings**: a new one needs a `Key`, a `didSet` that stores it, a default in
  `Preferences.init`, and — if anything outside SwiftUI reacts to it — a line in
  `AppModel.preferenceChanges`. Quitting must never write preferences.
- Formatting follows `.editorconfig`: 4 spaces, LF, final newline.

## Running it by hand

The Touch Bar and a menu bar extra cannot be scripted, so a build can be brought
up in a given state with environment variables (see
`AppModel.applyDevelopmentOverrides`): `GLASSDECK_OPEN_DASHBOARD=1`,
`GLASSDECK_OPEN_PANEL=1`, `GLASSDECK_OPEN_SETTINGS=1`,
`GLASSDECK_TOUCHBAR_MODE=fullscreen|expanded|mini|detail:<metric>`.

A released build is usually already running on this machine. A second instance
presents its own system-modal Touch Bar on top of it, so ask before launching
one, and stop it with SIGTERM (handled: it takes the bar down) rather than
SIGKILL, which leaves the Touch Bar stuck on a dead bar.

## Git

- Conventional Commits in English, enforced by commitlint on pull requests,
  header ≤ 100 characters, lower-case subject. Scopes are a closed list in
  `.commitlintrc.json` (`cpu`, `gpu`, `memory`, `disk`, `network`, `fans`,
  `battery`, `processes`, `bluetooth`, `clock`, `touchbar`, `menubar`, `ui`,
  `dashboard`, `settings`, `kit`, `scripts`, `ci`, `deps`, `readme`, `release`,
  `web`) — an unlisted scope fails CI.
- Work on a branch (`feat/…`, `fix/…`, `ci/…`) and merge through a pull request;
  `main` is what the Pages site and the release tags are cut from.
- `CHANGELOG.md` (Keep a Changelog) is written at release time in a
  `docs(release): cut the changelog for X.Y.Z` commit, in prose that says what
  changed for the user and why. A release is a `vX.Y.Z` tag; the workflow builds,
  signs ad hoc and publishes, then `Scripts/update-cask.sh X.Y.Z` moves the
  Homebrew cask.
