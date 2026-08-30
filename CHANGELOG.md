# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-08-31

### Added

- **Reorderable metrics.** The order was whichever one they happened to be
  declared in, and nothing could change it. Drag them in Settings → Metrics and
  the panel's gauges, the Touch Bar's panels and the status item's bars all
  follow the one list. A metric added in a later version appends itself rather
  than resetting the order.
- **A warning when the Mac runs hot.** Set a threshold and GlassDeck posts a
  notification once the hottest sensor passes it. Off by default, permission is
  asked for only when it is switched on, and the alert re-arms only after the
  temperature has fallen five degrees, so a reading sitting on the line notifies
  once instead of repeatedly. The setting appears only on a Mac with sensors.

### Changed

- **The throughput gauges scale against the machine rather than a constant.**
  Network used a fixed 100 Mbit ceiling, so on anything faster any real download
  pinned the meter to full and it said nothing for the rest of the transfer. The
  full scale is now the fastest rate seen recently, faded a little each sample so
  one burst does not flatten the gauge, with a floor so background chatter cannot
  read as a busy network.
- **The disk graph follows the disk working.** It drew capacity where network
  drew throughput, so its sparkline was a flat line at however full the volume is
  while the disk was plainly busy. The graph, the ring and the value now follow
  the busier of read and write. Capacity has not gone: it stays in the caption as
  "x free of y", and used, free, read and write remain in the details.
- **The panel scrolls** rather than losing its own bottom. With every metric
  enabled and the process list on it runs past 800 pt, and it used to be exactly
  as tall as its content, so on a short screen the footer was simply cut off.
- **GlassDeckKit API**: `NetworkThroughput` and `DiskUsage` gain
  `referenceBytesPerSecond`, `busiestBytesPerSecond`, `loadFraction` and a
  `minimumReference`. Nothing was removed or renamed.

### Fixed

- Turning off the selected metric no longer leaves the panel's detail card, or
  the dashboard's hero gauge, describing a gauge that is no longer on screen —
  and a first run with CPU disabled no longer opens on CPU regardless.
- The menu bar metric picker offered all nine kinds whatever the hardware, so
  "Fans" could be chosen on a fanless Mac and pin the status item to n/a for
  good. It offers what the machine reports, and an older stored choice falls back.
- VoiceOver reads the Touch Bar's content. The panels, the strip meter, the
  battery chip and the expanded bar were drawn rather than composed of controls,
  so they had no accessibility at all — only GlassDeck's buttons did.
- Touch Bar panel text is measured against the room it has instead of guessed
  from the panel's width, so "TEMPERATURE" is no longer clipped to "TEMPERATU"
  at widths where "TMP" fits.

## [1.4.1] - 2026-08-30

### Fixed

- The full-width Touch Bar fills the bar. Metric panels were pinned at 108 pt, so
  the leftover width simply sat black and turning a metric off widened the gap
  rather than the panels that remained — five metrics left a fifth of the bar
  empty, four left a third, two left over half. Panels are now sized from the
  room the bar actually has, so it is always full and enabling or disabling a
  metric resizes the rest: five come out at 148 pt where they were 108. Full
  width can also show all seven panels now, because the limit is a floor on how
  narrow a panel may get rather than a count derived from a fixed width.
- The bar beside the Control Strip is deliberately unchanged, since there the
  leftover width is what the **Position** setting slides the bar around in.
- The menu bar panel's gauges fill it too. Their size came from a ladder of three
  fixed values, so enabling or disabling a metric usually left the gauges exactly
  as they were and only changed how much empty panel sat beside them: five
  metrics used 70% of the width, and so did nine. The split is now chosen for how
  little it wastes — nine metrics read as three rows of three at 103 pt, filling
  every row.

## [1.4.0] - 2026-08-30

### Changed

- GlassDeck is markedly lighter at rest. Profiling the running app put its
  largest single cost in AppKit's redraw of the menu bar status item — about
  22 ms every time the label changes, more than all the sampling put together —
  so the status item now updates on its own two-second cadence instead of on
  every sample. Measured over alternating 45-second runs at the default cadence,
  1.47% of a core down to 0.93%. Sampling, the graphs, the dashboard and the
  Touch Bar are as live as they were.
- Temperatures are read every five seconds rather than on every sample. A Mac
  publishes dozens of thermometers — 83 on the machine this was measured on —
  and each is its own round trip to the SMC, which made temperature alone cost
  more than every other metric combined: 19 ms against well under 1 ms. A sample
  now costs 4.7 ms instead of 18.9 ms. Nothing changes in what is read: when the
  sensors are read, all of them still are, and the hottest still wins.
- **GlassDeckKit API**: `SystemMonitor` gains `coarseSnapshot` and
  `coarseInterval`, a reading republished on a slower cadence for surfaces whose
  redraw costs more than the freshness buys. `ThermalSampler.sample()` takes an
  optional `at:` date, so its cadence can be driven in tests.

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

[1.5.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.5.0
[1.4.1]: https://github.com/FraCata00/glassdeck/releases/tag/v1.4.1
[1.4.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.4.0
[1.3.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.3.0
[1.2.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.2.0
[1.1.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.1.0
[1.0.0]: https://github.com/FraCata00/glassdeck/releases/tag/v1.0.0
