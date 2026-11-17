# Touch Bar pets — design

Date: 2026-11-17 · Status: draft, awaiting approval

## Intent

A small easter egg: a pixel-art animal that now and then walks across the Touch
Bar and acts out what the Mac is doing — it runs when the CPU is busy, sweats
when the machine is hot, falls asleep when nothing is happening. It is meant to
make someone smile when they notice it, and to read as a tiny emotional gauge of
the machine rather than as decoration. It must never cost enough to show up in
GlassDeck's own process list.

## Goals

- Three animals, chosen by the user in Settings: **octopus**, **frog**, and a
  **toy poodle** modelled on the owner's dog, Coco. One animal at a time.
- The animal's mood is derived from the data the bar already has.
- Rare by default, but it always turns up on a notable spike.
- It also turns up, at random, in the expanded detail of a metric, reacting to
  that metric.
- Tapping it gives a small reaction.

## Non-goals

- More animals, user-drawn sprites, or a random animal per visit.
- Any presence in the menu bar, the panel or the dashboard window.
- The mini bar and the Control Strip: there is no room.
- Persistence of anything about a visit (it is session-only).

## Anti-goals (a failure even if it works)

- Measurable cost while it is absent, or a visible bump in `sample <pid> 20`
  during a crossing.
- Redrawing any metric view because the animal moved.
- A second timer, a `TimelineView`, a display link or a `repeatForever`
  animation.
- Turning into an alarm: it must not appear on every spike of a busy machine.
- A tap on the animal opening the metric underneath it.

## Behaviour

### Presence

- **Random visits**: one crossing every ~15 minutes on average, the gap drawn
  uniformly from 8–25 minutes so it is not predictable.
- **Spikes**: when a reading crosses a threshold on the way up — CPU above 85 %,
  thermal state serious or worse, memory pressure critical, battery below 10 %
  and discharging — the animal enters at once in the matching mood. A cooldown
  of ~5 minutes separates one spike visit from the next.
- A crossing runs from one edge of the bar to the other and lasts ~20–30 s.
  If a spike is still under way when the animal reaches the far end it stops
  there and "works" until the load drops, then leaves.
- Only in the **expanded** and **fullscreen** modes. Never in `mini` or
  collapsed. Visits do not run while the bar is parked on display sleep or not
  presented; a visit in progress ends when the bar changes mode.
- **Detail view**: on roughly one opening in four, the animal appears in a
  corner of `TouchBarDetailView` and acts out that metric (e.g. fans itself in
  the temperature detail). It stays put; it does not cross.

### Moods

Derived from `coarseSnapshot` (never `snapshot`). When several apply, the first
in this list wins:

| Priority | Condition (indicative)                    | Mood       |
|----------|-------------------------------------------|------------|
| 1        | battery < 10 % and discharging            | `drained`  |
| 2        | thermal serious+ or fans near maximum     | `hot`      |
| 3        | memory pressure critical                  | `squeezed` |
| 4        | CPU > 85 %                                | `busy`     |
| 5        | network throughput high                   | `carrying` |
| 6        | on charge                                 | `charging` |
| 7        | CPU < 5 % for several minutes             | `sleepy`   |
| 8        | otherwise                                 | `calm`     |

Exact thresholds are the builder's, with hysteresis so the mood does not
flicker on a boundary. Absent hardware (no battery, no fans) simply never
triggers its mood.

### How each animal acts it out

The moods are shared; each animal has its own sprites for them.

- **Octopus** — walks with its tentacles; tentacles flail when `busy`, a pixel
  sweat drop when `hot`, puffed up when `squeezed`.
- **Frog** — moves in hops rather than steps; hops more often when `busy`, mouth
  open when `hot`, crouches when `sleepy`.
- **Coco** (toy poodle) — trots with bouncing ears; tongue out and panting when
  `busy` or `hot`, curls up asleep when `sleepy`. The name "Coco" appears in
  the settings picker and in the accessibility label.
  From the owner's photo: a red/russet curly coat (a warm reddish brown, two or
  three tones for the curls' highlights and shadows), a teddy-bear cut with a
  round, fluffy head, long curly ears hanging close to the face, round black
  eyes and a black button nose, no collar. At 16 × 16 the read should be "round
  russet puffball with a dark nose": a broken outline to suggest curls, the ears
  as darker blobs either side of the face.

Common to all: `carrying` holds a small parcel, `charging` has a spark over the
head, `drained` drags slowly in muted colours.

### Tap

A tap makes the animal hop and pull a face. It is consumed by the animal and
never reaches the `TouchBarTapView` or metric view underneath.

### Setting

A picker in the Touch Bar settings page: **Off / Octopus / Frog / Coco**,
defaulting to Octopus. Wired the usual way: a `Key`, a `didSet` that stores it,
a default in `Preferences.init`, and a line in `AppModel.preferenceChanges` (or
in the controller's `ObservationLoop`) so the change applies at once. Strings in
both `en` and `it` tables.

## Approaches considered

1. **One Core Animation animation per crossing** — *chosen*. At the start of a
   visit, a single finite animation moves the sprite layer from edge to edge and
   cycles the walk frames (a `CAKeyframeAnimation` on `contents` with discrete
   timing, a finite repeat count, plus a linear one on `position`). The render
   server does the work: no `draw(_:)`, no timer, no extra wake-ups in our
   process. When the mood changes mid-crossing, the next sample swaps the
   frame set. Finite, so it does not break the no-`repeatForever` rule — but it
   must be profiled.
2. **One step per sample with a Core Animation glide between samples** —
   *fallback* if profiling shows option 1 costs. Essentially free, but the walk
   frames change only every 1.5 s, so it looks like skating; fine for the frog,
   weaker for the others.
3. **A ~6 fps timer while a visit is on screen** — rejected. The most faithful
   pixel art, but it breaks the "no second timer" rule.

Drawing the animal inside the metric views' `draw(_:)` was dismissed outright:
it would redraw the expensive views on every step.

## Architecture

### Kit (`Sources/GlassDeckKit/Pets/`, tested)

Everything with arithmetic or decisions in it, with no AppKit:

- `PetKind` (`octopus`, `frog`, `poodle`) and `PetMood`.
- `PetMood.resolve(from: MetricsSnapshot, previous:)` — thresholds, priorities,
  hysteresis.
- `PetDirector` — a value-type state machine fed each coarse sample and the
  current time: when the next random visit is due, spike detection on rising
  edges, cooldown, the visit's phase (entering, crossing, waiting at the end,
  leaving) and the mood to show. Randomness goes through an injected generator
  so tests are deterministic.
- Sprite data: each frame is a grid of palette indices (e.g. string rows of
  `.`/`1`/`2`/…) at 16 × 16 logical pixels, plus per-animal palettes. Tests
  assert every frame has the right size and only uses defined indices, and that
  every animal has frames for every mood.
- The crossing geometry: start/end x for a bar width, duration, frames per
  second of the walk cycle.

### App (`Sources/GlassDeck/TouchBar/`)

- `TouchBarPetLayer` (or a small layer-backed view): rasterises the sprite grids
  into `CGImage`s once per animal and palette, cached, at the Touch Bar's 2×
  scale with nearest-neighbour (no smoothing). Installs and runs the animation;
  swaps the frame set on mood change; handles the tap.
- `TouchBarController` feeds the director from the `ObservationLoop` it already
  has (`TouchBarController.swift:80`) — no new observation and no new readings.
  Visits only run in expanded and fullscreen modes.
- `TouchBarDetailView`: the corner appearance as a sublayer, not inside
  `draw(_:)`.

### Where the layer lives — the first open risk

The bar is a row of separate `NSCustomTouchBarItem` views; no single view spans
it. The builder must first establish, with a quick spike, how to host one layer
over the whole row — most likely a sublayer of the content view of the window
hosting the items (`item.view.window?.contentView`), kept on top and resized
with it. If that is not reliable, the fallback is a dedicated item, or handing
the sprite from one metric view's layer to the next. This is the first thing to
verify, before any sprite work.

## Constraints

- The cost rules in `CLAUDE.md` all apply. Profile with `sample <pid> 20` with
  no visit, then during a crossing, before and after; record the numbers in the
  pull request.
- The pet only reads `coarseSnapshot`.
- Kit code builds on the macOS 15 SDK; no macOS 26 API is needed here.
- British spelling in comments; Conventional Commits with the `touchbar`
  (app), `kit` and `settings` scopes.
- Testing by hand uses the existing `GLASSDECK_TOUCHBAR_MODE` override; a
  `GLASSDECK_PET_VISIT=1` override that starts a crossing at launch would make
  this practical. Ask before launching a second instance; stop it with SIGTERM.

## Left to the builder

- Exact thresholds, hysteresis, cooldown and crossing duration within the
  ranges above.
- The pixel art itself, keeping the animals original (Coco is from the owner's
  description, not from any existing character).
- Whether palettes follow `TouchBarStyle` or stay fixed per animal; the
  animals must stay legible on every style. Coco's russet coat stays fixed
  whatever the style: it is what makes it Coco.
- Exact detail-view reactions per metric.
