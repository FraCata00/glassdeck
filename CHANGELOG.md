# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-08-30

### Fixed

- Network throughput no longer spikes to nonsense every few gigabytes. The
  kernel's byte counters are 32-bit and wrap every 4 GiB — minutes of Wi-Fi —
  and the deltas were taken across a widened sum, so each wrap read as exabytes
  per second and pinned the gauge. At the 0.5 s cadence the resulting number no
  longer fitted the formatter and brought the app down outright.
- Disk throughput no longer does the same when an external disk is unmounted,
  which shrinks the set of drivers its counters are summed over.
- VPN traffic is no longer counted twice: `utun` and `ipsec` carry bytes that are
  already counted on the interface underneath them.
- The menu bar panel no longer draws its gauges past its own edge. They wrap onto
  as many rows as they need — nine metrics read as 3 · 3 · 3 — where before four
  gauges already asked for more width than the panel has, and the shipped default
  of every metric asked for nearly twice it.
- On a Mac with more than one GPU, the reported accelerator no longer flickers
  between the integrated and the discrete one from one sample to the next.
  GlassDeck follows a device and hands the reading over only when another is
  clearly busier.
- Text the Italian localisation had missed: "n/a" and the fan maximum in the
  metric details, every Touch Bar control's VoiceOver label, and the Settings
  window title.
- The process list no longer empties when the menu bar panel is closed while the
  dashboard is still open.
- The Settings window shows the sampling cadence as `1.5s` rather than `1.50s`,
  and its "Open at login" switch re-reads the system's answer instead of showing
  whatever was true when the window first opened.
- A release can no longer be built without GlassDeckKit's localisations: the
  bundle script fails instead of skipping them in silence, and CI checks that all
  four string tables are inside the built app.

### Changed

- Memory used is now app memory plus wired plus compressed — the three terms
  Activity Monitor adds up — rather than counting active pages, which include
  file-backed pages the system can evict on demand.
- GlassDeck reaches the menu bar sooner. Building the SMC sensor catalogue costs
  about 50 ms and ran on the main thread before anything could be drawn; it now
  happens on the sampling actor, with the first sample paying for it.
- **GlassDeckKit API**: `SystemMonitor.samplesProcesses` is now read-only. Views
  register their interest with `beginSamplingProcesses()` and
  `endSamplingProcesses()` instead, so that two open windows cannot switch the
  scan off under one another. `MemoryUsage` gains `appMemory`, and
  `ValueFormatter` gains `seconds(_:)`.

## [1.2.0] - 2026-08-30

### Added

- **Temperature** and **power** metrics. Sensor keys differ per model, so the SMC
  is enumerated once and only the keys returning plausible readings are kept;
  power is scaled against the attached adapter's rating.
- **Expandable Touch Bar panels**: tapping a panel — or the battery chip — opens
  that metric across the bar with the numbers behind its headline and its history.
- **Italian localisation**, following the system language.
- A default app Touch Bar, so opening a GlassDeck window no longer leaves the
  Touch Bar black while the bar is released.

### Changed

- The battery chip shows the charge only; the power draw moved to the battery's
  expanded bar, where it does not crowd the number people glance at.
- Touch Bar panel and button widths are measured against the space the system
  actually grants, instead of being estimated.

## [1.1.0] - 2026-08-30

### Added

- A **mini** Touch Bar size showing just the meters, so shrinking never makes
  GlassDeck disappear: the ⌄ button now steps down through full width, compact
  and mini, and only a tap on the mini bar hands the Touch Bar back.
- **Position** setting for the compact and mini bars: left, centre, or beside the
  system Control Strip (the new default).

### Fixed

- Quitting GlassDeck no longer writes `Touch Bar disabled` into the settings,
  which used to leave the integration switched off for every later launch.
- Collapsing from the Touch Bar no longer rewrites the placement preference; a
  tap is a session action, not a settings change.
- GlassDeck now releases the Touch Bar when it is sent `SIGINT`, `SIGTERM` or
  `SIGHUP`. Being killed while a bar was presented used to leave the system Touch
  Bar stuck on a dead bar until its server was restarted.
- Compact-bar items are sized to the space the system actually grants beside the
  Control Strip, so the trailing button is no longer clipped.

## [1.0.0] - 2026-08-30

### Added

- Menu bar app with a live status item and a Liquid Glass panel showing CPU, GPU,
  memory, disk, network, fans and battery.
- Dashboard window with a blurred, load-reactive backdrop, a hero gauge, the
  per-core grid split into performance and efficiency clusters, metric cards and
  the top CPU consumers.
- Touch Bar integration in three states: a Control Strip meter, an expanded bar
  that leaves the Control Strip visible, and a full-width bar that adds fan RPM.
- Fan speeds read from the SMC, read-only, with each fan's rated range.
- Battery chip with charge level, charging state and time estimates.
- Settings for the sampling interval, metric selection per surface, Touch Bar
  placement, the status item style and opening at login.
- `Scripts/bundle.sh` to assemble a signed `.app`, and `Scripts/make-icon.swift`
  to generate the icon artwork from code.

[1.3.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.3.0
[1.2.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.2.0
[1.1.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.1.0
[1.0.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.0.0
