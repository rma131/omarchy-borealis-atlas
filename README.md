# Borealis Atlas

A touchscreen sky and weather explorer for [Omarchy](https://omarchy.org).
Summon it and you get the sky where you actually are: today's forecast, the sun
rising and setting when it really does, the horizon measured from the terrain
around you, snow lying above the freezing level, and the aurora at whatever the
solar wind is doing tonight. Drag a finger across the screen and time moves —
seven days back, sixteen forward.

It is 100% procedural. One fragment shader, no image assets.

![Reykjavik at night — aurora over the sea, with the moon at its real phase](docs/media/reykjavik-aurora.jpg)

> The aurora scene began as a fork of
> [marko-builds/borealis](https://github.com/marko-builds/borealis) (MIT) and is
> still descended from it — the curtains, the starfield, the meteors and the
> water are its design. What grew around it is new: a finger the light reacts
> to, real weather, a measured horizon, and the 23-day scrub.

## What it looks like

Every image below is a real render at a real moment — a place, a date and an
hour that the data actually had. Nothing is staged; where there is fog it is
because there was fog.

### One place, through a day

Montreal, at its own true sunrise and sunset for that date.

| | |
|---|---|
| ![Dawn](docs/media/light-dawn.jpg) | ![Midday](docs/media/light-day.jpg) |
| **06:16 — sunrise.** Not six o'clock: the sun clears the horizon when it really does, and the moon is still up. | **Midday.** The far bank, Mount Royal on the skyline, and the near bank you are standing on. |
| ![Sunset](docs/media/light-sunset.jpg) | ![Night](docs/media/light-night.jpg) |
| **19:32 — sunset.** The day length comes from the date and the latitude, so this moves through the year. | **Night**, here at Reykjavik, with the aurora at whatever NOAA says the solar wind is doing. |

### Weather it found, not weather it invented

| | |
|---|---|
| ![Fog](docs/media/weather-fog.jpg) | ![Snow](docs/media/weather-snow.jpg) |
| **Fog** — Montreal, 31 August, 08:00. The forecast said fog for that hour, so the scene is fogged. | **Snow** — Ushuaia, 12 September. Snow showers at 4.8 °C over 7 cm of lying snow, which is why the ground is white and the air is not clear. |

### Places that look like themselves

| | |
|---|---|
| ![Quito](docs/media/quito-pichincha.jpg) | ![Montreal](docs/media/montreal-river.jpg) |
| **Quito.** Pichincha where it really stands, bare above the treeline, paramo in front and no lake — because there is no water within 6 km of Quito. | **Montreal.** Seen from across the St Lawrence, because that is where the water is. The swell on the skyline is Mount Royal. |
| ![Zermatt](docs/media/zermatt-snowline.jpg) | ![Tromso](docs/media/tromso-treeline.jpg) |
| **Zermatt.** Snow lies above the freezing level and nowhere else, so the line cuts dead straight across the range, and it moves as you scrub through colder days. | **Tromso.** The treeline is about 700 m this far north, so the fjord ridges are forested at the bottom and bare above it. |

### The moon, at its real phase

Same overlay, three different dates. The phase is arithmetic, not a picture.

![Moon phases: full, waning gibbous, last quarter](docs/media/moon-phases.jpg)

### Five palettes

`aurora` by default; `ember`, `gold`, `nord` and `ice` are one key in
`shell.json`, or a two-finger tap. Same place, same minute.

![The aurora, ember, gold, nord and ice palettes](docs/media/palettes.jpg)

## Install

```sh
omarchy plugin add https://github.com/rma131/omarchy-borealis-atlas.git --enable
```

Then bind it. Omarchy's Hyprland config is Lua, so in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + B", "Borealis Atlas",
       "omarchy-shell shell summon io.github.rma131.borealis-atlas")
```

## Remove

```sh
omarchy plugin remove io.github.rma131.borealis-atlas
```

That takes the plugin and its `shell.json` entry with it. One file is left
behind, the cached sky at `~/.local/state/omarchy/borealis-sky.json`; delete it
if you want nothing left:

```sh
rm -f ~/.local/state/omarchy/borealis-sky.json
```

## Requirements

- **Omarchy 4 (Quattro)** or later — it is a Quickshell `overlay` plugin
- **`curl`** — the only runtime dependency beyond a POSIX shell
- A **touchscreen** is the point of it, but every gesture has a pointer
  equivalent and it is perfectly usable with a mouse

Built and measured on one machine: a ThinkPad X1 Yoga 3rd Gen with Intel UHD 620
graphics, 1920×1080. It has not been tried on anything else. It is a fullscreen
shader and it is not cheap — see [docs/measurements.md](docs/measurements.md)
before you leave it running on battery.

## Use

| Gesture | What happens |
|---|---|
| Drag left or right | Move through time — 7 days back, 16 forward |
| Double tap | Return to now, rolling back through the days |
| Quick tap | Dismiss |
| Two-finger tap | Next palette |
| Press and hold, or drag | Play with the aurora — no dismiss |
| `/` | Type a place to look at |
| Any other key | Dismiss |

Up to three fingers at once. A finger is a repulsor in the aurora rather than a
light drawn on top of it: the curtains are sampled *through* the field, so light
thins where it is rarefied and burns where it piles up, and springs back when
you let go.

A readout under the scene names the date, the conditions and the temperature at
wherever you have dragged to, and a strip along the bottom shows the whole
window at a glance.

## Configure

Everything lives on the plugin's own entry in `~/.config/omarchy/shell.json`,
and is applied live when you save:

```json
{
  "plugins": [
    {
      "id": "io.github.rma131.borealis-atlas",
      "location": "Reykjavik",
      "palette": "ember",
      "auroraFloor": 0.12
    }
  ]
}
```

| Key | Default | Meaning |
|---|---|---|
| `location` | — | A place name. Geocoded once and remembered. |
| `latitude` / `longitude` | — | Exact coordinates, taking precedence over `location`. |
| `palette` | `aurora` | `aurora`, `ember`, `gold`, `nord`, `ice`. |
| `auroraFloor` | `0.12` | Keeps a ghost of aurora on a quiet night, so the scene stays itself. |

With **no** location set it follows your IP, so a VPN moves the sky with you.
A two-finger tap also cycles the palette for the life of the shell, and that
override is deliberately *not* written back to `shell.json` — your configured
palette is never silently rewritten.

## What it fetches, and where that goes

No account, no API key, nothing stored anywhere but your own machine.

| What leaves your machine | Where it goes | Why |
|---|---|---|
| Your IP, implicitly | `get.geojs.io`, and `wttr.in` as a fallback | To know roughly where you are — **only when no location is configured** |
| An approximate latitude and longitude | `api.open-meteo.com`, `archive-api.open-meteo.com`, `geocoding-api.open-meteo.com` | Forecast, a year of climate normals, terrain elevation, and place search |
| Nothing | `services.swpc.noaa.gov` | NOAA's global aurora index, which is the same for everyone |

Set `location` in `shell.json` and the IP lookup never happens at all.

It writes exactly one file, `~/.local/state/omarchy/borealis-sky.json`, holding
the last answers so the overlay opens instantly and still works offline. It
never edits `shell.json` or any other configuration.

Weather, climate, elevation and geocoding come from
[Open-Meteo](https://open-meteo.com) (CC BY 4.0), built on
[ECMWF](https://www.ecmwf.int) and other national services; elevation is the
[Copernicus DEM](https://spacedata.copernicus.eu). Space weather is
[NOAA SWPC](https://www.swpc.noaa.gov), public domain.

## How it works

The interesting parts are all in [docs/design.md](docs/design.md) — how the
horizon is measured rather than invented, how snow finds the freezing level, how
water is detected by being the one flat thing in a terrain model, and what was
tried and thrown away. [docs/development.md](docs/development.md) covers
rebuilding the shader and clearing the QML cache.

## Credits

[marko-builds/borealis](https://github.com/marko-builds/borealis) by Marko
Stankovic, MIT — the aurora scene this grew out of, and still the shape of the
sky, the water and the ridge. If you want the original, calm, non-interactive
version, install that one.

## Licence

MIT — see [LICENSE](LICENSE). Copyright is held jointly: Marko Stankovic for
the original Borealis, and rma131 for everything added here.
