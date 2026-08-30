# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.0.0
