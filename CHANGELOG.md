# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-08-30

### Added

- **Temperature** and **power** metrics. Sensor keys differ per model, so the SMC
  is enumerated once at start-up and only the keys returning plausible readings
  are kept; power is scaled against the attached adapter's rating.
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

[1.2.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.2.0
[1.1.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.1.0
[1.0.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.0.0
