# Measured cost

Numbers from the machine this was built on, kept because the power result is the
one thing a reader should know before leaving this on a laptop screen. One
machine, one GPU — see the caveat in [the README](../README.md#requirements).

Machine: ThinkPad X1 Yoga 3rd Gen · i7-8650U · Intel UHD 620 (Gen9.5, 24 EU, 1150 MHz max)
Display: 1920x1080@60 eDP, scale 1.25 (overlay is 1536x864 logical / 1920x1080 physical)
Omarchy 4.0.1 Quattro · Hyprland/Wayland
Measured 2026-08-27, **on battery**, 60 s sample windows.

## Numbers

| Metric | Idle (dismissed) | Borealis running | Delta |
|---|---|---|---|
| GPU clock, avg | 301 MHz | **748 MHz** (peak 1150 = max) | +447 MHz (2.5x) |
| System power | 5.87 – 6.38 W | **13.88 W** | **+7.5 to +8.0 W** |
| quickshell CPU | 40 – 45 % | 67.6 % | +23 – 28 pp |
| quickshell RSS | 509 – 511 MB | 523 MB | +13 MB |

Battery runtime: **~7.8 h idle → ~3.3 h with Borealis on screen.**

## Reading of the numbers

- **Framerate is fine, power is not.** The scene renders smoothly and correctly
  (curtains, starfield, crescent moon, tree-spiked ridge, water reflection all present).
  But the GPU averages 748 MHz and *touches its 1150 MHz ceiling* — this is not a shader
  the UHD 620 coasts through. The +7.5 W delta landed at the top of the 4–8 W estimate.
- **"Zero work while dismissed" is true, and verified twice.** Installing the plugin
  changed nothing at idle (GPU stayed 301 MHz, RSS flat despite `keepLoaded: true`), and
  on dismiss the GPU drops back to 300 MHz immediately. The `NumberAnimation`'s
  `running: root.opened` gate does what the README claims.
- **The cost is concentrated in the water.** `main()` calls `upperScene()` five times
  below `WATERLINE = 0.82` for reflection taps, so the bottom 18 % of the screen costs
  5x the sky — a weighted ~1.7x average. Dropping to 3 taps is the cheapest big win if
  this needs to get lighter.

## Decision

The plan's gate was: >6 W delta ⇒ AC-only is essential, not merely tidy. **We measured
+7.5 W, so: AC-only.** Running this as an unattended battery screensaver would more than
double idle draw precisely while nobody is watching it.

## Incidental finding (unrelated to Borealis)

`quickshell` already burns **40–45 % of a core at idle**, before Borealis is involved,
with a busy `QDBusConnection` thread (~10–19 %). That is pre-existing bar/plugin load and
is worth chasing separately — it is a bigger steady-state drain than the aurora, because
it runs all the time.

## State after the trial

- Plugin installed and enabled: `~/.config/omarchy/plugins/io.github.marko-builds.borealis/`
- `shell.json` → `plugins: [{ "id": "io.github.marko-builds.borealis" }]`
- Keybinding appended to `~/.config/hypr/bindings.lua` (Lua `o.bind`, **not** the README's
  stale `bindings.conf` / `bindd` form, which does not exist on Omarchy 4)
- Untouched: `omarchy-screensaver-clock.service` (still active + enabled),
  `shell.json` idle block (150 s / 300 s), `omarchy-launch-screensaver`
- Nothing is wired to idle — the terminal screensaver still owns the idle path

## Rollback

    omarchy plugin remove io.github.marko-builds.borealis --yes
    # then delete the Borealis block at the end of ~/.config/hypr/bindings.lua

## Touch fork — done

Forked to a separate plugin, `io.github.rma131.borealis-atlas`, so upstream stays pristine and
`omarchy plugin update`-able. Upstream is installed but **disabled**; the fork is enabled
and `SUPER+ALT+B` points at it.

**What it does.** Three touch slots reach the shader as `vec4(x, y, birth, down)`
and contribute a radial **repulsion field**; the aurora is sampled *through* that
field rather than having anything drawn on top of it.

- Curtains sample at `uv - displacement`, so light is pushed away from the finger.
- The field's **divergence** drives emission — light piling up burns brighter,
  rarefied light thins out. A held finger opens a dark well inside a brighter rim.
- The starfield is drawn before the curtains and is not displaced, so the stars
  read through wherever the aurora thins.
- Touch-down launches an expanding wave; its crests alternate compression and
  rarefaction, banking the light into moving rings that fade over ~3 s.
- On release the push decays as a damped oscillation, so the light overshoots and
  settles back rather than snapping.
- A **two-finger tap** cycles the palette (session-local; never rewrites shell.json).
- The water reflection evaluates the same field at the mirrored sky point, and the
  field separately displaces the water surface where the finger meets it.

**Dismissal is split by gesture**, because a screensaver still has to be trivial to
escape, especially folded into tablet mode where there is no keyboard:

| Gesture | Result |
|---|---|
| Quick tap (< 300 ms, < 12 px) | dismiss |
| Press and hold, or any drag | interact |
| Any key | dismiss |

**Cost: near-free, idle and active.** The guards test uniforms, not varyings, so the
branch is coherent and the field collapses to exactly zero when nothing is touching.
Like-for-like on AC (GPU clock, avg of 1150 max):

| | GPU avg |
|---|---|
| Stock upstream (measured twice, 951 / 952 MHz) | 952 MHz |
| Field fork, nothing touching | 1014 MHz |

The field model costs about **+6.5 %** at idle. Not the field maths — with no touch
every slot early-outs and the field is exactly zero — but `upperScene` now carries
field parameters through all five of the water's reflection taps, and the extra live
values cost occupancy on a 24-EU part. Interaction on top is nearly free (~+2 %),
because the field is evaluated once per pixel and shared across those taps.

The earlier additive-bloom version *was* free at idle; this one is not. The lever to
get it back is the reflection tap count, not the touch code. (These AC numbers are *not* comparable to the battery figures
above — on AC the discharge reading is meaningless and the GPU governor boosts higher.
The +7.5 W battery result stands as the power finding.)

### Two traps worth remembering

1. **Quickshell caches compiled QML** in `~/.cache/quickshell/qmlcache` and serves a
   stale component after a plugin edit — edits appear to do *nothing*. Clearing
   `~/.cache/qtshadercache-*` alone is not enough. Always:
   `rm -rf ~/.cache/quickshell ~/.cache/qtshadercache-* && omarchy-restart-shell`.
2. **`open()` calls `clearSlots()`**, so a touch slot pinned as a property *default* for
   testing is wiped the instant the overlay is summoned. This mimics the uniform never
   being delivered and sent this investigation a long way down the wrong road. Pin test
   values *inside* `clearSlots()`.

## Not done (deferred)

1. **Idle wiring, AC-only.** Omarchy's idle service tracks the screensaver by watching
   Hyprland for a window of class `org.omarchy.screensaver`; Borealis is a layer-shell
   surface and emits no such window event, so this needs a bridge, not a config line.
2. **30 fps throttle** — roughly halves the GPU cost; untested.
3. **Real finger validation.** Every touch check here drove the uniforms directly; no
   tool on this box can synthesise a `wl_touch` event (`wtype` is keyboard-only). The
   gesture handling itself is unexercised until you put a finger on the glass.

## Re-measured 2026-09-22, with the battery mode

Same machine, same method, **on mains this time** — the GPU's average clock is
the metric that moves, because both modes are vsync-bound at ~55 fps on a 60 Hz
panel and frame count therefore says nothing about how hard the GPU worked
inside each frame. Overlay dismissed reads 302 MHz, against 301 in August, so
the two sets of numbers are comparable.

| Scene | GPU avg | vs full |
|---|---|---|
| Idle, overlay dismissed | 302 MHz | — |
| Toronto, full (mains) | 1021 MHz | — |
| Toronto, reflection taps 5 → 3 only | 995 MHz | −2.5 % |
| Toronto, 75 % render resolution | 876 MHz | −14 % |
| **Toronto, battery mode as shipped** | **688 MHz** | **−33 %** |
| Banff, 75 % / 60 % render resolution | 703 / 601 MHz | −31 % / −41 % |

**The scene costs more than it did.** 748 MHz average in August, 1021 now, against
the same 1150 MHz ceiling — eclipses, storms, the globe and the growing season
have all been added since. It now sits near the ceiling for most of every frame.

**The 2026-08 remedy no longer applies.** "The bottom 18 % of the screen costs 5×
the sky … dropping to 3 taps is the cheapest big win" is measured at 2.5 % today,
and that is with a lake filling the foreground; at a place with a river it is a
narrow band, and at a place with no water it is nothing at all. What works is
drawing fewer pixels: 60 % in each dimension is 36 % of the fragments and a third
off the clock. It is kept for battery only, because what it costs is sharpness in
the tree crowns, which are the one thing in the scene a couple of pixels wide.

## Re-measured 2026-09-23, on battery, in watts

The rows above use the GPU's average clock, because the machine was plugged in
and `power_now` reports charging rather than draw. Unplugged, the real number is
available again — and it is much larger than the clock suggested.

Montreal, clear, 55 s windows, 45.2 Wh cell (`energy_full`):

| State | Draw | GPU avg | Runtime |
|---|---|---|---|
| Idle, overlay dismissed | **6.62 W** | 300 MHz | 6.8 h |
| Overlay open, battery mode | **10.73 W** | 618 MHz | 4.2 h |
| Overlay open, full quality | **18.22 W** | 863 MHz | 2.5 h |

**The overlay's own cost falls from +11.60 W to +4.11 W — 65 % of it gone**, and
the machine goes from 2.5 h to 4.2 h with the sky on screen. The GPU clock had
suggested 33 %; it understates the saving, because the clock is a coarse,
governed quantity and the work it hides scales with resolution while the clock
does not.

Note also that +11.60 W is well above the +7.5 W measured in August 2026. The
scene has grown — eclipses, storms, the globe, the growing season — and the cost
grew with it.

## Where the cost actually is, 2026-09-23

Measured on battery, Montreal, 40–45 s windows. **Watts carry about ±1 W of
run-to-run noise** on this machine — repeated runs of the same configuration
gave 10.73, 11.35 and 12.29 W — while the GPU's average clock repeats to within
a megahertz or two (589, 590 for the same config). So the clock is used here as
the comparator and watts as the headline. Idle with the overlay dismissed is
301 MHz and 6.62 W; the column is what each configuration adds to that.

| Configuration | GPU avg | over idle | share of shipped |
|---|---|---|---|
| Overlay open, **frozen** | 301 MHz | **+0** | 0 % |
| 10 fps, 60 % resolution | 356 MHz | +55 | 19 % |
| 20 fps, 60 % resolution | 437 MHz | +136 | 47 % |
| **10 fps, full resolution** | 471 MHz | **+170** | 59 % |
| 30 fps, 60 % resolution | 514 MHz | +213 | 74 % |
| 60 fps, 60 % resolution — *as shipped* | 589 MHz | +289 | 100 % |
| 60 fps, full resolution | 863 MHz | +562 | 194 % |

**A still picture is free.** The overlay open and frozen draws 6.64 W against
6.62 W dismissed, at the idle clock. Every watt this thing costs is the
redrawing, not the scene: the shader is expensive per frame and there is nothing
expensive about the frame itself.

**Frames buy more than pixels.** Ten frames a second at full resolution costs
less than sixty at 60 % — +170 against +289 — so the blur that the battery mode
currently pays for the saving could be given back and the saving increased at
the same time.

### Two things that are not levers

- **The touch field.** `touchField1` returns early on a uniform comparison when
  no finger is held and no ripple is alive, so it costs three comparisons per
  pixel while nobody is touching. It is already free.
- **A frame cap applied to one clock.** Capping `time` at 30 Hz saved nothing,
  because `tod` is animated separately by a `Behavior` and was still dirtying
  the scene every vsync. Driving both from separate 33 ms timers is *worse* than
  useless: the two interleave at unrelated phases and produce sixty renders a
  second between them, with the timer overhead on top. A frame cap has to be one
  clock that everything hangs off.

### What the frame is made of, at the shipped configuration

| Feature removed | GPU avg | saving | share of +289 |
|---|---|---|---|
| Trees on the ridge | 535 MHz | −54 | 19 % |
| Cloud deck | 551 MHz | −39 | 13 % |
| Reflection taps 5 → 3 (already shipped) | — | −26 | 9 % |

Everything else measured below the noise floor individually. The aurora,
starfield and meteors are gated on night and cost nothing in daylight; the third
rain layer is gated on the storm tier.

## After pacing the frames, 2026-09-23

One clock, running only in the reduced-cost mode: 100 ms on a calm drifting sky,
33 ms when there is rain, snow or a storm in it, 16 ms while the scene is being
touched, scrubbed, searched or inspected.

| State | Draw | GPU avg | Overlay's own cost | Runtime |
|---|---|---|---|---|
| Idle, dismissed | 6.62 W | 301 MHz | — | 6.8 h |
| **Paced, calm sky** | **8.76 W** | **354 MHz** | **+2.14 W** | **5.2 h** |
| Unpaced cheap mode | ~11.4 W | 589 MHz | +4.8 W | 4.0 h |
| Full quality | 18.22 W | 863 MHz | +11.60 W | 2.5 h |

**82 % of the overlay's cost is gone against full quality**, for the same
picture. All three rates were observed: 354 MHz on a calm Montreal sky, 509 MHz
at Quito while it drizzled, 658 MHz with the search open, and back to 392 MHz
after dismissing it.

What this leaves is a scene that costs about two watts to look at, on a machine
whose shell already burns 39–45 % of a core doing nothing. The next honest
target is not in this plugin.

## Spike: is a text-art mode a cheaper scene? 2026-09-23

Run before building anything, to price a proposed braille/character-grid mode
against the smooth one. On battery, 50 s windows, screen at 5 % brightness —
**absolute watts here are not comparable with the sections above**, only the
deltas within this table are. Dismissed idle is 301 MHz.

| Configuration | GPU | over idle | W |
|---|---|---|---|
| Dismissed | 301 MHz | +0 | — |
| Shipped: 60 % scale, 10 fps | 383 MHz | **+82** | 8.10 / 8.71 |
| Scene at a braille grid, 320×180, 10 fps | 309 MHz | **+8** | 7.89 |
| Fragments removed entirely, 10 fps | 313 MHz | +12 | 7.56 |
| Fragments removed, 3 fps | 306 MHz | +5 | 7.46 |
| Fragments removed, 60 fps | 317 MHz | +16 | 8.86 |
| A trivial fullscreen pass, full resolution | 314 MHz | +13 | 8.37 |
| A trivial fullscreen pass, at grid resolution | 306 MHz | +5 | 7.04 |

**The frame-rate lever is spent.** With fragments removed, 60 → 10 fps is worth
**1.30 W** and 10 → 3 fps is worth **0.10 W**. The pacing shipped earlier the
same day already took all of it. A character grid's one structural advantage —
that it can credibly run at 2–4 fps where a smooth gradient sky cannot — is
therefore worth a tenth of a watt, which is nothing.

**Drawing the scene at a braille grid removes 90 % of the overlay's GPU work**
(+82 MHz → +8) **and that is worth about half a watt**, because the GPU was
never the expensive part. The frame loop is.

**Half a watt is below what this machine can measure.** The *same* configuration
read 8.10 W and 8.71 W on two runs an hour apart, while its GPU clock reproduced
at 383 MHz both times. Watts carry ±0.6 W here; the clock carries ±2 MHz.

So: **a text-art mode is not a power feature.** It is worth building if it is
worth looking at. And since a two-pass structure exists only to make fragments
cheap, and cheap fragments are worth an unmeasurable half watt, the simple
single-pass form — quantise to the dot centre inside the existing shader — is
the one to build. One shader, one binary, no provenance change.

### Measurement notes, both of which nearly spoiled this

- **A battery fresh off the charger has not settled.** The dismissed baseline
  read 8.39 W and then 7.16 W a few minutes later with nothing changed. Let it
  discharge before trusting absolute watts.
- **Assert the condition you are measuring.** An earlier attempt to measure a
  battery-only code path produced three identical readings because the machine
  had been plugged back in and the path never ran. The harness now refuses to
  start on mains and prints whether the overlay is actually open.
