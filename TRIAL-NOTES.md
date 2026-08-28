# Borealis trial — measured results

Machine: ThinkPad X1 Yoga 3rd Gen · i7-8650U · Intel UHD 620 (Gen9.5, 24 EU, 1150 MHz max)
Display: 1920x1080@60 eDP, scale 1.25 (overlay is 1536x864 logical / 1920x1080 physical)
Omarchy 4.0.1 Quattro · Hyprland/Wayland · battery 45.6 Wh @ 84% health
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

Forked to a separate plugin, `local.borealis-touch`, so upstream stays pristine and
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
