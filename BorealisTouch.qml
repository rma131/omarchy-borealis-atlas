// BorealisTouch — a touch-reactive fork of marko-builds/borealis (MIT).
//
// Two changes from upstream. The shader gained three touch slots (ripples that
// ride the water's reflection UV, and an in-palette bloom under a finger), and
// the dismiss rule was split so the screen can be played with at all: upstream
// dismissed on *any* press, which on a touchscreen meant the first finger-down
// closed the overlay before anything could react.
//
// Dismiss rule: a quick tap dismisses (a screensaver must stay trivial to get
// out of, especially in tablet mode where there is no keyboard); press-and-hold
// past HOLD_MS, or any drag past DRAG_PX, is treated as intent to interact and
// will not dismiss. Any key still dismisses.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // The single config surface: "palette" on this plugin's entry in
  // ~/.config/omarchy/shell.json, applied live on save (shellConfig is
  // reactive):  "plugins": [{ "id": "local.borealis-touch",
  // "palette": "ember" }]  — aurora | ember | gold | nord | ice.
  // 6-stop ramps + sky tints from play/aurora.py PALETTES (0-255).
  readonly property var paletteTable: ({
    aurora: { p: [0.00, 0.12, 0.30, 0.55, 0.80, 1.00],
      c: [[150,45,180],[90,110,205],[35,200,200],[30,235,130],[25,180,80],[8,70,35]],
      sb: [6,8,18], sa: [8,10,22] },
    ember: { p: [0.00, 0.15, 0.35, 0.60, 0.82, 1.00],
      c: [[200,40,150],[225,60,95],[235,75,60],[240,120,40],[180,70,22],[60,20,12]],
      sb: [10,6,12], sa: [16,8,14] },
    gold: { p: [0.00, 0.15, 0.35, 0.60, 0.82, 1.00],
      c: [[120,70,20],[180,120,35],[225,165,55],[245,205,110],[235,175,90],[60,40,14]],
      sb: [10,8,6], sa: [16,12,8] },
    nord: { p: [0.00, 0.18, 0.40, 0.62, 0.82, 1.00],
      c: [[180,142,173],[129,161,193],[136,192,208],[143,188,187],[163,190,140],[90,110,75]],
      sb: [12,14,18], sa: [20,24,34] },
    ice: { p: [0.00, 0.15, 0.35, 0.60, 0.82, 1.00],
      c: [[60,90,200],[60,150,230],[90,210,235],[160,235,240],[130,185,160],[20,45,75]],
      sb: [6,9,22], sa: [8,14,26] }
  })
  property string configPalette: {
    var cfg = root.shell && root.shell.shellConfig
    var plugins = (cfg && cfg.plugins) || []
    for (var i = 0; i < plugins.length; i++) {
      var e = plugins[i]
      // hasOwnProperty, never `paletteTable[k] !== undefined`: every key on
      // Object.prototype ("__proto__", "constructor", "toString",
      // "hasOwnProperty", "valueOf") answers a plain lookup, so the loose test
      // accepts all five and hands `pal` the prototype object, whose ramp is
      // undefined. Measured in the shipping Qt V4 engine as a TypeError on
      // every colour uniform.
      var name = e && e.palette !== undefined ? String(e.palette) : ""
      if (e && e.id === "local.borealis-touch"
          && Object.prototype.hasOwnProperty.call(paletteTable, name))
        return name
    }
    return "aurora"
  }
  // Two-finger tap cycles this. -1 follows shell.json; the override lives as
  // long as the shell does (keepLoaded) and is deliberately not written back to
  // shell.json, so your configured palette is never silently rewritten.
  property int paletteOverride: -1
  readonly property var paletteNames: ["aurora", "ember", "gold", "nord", "ice"]
  readonly property string palette: paletteOverride >= 0
    ? paletteNames[paletteOverride] : configPalette
  readonly property var pal: paletteTable[palette]

  function cyclePalette() {
    var cur = paletteOverride >= 0 ? paletteOverride : paletteNames.indexOf(configPalette)
    if (cur < 0) cur = 0
    paletteOverride = (cur + 1) % paletteNames.length
  }

  // ramp stop i as vec4: rgb (0-1) + stop position in w
  function stopVec(i) {
    return Qt.vector4d(pal.c[i][0] / 255, pal.c[i][1] / 255, pal.c[i][2] / 255, pal.p[i])
  }

  // Interaction tuning. HOLD_MS/DRAG_PX are the tap-vs-play threshold; a
  // release inside both is a dismiss, anything beyond either is interaction.
  readonly property int holdMs: 300
  readonly property real dragPx: 12
  // Days covered by dragging the full width of the screen. The window is now 23
  // days wide, so at 1.0 crossing it took 23 swipes; 2.5 still leaves about two
  // minutes of forecast per pixel, which is far finer than the hourly data.
  readonly property real todGain: 2.5

  // the clock is the default: whatever time it actually is when you summon it






  function clockFraction() {
    var n = new Date()
    return (n.getHours() * 3600 + n.getMinutes() * 60 + n.getSeconds()) / 86400.0
  }

  function syncTimeOfDay() {
    if (!scene) return
    root.todReturning = false
    scene.tod = clockFraction()
  }

  // Left alone the sky drifts forward, about an hour of sky per minute of real
  // time, so you look up and the day has moved. Touching it cancels the drift
  // and returns to the true now: idle is ambience, touched is truth. Nothing
  // on screen lies, because the readout is hidden while this runs.
  readonly property int driftMs: 250
  readonly property real driftHoursPerMinute: 1.0
  property bool drifting: false

  // Bleed the smear away once the drag stops. Without this the last velocity
  // would stick, because onTodChanged simply stops firing.
  Timer {
    interval: 60; repeat: true
    running: root.opened && root.todVel > 0.015
    onTriggered: {
      root.todVel *= 0.72
      if (root.todVel < 0.02) root.todVel = 0
      if (scene) scene.ice = Qt.vector4d(scene.ice.x, scene.ice.y, root.todVel, 0)
    }
  }

  Timer {
    interval: root.driftMs
    repeat: true
    running: root.opened && !root.scrubbing && root.inspectMode === 0
    onTriggered: {
      if (!scene) return
      root.drifting = true
      var step = (root.driftHoursPerMinute / 24.0) * (root.driftMs / 60000.0)
      scene.tod = Math.min(root.todMax, scene.tod + step)
    }
  }

  // scrubbing / inspect state
  property real sceneH: 1080          // panel height, for readout sizing
  property bool todReturning: false
  property bool scrubbing: false
  property int  inspectMode: 0        // 0 off, 1 aurora, 2 moon (event only)
  property real inspectReveal: 0
  Behavior on inspectReveal { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

  function cycleInspect() {
    if (!scene) return
    var m = moonAt(todToDate(scene.tod))
    if (inspectMode === 0) inspectMode = 1
    else if (inspectMode === 1) inspectMode = (m.event > 0.5) ? 2 : 0
    else inspectMode = 0
    inspectReveal = inspectMode > 0 ? 1 : 0
    pushSky()
  }

  // Rebuilding a Date, formatting it and concatenating strings every frame is
  // wasted while the readout is invisible — and the idle drift makes `tod`
  // change every frame, so it was running constantly for nothing.
  property string readoutLine: ""
  function buildReadout() {
        if (!scene) return ""
        root.dataRev            // re-read when a fetch lands
        var o = root.sky
        var d = root.todToDate(scene.tod)
        var today = new Date(); today.setHours(0, 0, 0, 0)
        var dd = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
                             - today.getTime()) / 86400000)
        // beyond tomorrow the date line underneath names the day already
        var tag = dd === -1 ? "Yesterday " : dd === 1 ? "Tomorrow " : ""
        var line = tag + Qt.formatTime(d, "HH:mm")
        if (o.has) {
          line += "   " + o.cond
          if (o.temp !== null) line += "   " + Math.round(o.temp) + "\u00b0"
        }
        if (root.inspectMode === 1)
          line += "   " + (o.kp !== null ? "Kp " + o.kp.toFixed(1) : "Kp \u2014")
                + ", aurora " + root.auroraWord(o.aurora)
        else if (root.inspectMode === 2) {
          var m = root.moonAt(d)
          line += "   " + m.name + (m.eventName ? "  \u00b7  " + m.eventName : "")
                + "   " + Math.round(m.illum * 100) + "%"
        }
        return line
  }
  function refreshReadout() {
    if (root.scrubbing || root.inspectMode > 0) root.readoutLine = buildReadout()
  }

  // One finger: two taps come home to today, three leave. A single tap does
  // nothing on purpose — this is a screensaver you can hold a forecast in, so
  // leaving should be deliberate. Any key still exits immediately.
  property int tapCount: 0

  function goToNow() {
    if (!scene) return
    root.todReturning = true
    root.drifting = false
    // the real present, not "this hour, still three days out" — which is what
    // rounding to the nearest equivalent of now used to do
    scene.tod = clockFraction()
    root.inspectMode = 0
    root.inspectReveal = 0
    root.scrubbing = true
    readoutHideTimer.restart()
    refreshReadout()
  }

  readonly property bool awayFromNow:
    scene ? Math.abs(scene.tod - clockFraction()) > 0.02 : false

  function auroraWord(p) {
    if (p >= 0.75) return "very likely"
    if (p >= 0.45) return "likely"
    if (p >= 0.20) return "possible"
    return "unlikely"
  }

  // pointId occupying each shader slot, -1 when free. A released slot is freed
  // for reuse immediately but keeps its birth stamp, so its ripple plays out.
  // ==== real sky =============================================================
  // Everything below resolves to six numbers pushed into two uniforms. The
  // shader does no lookups and holds no arrays — deliberately, since the GLSL
  // 120 target this compiles to rejects them (see the note atop aurora.frag).

  readonly property string cachePath: Quickshell.env("HOME") + "/.local/state/omarchy/borealis-sky.json"
  readonly property real cacheMaxAgeMs: 30 * 60 * 1000

  // never quite zero, so a quiet night still has a ghost of aurora
  readonly property real auroraFloor: {
    var cfg = root.shell && root.shell.shellConfig
    var plugins = (cfg && cfg.plugins) || []
    for (var i = 0; i < plugins.length; i++) {
      var e = plugins[i]
      if (e && e.id === "local.borealis-touch" && e.auroraFloor !== undefined) {
        var v = parseFloat(e.auroraFloor)
        if (!isNaN(v)) return Math.max(0, Math.min(1, v))
      }
    }
    return 0.12
  }

  // How far the scrub may run, in tod units (days from today's midnight),
  // derived from the data itself so it follows the fetch parameters. With
  // past_days=1 the earliest real hour is yesterday 00:00 — there is no data
  // for the day before that, so the drag must not pretend otherwise.
  readonly property real todMin: (fc && fc.code.length) ? fc.t0 / 24.0 : -7.0
  readonly property real todMax: (fc && fc.code.length)
                                 ? (fc.t0 + fc.code.length - 1) / 24.0 : 2.95
  // Kp only forecasts ~3 days; past that o.kp stays null and the aurora falls
  // back to the floor rather than pretending to know.

  property int dataRev: 0
  onFcChanged: { _lastPush = -9999; dataRev++; pushSky(); refreshReadout() }
  onKpChanged: { _lastPush = -9999; dataRev++; pushSky() }
  onRingChanged: { _lastPush = -9999; pushSky() }
  onClimateChanged: { _lastPush = -9999; pushSky() }
  // sky angular speed, for motion blur
  property real todVel: 0
  property real _velTod: 0
  property real _velMs: 0
  property real _lastPush: -9999
  // Location, in order of preference: explicit coordinates in shell.json, then
  // a place name there (geocoded once), then IP lookup. Set it per-plugin:
  //   { "id": "local.borealis-touch", "location": "Reykjavik" }
  //   { "id": "local.borealis-touch", "latitude": 64.15, "longitude": -21.94 }
  readonly property var configLoc: {
    var cfg = root.shell && root.shell.shellConfig
    var plugins = (cfg && cfg.plugins) || []
    for (var i = 0; i < plugins.length; i++) {
      var e = plugins[i]
      if (!e || e.id !== "local.borealis-touch") continue
      var la = parseFloat(e.latitude), lo = parseFloat(e.longitude)
      if (!isNaN(la) && !isNaN(lo))
        return { lat: la, lon: lo, name: String(e.location || "Custom") }
      if (e.location) return { name: String(e.location) }   // geocode it
    }
    return null
  }
  // editing shell.json re-resolves immediately, which is the point of having it
  // The ring and the climate belong to the old place, not the new one. Leaving
  // them behind showed Phoenix with Montreal's aridity for as long as the
  // archive took to answer — and wrote that pairing into the cache.
  onConfigLocChanged: {
    root.loc = null; root.ring = null; root.climate = null
    root.fc = null; root.kp = null
    refreshSky(true)
  }

  property var loc: null      // { lat, lon, name, country }
  property real elevation: 0
  property var ring: null     // { spread (m across ~100 km), sea (0..1) }
  property var climate: null  // { ai } — a year of P / PET

  // What the land here is like, from what the forecast already tells us: how
  // cold, how dry, how high, how lush. Four scalars the shader blends between,
  // rather than a list of named biomes — the world does not have hard edges.
  // A function, not a binding: as a `readonly property var` this evaluated once
  // while fc was still null and never re-ran, so every place on earth came out
  // with the same default terrain.
  function computeTerrain() {
    if (!fc || !fc.temp || !fc.temp.length)
      return { cold: 0.35, arid: 0.15, lush: 0.25, alpine: 0,
               relief: ring ? Math.max(0, Math.min(1, (ring.spread - 30.0) / 1200.0)) : 0.5,
               water: 1.0 }
    var n = fc.temp.length, ts = 0, ps = 0
    for (var i = 0; i < n; i++) { ts += fc.temp[i] || 0; ps += fc.precip[i] || 0 }
    var meanT = ts / n                 // degrees C
    var mmDay = ps / (n / 24.0)        // mm per day
    var absLat = loc ? Math.abs(loc.lat) : 45

    var cl = function (v) { return Math.max(0, Math.min(1, v)) }
    var cold   = cl((8.0 - meanT) / 22.0)
    // UNEP puts arid below 0.20 and humid above 0.65; this spans that range.
    // The three-week fallback is only what shows before the archive lands.
    var arid   = climate ? cl((0.55 - climate.ai) / 0.50)
                         : cl(1.0 - mmDay / 2.2)
    var alpine = cl((root.elevation - 900) / 1800)
    // Vegetation follows water, not warmth: Phoenix is hotter than Montreal and
    // far greener by this measure until the aridity index gets a say. Without
    // it, a desert came out lush 0.45 and the ground was drawn forest green.
    var wet    = climate ? cl((climate.ai - 0.55) / 0.55) : (1.0 - arid)
    var lush   = cl((meanT - 13.0) / 12.0) * wet * (1.0 - alpine)
    // very high latitude thins the treeline regardless of the local average
    cold = Math.max(cold, cl((absLat - 58.0) / 12.0) * 0.85)

    // How high the skyline stands, measured rather than assumed: the spread of
    // elevation across the ring. Montreal comes out near flat at 63 m, Phoenix
    // ringed by real mountains at 414, Zermatt off the top at 2345.
    // 0.5 is the default because it reproduces exactly the amplitude the ridge
    // had before this was measured, so a failed lookup changes nothing.
    var relief = ring ? cl((ring.spread - 30.0) / 1200.0) : 0.5

    // Sea shows up in the ring as points at zero. Lakes and rivers do not —
    // they sit above sea level — so standing water inland is inferred from the
    // climate instead: a place has to be genuinely humid to keep any. Phoenix
    // is semi-arid and gets none; Dubai is drier still but sits on the Gulf,
    // and the ring finds it.
    var inland = climate ? cl((climate.ai - 0.40) / 0.35) : 1.0
    var water = ring ? cl(Math.max(ring.sea * 1.6, inland)) : inland

    return { cold: cold, arid: arid, lush: lush, alpine: alpine,
             relief: relief, water: water }
  }
  property var fc: null       // { t0, code[], precip[], cloud[], temp[] }
  property var kp: null       // { t0, step, vals[] }
  property real lastFetchMs: 0

  // ---- moon: pure arithmetic, no network -----------------------------------
  readonly property real synodicDays: 29.530588853
  readonly property real anomalisticDays: 27.554549878

  property var _moonCache: null
  property real _moonAt: -9999
  function moonAt(date) {
    // the moon does not move perceptibly inside a minute
    var key = Math.floor(date.getTime() / 60000)
    if (_moonAt === key && _moonCache) return _moonCache
    var r = moonCompute(date)
    _moonAt = key; _moonCache = r
    return r
  }

  function moonCompute(date) {
    var ref = Date.UTC(2000, 0, 6, 18, 14)           // a known new moon
    var d = (date.getTime() - ref) / 86400000.0
    var wrap = function (v, m) { return ((v % m) + m) % m }
    var phase = wrap(d, synodicDays) / synodicDays               // 0 new, .5 full
    var anom  = wrap(d - 2.0, anomalisticDays) / anomalisticDays // 0 at perigee
    var dist  = 1 - 0.0549 * Math.cos(2 * Math.PI * anom)        // ~0.945 .. 1.055
    var illum = (1 - Math.cos(2 * Math.PI * phase)) / 2
    // a supermoon is a full moon that also happens near perigee
    var nearFull = 1 - Math.min(1, Math.abs(phase - 0.5) / 0.055)
    var nearPeri = 1 - Math.min(1, Math.max(0, dist - 0.955) / 0.030)
    var superness = Math.max(0, Math.min(1, nearFull * nearPeri))
    return { phase: phase, dist: dist, illum: illum, event: superness,
             name: moonName(phase),
             eventName: superness > 0.5 ? "Supermoon" : "" }
  }

  function moonName(p) {
    var n = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
             "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"]
    return n[Math.floor(p * 8 + 0.5) % 8]
  }

  // ---- aurora: geomagnetic latitude vs the auroral oval --------------------
  function geomagneticLat(lat, lon) {
    var pLat = 80.7 * Math.PI / 180, pLon = -72.7 * Math.PI / 180
    var la = lat * Math.PI / 180, lo = lon * Math.PI / 180
    var sn = Math.sin(la) * Math.sin(pLat)
           + Math.cos(la) * Math.cos(pLat) * Math.cos(lo - pLon)
    return Math.asin(Math.max(-1, Math.min(1, sn))) * 180 / Math.PI
  }

  // The oval's equatorward edge sits near 66.5 - 2*Kp degrees; allow ~8 more
  // for aurora low on the northern horizon, and smooth the edge.
  function auroraProbability(kpVal) {
    if (!loc || kpVal === null || kpVal === undefined) return auroraFloor
    var mag = Math.abs(geomagneticLat(loc.lat, loc.lon))
    var p = (mag - (66.5 - 2.0 * kpVal - 8.0)) / 10.0
    return Math.max(auroraFloor, Math.max(0, Math.min(1, p)))
  }

  // ---- WMO grouping, matching Omarchy's own weather Model.js ---------------
  function classifyCode(c) {
    c = parseInt(String(c), 10)
    if (c === 0) return { kind: "clear", label: "Clear" }
    if (c === 1 || c === 2) return { kind: "clear", label: "Partly cloudy" }
    if (c === 3) return { kind: "cloud", label: "Overcast" }
    if (c === 45 || c === 48) return { kind: "fog", label: "Fog" }
    if (c >= 51 && c <= 57) return { kind: "rain", label: "Drizzle" }
    if (c === 61 || c === 63 || c === 65) return { kind: "rain", label: "Rain" }
    if (c === 66 || c === 67) return { kind: "rain", label: "Freezing rain" }
    if (c >= 71 && c <= 77) return { kind: "snow", label: "Snow" }
    if (c >= 80 && c <= 82) return { kind: "rain", label: "Showers" }
    if (c === 85 || c === 86) return { kind: "snow", label: "Snow showers" }
    if (c >= 95) return { kind: "storm", label: "Thunderstorm" }
    return { kind: "cloud", label: "Cloudy" }
  }

  // A code is categorical, so it cannot be averaged — but its *weights* can,
  // which is what stops rain snapping to snow between one hour and the next.
  function kindWeights(c) {
    var k = classifyCode(c)
    return { rain:  k.kind === "rain"  ? 1 : 0,
             snow:  k.kind === "snow"  ? 1 : 0,
             storm: k.kind === "storm" ? 1 : 0,
             fog:   k.kind === "fog"   ? 1 : 0 }
  }

  // A lake freezes on accumulated cold, not on the temperature right now, so
  // this reads back across the past days we already fetch.
  function trailingMeanTemp(hr, hours) {
    if (!fc || !fc.temp) return null
    var e = Math.floor(hr - fc.t0), b = Math.max(0, e - hours)
    e = Math.min(fc.temp.length - 1, e)
    if (e < b) return null
    var sum = 0, n = 0
    for (var i = b; i <= e; i++) { sum += fc.temp[i]; n++ }
    return n ? sum / n : null
  }

  // ---- resolve the whole sky for one moment --------------------------------
  // todValue is hours/24 from *today's* local midnight and may run past 1, so
  // dragging into tomorrow reads tomorrow's forecast.
  function resolveSky(todValue) {
    var hr = todValue * 24.0
    var o = { cloud: 0, rain: 0, snow: 0, storm: 0, fog: 0,
              snowCover: 0, frozen: 0, verglas: 0, wind: 0,
              rise: 0.25, set: 0.75,
              temp: null, cond: "", kp: null, aurora: auroraFloor, has: false }

    // The hourly samples start at midnight of the first day, so the day index
    // is just the hour offset over 24 — the same axis, coarser.
    if (fc && fc.rise && fc.rise.length) {
      var di = Math.floor((hr - fc.t0) / 24.0)
      di = Math.max(0, Math.min(fc.rise.length - 1, di))
      o.rise = fc.rise[di]; o.set = fc.set[di]
    }

    var x = fc ? hr - fc.t0 : -1
    if (fc && fc.code.length > 1 && x >= 0 && x <= fc.code.length - 1) {
      var i = Math.floor(x), f = x - i
      i = Math.max(0, Math.min(fc.code.length - 2, i))
      var lp = function (a) { return a ? a[i] + (a[i + 1] - a[i]) * f : 0 }
      var mixw = function (a, b) { return a + (b - a) * f }

      o.cloud = Math.max(0, Math.min(1, lp(fc.cloud) / 100))
      o.temp  = lp(fc.temp)

      // Intensity is no longer floored, so drizzle looks like drizzle.
      // 3 mm/h reads as heavy rain, 2 cm/h as heavy snow.
      var wetRate  = Math.max(0, Math.min(1, lp(fc.precip) / 3.0))
      var snowRate = Math.max(0, Math.min(1, lp(fc.snowfall) / 2.0))
      var wA = kindWeights(fc.code[i]), wB = kindWeights(fc.code[i + 1])
      o.rain  = mixw(wA.rain,  wB.rain)  * Math.min(1, 0.12 + wetRate)
      o.snow  = mixw(wA.snow,  wB.snow)  * Math.min(1, 0.15 + snowRate)
      o.storm = mixw(wA.storm, wB.storm) * Math.min(1, 0.35 + wetRate)
      o.fog   = mixw(wA.fog,   wB.fog)
      if (o.storm > 0) o.rain = Math.max(o.rain, o.storm * 0.8)

      // snow_depth is the ground truth for "does it settle": falling snow that
      // melts leaves this at zero, a white landscape does not. 25 cm reads full.
      o.snowCover = Math.max(0, Math.min(1, lp(fc.depth) / 0.25))

      // eastward wind component -> screen drift. Sampling p.x + t*w moves the
      // cloud toward -x, so the sign is flipped to match the real direction.
      var spd = lp(fc.wspd), dir = (lp(fc.wdir) || 0) * Math.PI / 180
      var eastward = -spd * Math.sin(dir)
      o.wind = Math.max(-0.045, Math.min(0.045, -0.0007 * eastward))

      // verglas: freezing rain by code, or plain rain onto sub-zero ground
      var code = fc.code[f < 0.5 ? i : i + 1]
      var soil = lp(fc.soil)
      o.verglas = (code === 56 || code === 57 || code === 66 || code === 67) ? 1.0
                : (o.rain > 0.05 && soil < -0.5 && o.temp > -8) ? 0.7 : 0.0

      var tm = trailingMeanTemp(hr, 72)
      if (tm !== null) o.frozen = Math.max(0, Math.min(1, (-2.0 - tm) / 6.0))

      o.cond = classifyCode(code).label
      o.has = true
    }

    // Kp samples are evenly spaced, so index them instead of scanning 81.
    if (kp && kp.vals.length > 0) {
      var step = kp.hrs.length > 1 ? (kp.hrs[1] - kp.hrs[0]) : 3
      var j = Math.round((hr - kp.hrs[0]) / step)
      if (j >= 0 && j < kp.vals.length && Math.abs(kp.hrs[j] - hr) < 6)
        o.kp = kp.vals[j]
    }
    o.aurora = auroraProbability(o.kp)

    return o
  }

  // Colour for one hour of the strip. Deliberately not resolveSky(): that
  // carries a 72 h trailing mean and a Kp lookup, and calling it 36 times a
  // frame would also evict the single-slot cache the sky itself relies on.
  function stripColour(todValue) {
    if (!fc || !fc.code.length) return "#00000000"
    var x = todValue * 24.0 - fc.t0
    if (x < -0.5 || x > fc.code.length - 0.5) return "#10ffffff"   // no data
    var i = Math.max(0, Math.min(fc.code.length - 1, Math.round(x)))
    var k = classifyCode(fc.code[i]).kind
    if (k === "storm") return "#c39bf5"
    if (k === "snow")  return "#e9f1ff"
    if (k === "rain")  return "#6ea6dd"
    if (k === "fog")   return "#b7bec6"
    var cl = Math.max(0, Math.min(1, fc.cloud[i] / 100))
    return Qt.rgba(0.29 + 0.44 * cl, 0.50 + 0.25 * cl, 0.78, 0.80 + 0.20 * cl)
  }

  // ---- push the resolved sky into the two uniforms -------------------------
  // The resolved sky, published once per push. The readout reads THIS rather
  // than calling resolveSky itself: doing that from inside a binding made the
  // binding read and then write the same cache, which Qt correctly reported as
  // a binding loop and which cost more than the cache ever saved.
  property var sky: ({ cloud: 0, rain: 0, snow: 0, storm: 0, fog: 0, snowCover: 0,
                       frozen: 0, verglas: 0, wind: 0, temp: null, cond: "",
                       kp: null, aurora: 0.12, has: false })

  function pushSky() {
    if (!scene) return
    var o = resolveSky(scene.tod)
    root.sky = o
    var m = moonAt(todToDate(scene.tod))
    scene.wx = Qt.vector4d(o.cloud, o.rain, o.snow, o.storm)
    // apparent size swings with distance; a real event adds emphasis on top
    var emphasis = (1.0 / m.dist - 1.0) * 2.0 + m.event * 0.5
                   + (root.inspectMode === 2 ? 0.5 : 0.0)
    scene.astro = Qt.vector4d(m.phase, o.aurora, root.inspectReveal, emphasis)
    // A dead-still sky looks broken rather than calm, so the drift has a floor.
    var w = o.has ? o.wind : 0.0105
    if (Math.abs(w) < 0.0025) w = 0.0025
    scene.wx2 = Qt.vector4d(w, 0, o.fog, o.snowCover)
    scene.ice = Qt.vector4d(o.frozen, o.verglas, root.todVel, 0)
    var tr = root.computeTerrain()
    scene.land = Qt.vector4d(tr.cold, tr.arid, tr.lush, tr.alpine)
    scene.geo = Qt.vector4d(tr.relief, tr.water, o.rise, o.set)
  }

  function hoursFromMidnightLocal(iso) {      // "2026-08-27T14:00", local
    var a = String(iso).split("T"), d = a[0].split("-"), t = (a[1] || "0:0").split(":")
    var dt = new Date(parseInt(d[0], 10), parseInt(d[1], 10) - 1, parseInt(d[2], 10),
                      parseInt(t[0], 10), parseInt(t[1] || "0", 10), 0)
    var mid = new Date(); mid.setHours(0, 0, 0, 0)
    return (dt.getTime() - mid.getTime()) / 3600000.0
  }

  // "2026-08-30T05:59" -> 0.2493, a fraction of the local day. The forecast is
  // fetched with timezone=auto, so these are already local wall-clock times and
  // land on the same axis `tod` runs along.
  function dayFractionOf(iso) {
    var t = String(iso).split("T")[1]
    if (!t) return -1
    var q = t.split(":")
    return (parseInt(q[0], 10) + parseInt(q[1] || "0", 10) / 60.0) / 24.0
  }

  // Inside the polar circles the sun does not cross the horizon at all and the
  // API returns null; daylight_duration is what says which kind of nothing it
  // is. A near-full or near-empty day is as close as the sine model can get,
  // and reads correctly as a sun that grazes the horizon or never clears it.
  function parseDaylight(dy) {
    var rise = [], set = []
    var n = (dy && dy.time) ? dy.time.length : 0
    for (var k = 0; k < n; k++) {
      var r = dy.sunrise ? dy.sunrise[k] : null
      var t = dy.sunset  ? dy.sunset[k]  : null
      var dur = dy.daylight_duration ? dy.daylight_duration[k] : null
      if (r && t) { rise.push(dayFractionOf(r)); set.push(dayFractionOf(t)) }
      else if (dur !== null && dur > 43200) { rise.push(0.02); set.push(0.98) }
      else { rise.push(0.48); set.push(0.52) }
    }
    return { rise: rise, set: set }
  }

  function hoursFromMidnightUtc(iso) {        // NOAA time_tag, UTC, no suffix
    var dt = new Date(String(iso).replace(" ", "T") + "Z")
    var mid = new Date(); mid.setHours(0, 0, 0, 0)
    return (dt.getTime() - mid.getTime()) / 3600000.0
  }

  function refreshSky(force) {
    if (!force && Date.now() - lastFetchMs < cacheMaxAgeMs) return
    lastFetchMs = Date.now()
    var c = configLoc
    if (c && c.lat !== undefined) {
      root.loc = c; fetchForecast(); fetchKp(); fetchElevation(); fetchClimate(); return
    }
    if (c && c.name) { geocode(c.name); return }
    // No shortcut on an existing loc: the IP can move (a VPN, or actually
    // travelling), so an unconfigured location is re-detected every refresh.
    checkLocation(true)
  }

  property real lastLocMs: 0
  property real locStartedMs: 0
  // Throttled so summoning repeatedly does not hammer the lookup, but quick
  // enough that flipping a VPN and reopening shows the new place.
  function checkLocation(force) {
    if (configLoc) return
    // A lookup already in flight is left alone, but only for as long as curl's
    // own timeout: a wedged one must not disable detection for the session.
    if (locProc.running && Date.now() - locStartedMs < 20000) return
    if (!force && Date.now() - lastLocMs < 8000) return
    lastLocMs = Date.now()
    locStartedMs = Date.now()
    locProc.running = true
  }

  function geocode(place) {
    if (geoProc.running) return
    geoProc.command = ["curl", "-fsS", "--max-time", "8",
      "https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name="
      + encodeURIComponent(place)]
    geoProc.running = true
  }

  function fetchForecast() {
    if (!loc || fcProc.running) return
    fcProc.command = ["curl", "-fsS", "--max-time", "10",
      "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + loc.lat + "&longitude=" + loc.lon
      + "&hourly=weather_code,precipitation,cloud_cover,temperature_2m"
      + ",snowfall,snow_depth,soil_temperature_0cm,wind_speed_10m,wind_direction_10m"
      + "&daily=sunrise,sunset,daylight_duration"
      + "&past_days=7&forecast_days=16&timezone=auto"]   // 16 is the API max
    fcProc.running = true
  }

  // Aridity is a property of the climate, not of the next three weeks. Asking
  // the forecast window put Phoenix at 2.66 mm/day — a monsoon burst — and grew
  // it a lush lakeside. A year of the reanalysis archive gives the real answer,
  // and the model's habit of over-raining on deserts cancels out because what
  // is measured is the ratio of rain to how fast the sun takes it back:
  // P / PET, the UN's aridity index. Sahara 0.01, Dubai 0.18, Phoenix 0.26,
  // Zermatt 0.89, Montreal 1.20 — which is exactly the right order.
  function fetchClimate() {
    if (!loc || climProc.running) return
    // the archive runs a few days behind live, so end a week back
    var end = new Date(Date.now() - 7 * 86400000)
    var start = new Date(end.getTime() - 365 * 86400000)
    var iso = function (d) {
      var m = d.getMonth() + 1, dd = d.getDate()
      return d.getFullYear() + "-" + (m < 10 ? "0" : "") + m
                             + "-" + (dd < 10 ? "0" : "") + dd
    }
    climProc.command = ["curl", "-fsS", "--max-time", "12",
      "https://archive-api.open-meteo.com/v1/archive?latitude=" + loc.lat
      + "&longitude=" + loc.lon
      + "&start_date=" + iso(start) + "&end_date=" + iso(end)
      + "&daily=precipitation_sum,et0_fao_evapotranspiration&timezone=auto"]
    climProc.running = true
  }

  // How rugged the country is, and whether there is sea in it — from one call.
  // Nine points, a centre and a ring at roughly 50 km, which describes the
  // skyline you would see rather than the ground under your feet.
  function fetchElevation() {
    if (!loc || elevProc.running) return
    var dLat = 0.45
    // a degree of longitude shrinks toward the poles; keep the ring circular
    var dLon = 0.45 / Math.max(0.20, Math.cos(loc.lat * Math.PI / 180))
    var oct = [[0, 0], [1, 0], [0.71, 0.71], [0, 1], [-0.71, 0.71],
               [-1, 0], [-0.71, -0.71], [0, -1], [0.71, -0.71]]
    var la = [], lo = []
    for (var i = 0; i < oct.length; i++) {
      var y = Math.max(-89.5, Math.min(89.5, loc.lat + oct[i][0] * dLat))
      var x = loc.lon + oct[i][1] * dLon
      while (x > 180) x -= 360
      while (x < -180) x += 360
      la.push(y.toFixed(4)); lo.push(x.toFixed(4))
    }
    elevProc.command = ["curl", "-fsS", "--max-time", "8",
      "https://api.open-meteo.com/v1/elevation?latitude=" + la.join(",")
      + "&longitude=" + lo.join(",")]
    elevProc.running = true
  }

  function fetchKp() {
    if (kpProc.running) return
    kpProc.running = true
  }

  function saveCache() {
    if (!loc) return
    var payload = { at: Date.now(), loc: loc, fc: fc, kp: kp,
                    ring: ring, elevation: elevation, climate: climate }
    // base64 through argv: no quoting or escaping can go wrong
    cacheWriteProc.command = ["sh", "-c",
      "mkdir -p \"$(dirname \"$1\")\"; printf %s \"$2\" | base64 -d > \"$1\"",
      "sh", cachePath, Qt.btoa(JSON.stringify(payload))]
    cacheWriteProc.running = true
  }

  function loadCache(txt) {
    try {
      var c = JSON.parse(String(txt || ""))
      if (!c || !c.loc) return
      // a cache for somewhere else is not a cache for here
      var want = root.configLoc
      if (want && want.name && c.loc.name
          && String(c.loc.name).toLowerCase() !== want.name.toLowerCase()) {
        refreshSky(true); return
      }
      loc = c.loc; fc = c.fc || null; kp = c.kp || null
      ring = c.ring || null; elevation = c.elevation || 0
      climate = c.climate || null
      lastFetchMs = c.at || 0
      pushSky()
      if (!ring) fetchElevation()
      if (!climate) fetchClimate()
      // the cache says where you were, not where you are
      checkLocation(true)
      if (Date.now() - lastFetchMs >= cacheMaxAgeMs) refreshSky(true)
    } catch (e) { /* a corrupt cache is simply no cache */ }
  }

  function todToDate(todValue) {
    var d = new Date()
    d.setHours(0, 0, 0, 0)
    return new Date(d.getTime() + todValue * 86400000)
  }

  property var slotIds: [-1, -1, -1]
  property var slotBirth: [0, 0, 0]

  // w encodes the slot state for the shader: 1.0 = finger down, 0.0 = dead,
  // negative = -(release time + 1), which is what lets the light spring back
  // over the following moment instead of snapping into place.
  function writeSlot(i, x, y, birth, w) {
    var v = Qt.vector4d(x, y, birth, w)
    if (i === 0) scene.touch0 = v
    else if (i === 1) scene.touch1 = v
    else scene.touch2 = v
  }

  function clearSlots() {
    root.slotIds = [-1, -1, -1]
    root.slotBirth = [0, 0, 0]
    for (var i = 0; i < 3; i++) writeSlot(i, 0, 0, -1000, 0.0)

  }

  function slotFor(pointId) {
    var ids = root.slotIds
    for (var i = 0; i < 3; i++) if (ids[i] === pointId) return i
    return -1
  }

  // a free slot, else the one whose ripple is furthest along
  function claimSlot(pointId) {
    var ids = root.slotIds.slice()
    var oldest = 0
    for (var i = 0; i < 3; i++) {
      if (ids[i] === -1) { ids[i] = pointId; root.slotIds = ids; return i }
      if (root.slotBirth[i] < root.slotBirth[oldest]) oldest = i
    }
    ids[oldest] = pointId
    root.slotIds = ids
    return oldest
  }

  function touchDown(pointId, nx, ny) {
    var i = claimSlot(pointId)
    var births = root.slotBirth.slice()
    births[i] = scene.time
    root.slotBirth = births
    writeSlot(i, nx, ny, scene.time, 1.0)
  }

  function touchMove(pointId, nx, ny) {
    var i = slotFor(pointId)
    if (i < 0) return
    // birth is preserved, so a dragged finger pulls its disturbance along as a
    // wake rather than restarting the ring under itself
    writeSlot(i, nx, ny, root.slotBirth[i], 1.0)
  }

  function touchUp(pointId, nx, ny) {
    var i = slotFor(pointId)
    if (i < 0) return
    var ids = root.slotIds.slice()
    ids[i] = -1
    root.slotIds = ids
    // negative w stamps the release moment; the wave keeps running and the
    // push relaxes out of the way behind it
    writeSlot(i, nx, ny, root.slotBirth[i], -(scene.time + 1.0))
  }

  function open(payloadJson) {
    root.checkLocation(true)
    root.syncTimeOfDay()
    root.opened = true
    root.clearSlots()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "local.borealis-touch")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Location by IP, exactly the chain Omarchy's own weather widget uses.
  Process {
    id: locProc
    command: ["curl", "-fsS", "--max-time", "8", "https://wttr.in/?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          // An IP lookup started before shell.json was read can land after it;
          // without this it would quietly overwrite an explicit location.
          if (root.configLoc) return
          var a = JSON.parse(String(text || "")).nearest_area[0]
          var nl = { lat: parseFloat(a.latitude), lon: parseFloat(a.longitude),
                     name: (a.areaName && a.areaName[0] && a.areaName[0].value) || "",
                     country: (a.country && a.country[0] && a.country[0].value) || "" }
          // a fifth of a degree is roughly 20 km: far enough to be somewhere else
          var moved = !root.loc || Math.abs(nl.lat - root.loc.lat) > 0.2
                                || Math.abs(nl.lon - root.loc.lon) > 0.2
          root.loc = nl
          if (moved) { root.fc = null; root.kp = null; root.ring = null
                       root.climate = null; root._lastPush = -9999 }
          root.fetchForecast(); root.fetchKp()
          if (moved || !root.ring) root.fetchElevation()
          if (moved || !root.climate) root.fetchClimate()
        } catch (e) { /* offline: the scene simply stays as it is */ }
      }
    }
  }

  Process {
    id: fcProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var j = JSON.parse(String(text || ""))
          var h = j.hourly
          root.elevation = parseFloat(j.elevation) || 0
          var sr = root.parseDaylight(j.daily)
          root.fc = { t0: root.hoursFromMidnightLocal(h.time[0]),
                      code: h.weather_code, precip: h.precipitation,
                      cloud: h.cloud_cover, temp: h.temperature_2m,
                      snowfall: h.snowfall, depth: h.snow_depth,
                      soil: h.soil_temperature_0cm,
                      wspd: h.wind_speed_10m, wdir: h.wind_direction_10m,
                      rise: sr.rise, set: sr.set }
          root.pushSky(); root.saveCache()
        } catch (e) {}
      }
    }
  }

  Process {
    id: kpProc
    command: ["curl", "-fsS", "--max-time", "8",
      "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var arr = JSON.parse(String(text || ""))
          var hrs = [], vals = []
          for (var i = 0; i < arr.length; i++) {
            var e = arr[i]
            if (!e || e.kp === undefined) continue
            hrs.push(root.hoursFromMidnightUtc(e.time_tag))
            vals.push(parseFloat(e.kp))
          }
          root.kp = { hrs: hrs, vals: vals }
          root.pushSky(); root.saveCache()
        } catch (e) {}
      }
    }
  }

  Process {
    id: climProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text || "")).daily
          var ps = 0, es = 0
          for (var i = 0; i < d.time.length; i++) {
            ps += d.precipitation_sum[i] || 0
            es += d.et0_fao_evapotranspiration[i] || 0
          }
          if (es <= 0) return
          root.climate = { ai: ps / es }
          root.pushSky(); root.saveCache()
        } catch (e) { /* no archive: the window heuristic stands in */ }
      }
    }
  }

  Process {
    id: elevProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var e = JSON.parse(String(text || "")).elevation
          if (!e || !e.length) return
          var lo = e[0], hi = e[0], sea = 0
          for (var i = 0; i < e.length; i++) {
            var v = e[i] || 0
            if (v < lo) lo = v
            if (v > hi) hi = v
            // the dataset returns 0 over open water; land at exactly sea level
            // is rare enough, and wet enough, that the confusion is harmless
            if (v <= 0.5) sea++
          }
          root.ring = { spread: hi - lo, sea: sea / e.length }
          root.pushSky(); root.saveCache()
        } catch (err) { /* no ring: the scene keeps its default landscape */ }
      }
    }
  }

  // Same geocoder Omarchy's weather panel uses, so no new service is involved.
  Process {
    id: geoProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var r = JSON.parse(String(text || "")).results[0]
          root.loc = { lat: r.latitude, lon: r.longitude, name: r.name,
                       country: r.country || "" }
          root.fetchForecast(); root.fetchKp(); root.fetchElevation(); root.fetchClimate()
        } catch (e) { /* unknown place: fall back to IP */
          if (!locProc.running) locProc.running = true }
      }
    }
  }

  Process { id: cacheWriteProc }

  FileView {
    path: root.cachePath
    printErrors: false
    onLoaded: root.loadCache(text())
    onLoadFailed: root.refreshSky(true)
  }

  Timer {
    interval: root.cacheMaxAgeMs; repeat: true; running: true
    onTriggered: root.refreshSky(true)
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "borealis"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onHeightChanged: root.sceneH = height
    Component.onCompleted: root.sceneH = height

    ShaderEffect {
      id: scene
      anchors.fill: parent
      property real time: 0
      property vector2d resolution: Qt.vector2d(width, height)
      property vector4d stop0: root.stopVec(0)
      property vector4d stop1: root.stopVec(1)
      property vector4d stop2: root.stopVec(2)
      property vector4d stop3: root.stopVec(3)
      property vector4d stop4: root.stopVec(4)
      property vector4d stop5: root.stopVec(5)
      property vector4d skyBase: Qt.vector4d(root.pal.sb[0] / 255, root.pal.sb[1] / 255,
                                             root.pal.sb[2] / 255, 0)
      property vector4d skyAmp: Qt.vector4d(root.pal.sa[0] / 255, root.pal.sa[1] / 255,
                                            root.pal.sa[2] / 255, 0)

      // Touch slots, mirroring the shader's uniforms: xy = position in uv,
      // z = birth stamp on this same `time` clock, w = 1.0 while down. A birth
      // far in the past is the dead sentinel, so an untouched frame needs no
      // writes here at all.
      property vector4d touch0: Qt.vector4d(0, 0, -1000, 0)
      property vector4d touch1: Qt.vector4d(0, 0, -1000, 0)
      property vector4d touch2: Qt.vector4d(0, 0, -1000, 0)

      // Time of day as a fraction of 24 h. Seeded from the real clock each time
      // the overlay opens, then dragged left to right. Deliberately unbounded:
      // letting it run past 1 means a drag through midnight keeps going forward
      // instead of the animation winding back through the whole day. The shader
      // wraps it.
      property real tod: 0
      Behavior on tod {
        NumberAnimation {
          duration: root.todReturning ? 1300 : (root.drifting ? root.driftMs : 110)
          easing.type: root.todReturning ? Easing.InOutSine
                     : root.drifting ? Easing.Linear : Easing.OutCubic
        }
      }
      // the real sky, resolved in QML (see resolveSky)
      property vector4d wx: Qt.vector4d(0, 0, 0, 0)
      property vector4d astro: Qt.vector4d(0.5, root.auroraFloor, 0, 0)
      property vector4d wx2: Qt.vector4d(0.0105, 0, 0, 0)   // wind, gust, fog, lying snow
      property vector4d ice: Qt.vector4d(0, 0, 0, 0)        // frozen lake, verglas
      property vector4d land: Qt.vector4d(0.35, 0.15, 0.25, 0)  // cold, arid, lush, alpine
      // relief, water, sunrise, sunset. The defaults are the constants this
      // replaced: 0.5 relief is the old fixed ridge amplitude, 1.0 water the
      // lake that used to be unconditional, 0.25/0.75 the old six-to-six day.
      property vector4d geo: Qt.vector4d(0.5, 1.0, 0.25, 0.75)
      // `tod` must animate every frame for the sun to move smoothly, but the
      // weather it resolves to changes hourly, so only re-push when the sky has
      // moved a couple of minutes. This is most of the drift's cost.
      onTodChanged: {
        // How fast the vault is turning, for the motion blur. Rises instantly
        // on a flick and is eased back down by the timer below, so a fast scrub
        // smears and a stop clears rather than freezing mid-trail.
        var nowMs = Date.now()
        var dt = (nowMs - root._velMs) / 1000.0
        if (dt > 0.01) {
          root.todVel = Math.max(Math.abs(scene.tod - root._velTod) / dt, root.todVel)
          root._velTod = scene.tod
          root._velMs = nowMs
        }
        if (Math.abs(scene.tod - root._lastPush) > 0.0012) {
          root._lastPush = scene.tod
          root.pushSky()
        }
      }
      fragmentShader: Qt.resolvedUrl("shaders/aurora.frag.qsb")

      // All animation gated on the overlay being open: zero work while dismissed.
      NumberAnimation on time {
        from: 0
        to: 3600
        duration: 3600000
        loops: Animation.Infinite
        running: root.opened
      }
    }

    // mouseEnabled lets a trackpad exercise the same path as the digitiser, so
    // the effect is testable without reaching for the screen.
    MultiPointTouchArea {
      id: touchArea
      anchors.fill: parent
      maximumTouchPoints: 3
      mouseEnabled: true

      // press bookkeeping for the tap-vs-hold decision, first point only
      property int gestureId: -1
      property real gestureStartMs: 0
      property real gestureStartX: 0
      property real gestureStartY: 0
      property bool gestureMoved: false
      // how many fingers were down at once during this gesture, and how many
      // still are — the decision is taken when the last one lifts
      property int activeCount: 0
      property int gestureMaxPoints: 0
      // time is driven relative to where the drag began, so touching near an
      // edge does not jump the sky to a different hour
      property real todStartX: 0
      property real todBase: 0

      function norm(pt, axis) {
        return axis === 0 ? pt.x / Math.max(width, 1) : pt.y / Math.max(height, 1)
      }

      onPressed: function(points) {
        // A second finger arriving while the first is already dragging is the
        // inspect tap. The palette gesture cannot collide with it: that one
        // requires a quick two-finger tap with no movement at all.
        if (touchArea.activeCount >= 1 && touchArea.gestureMoved) root.cycleInspect()
        root.todReturning = false
        root.drifting = false
        readoutHideTimer.stop()
        touchArea.activeCount += points.length
        touchArea.gestureMaxPoints = Math.max(touchArea.gestureMaxPoints, touchArea.activeCount)
        for (var i = 0; i < points.length; i++) {
          var pt = points[i]
          root.touchDown(pt.pointId, norm(pt, 0), norm(pt, 1))
          if (touchArea.gestureId === -1) {
            touchArea.gestureId = pt.pointId
            touchArea.gestureStartMs = Date.now()
            touchArea.gestureStartX = pt.x
            touchArea.gestureStartY = pt.y
            touchArea.gestureMoved = false
            touchArea.todStartX = pt.x
            touchArea.todBase = scene.tod
          }
        }
      }

      onUpdated: function(points) {
        for (var i = 0; i < points.length; i++) {
          var pt = points[i]
          root.touchMove(pt.pointId, norm(pt, 0), norm(pt, 1))
          if (pt.pointId === touchArea.gestureId) {
            var dx = pt.x - touchArea.gestureStartX
            var dy = pt.y - touchArea.gestureStartY
            if (Math.sqrt(dx * dx + dy * dy) > root.dragPx) {
              // the readout appears only once this is a real scrub, not on a
              // bare touch — a resting finger should leave the sky alone
              touchArea.gestureMoved = true
              root.scrubbing = true
              root.refreshReadout()
            }
            // Inverted on purpose: you grab the sky and pull it, the way you
            // scroll content. Dragging left pulls later hours in from the right.
            var slide = (pt.x - touchArea.todStartX) / Math.max(width, 1)
            var want = touchArea.todBase - slide * root.todGain
            var lim = Math.max(root.todMin, Math.min(root.todMax, want))
            if (lim !== want) {
              // Re-anchor at the edge, so reversing the drag responds straight
              // away instead of first having to unwind the overshoot.
              touchArea.todStartX = pt.x
              touchArea.todBase = lim
            }
            scene.tod = lim
          }
        }
      }

      onReleased: function(points) {
        for (var i = 0; i < points.length; i++)
          root.touchUp(points[i].pointId, norm(points[i], 0), norm(points[i], 1))
        touchArea.activeCount = Math.max(0, touchArea.activeCount - points.length)
        if (touchArea.activeCount > 0) return   // still mid-gesture

        var held = Date.now() - touchArea.gestureStartMs
        var quick = !touchArea.gestureMoved && held < root.holdMs
        var fingers = touchArea.gestureMaxPoints
        touchArea.gestureId = -1
        touchArea.gestureMaxPoints = 0

        // Letting go keeps the hour you landed on, so a forecast can actually
        // be read. Double tap comes home; see goToNow().
        readoutHideTimer.restart()

        // one quick tap is the way out; two fingers recolours the sky; holding
        // or dragging means "I am playing" and does neither
        if (quick && fingers >= 2) root.cyclePalette()
        else if (quick) { root.tapCount++; tapTimer.restart() }
      }

      onCanceled: function(points) {
        for (var i = 0; i < points.length; i++)
          root.touchUp(points[i].pointId, 0, 0)
        touchArea.activeCount = Math.max(0, touchArea.activeCount - points.length)
        if (touchArea.activeCount === 0) {
          touchArea.gestureId = -1
          touchArea.gestureMaxPoints = 0
        }
      }
    }

    Timer {
      id: tapTimer
      interval: 380; repeat: false
      onTriggered: {
        if (root.tapCount >= 3) root.dismiss()
        else if (root.tapCount === 2) root.goToNow()
        root.tapCount = 0
      }
    }

    Timer {
      id: readoutHideTimer
      interval: 1100; repeat: false
      onTriggered: root.scrubbing = false
    }

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: parent.height * 0.075
      width: parent.width
      spacing: parent.height * 0.008
      // Kept visible while parked away from the present, so a held forecast
      // always says which moment you are looking at.
      opacity: (root.scrubbing || root.inspectMode > 0) ? 1
             : root.awayFromNow ? 0.78 : 0
      Behavior on opacity { NumberAnimation { duration: 280 } }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      color: "#eaf0f8"
      style: Text.Outline
      styleColor: "#66000000"
      font.pixelSize: Math.max(15, root.sceneH * 0.025)
      font.letterSpacing: 0.5
      text: root.readoutLine
    }

    // the day being explored, quieter than the line above it
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      color: "#eaf0f8"
      opacity: 0.62
      style: Text.Outline
      styleColor: "#66000000"
      font.pixelSize: Math.max(11, root.sceneH * 0.0165)
      font.letterSpacing: 0.4
      text: {
        if (!scene) return ""
        var d = Qt.formatDate(root.todToDate(scene.tod), "dddd d MMMM")
        // A city alone means nothing once a VPN can drop you anywhere; the
        // country is dropped rather than shown blank when a lookup lacks it.
        var parts = [d]
        if (root.loc && root.loc.name) parts.push(root.loc.name)
        if (root.loc && root.loc.country) parts.push(root.loc.country)
        return parts.join("   \u00b7   ")
      }
    }

    }

    // A day has a shape, and scrubbing hour by hour never showed it. The strip
    // scrolls under a fixed playhead, so the moment you are looking at is
    // always dead centre.
    Item {
      id: strip
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: parent.height * 0.036
      width: parent.width * 0.52
      height: Math.max(3, parent.height * 0.0042)
      opacity: (root.scrubbing || root.inspectMode > 0 || root.awayFromNow) ? 0.72 : 0
      visible: opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: 280 } }

      readonly property int span: 36                       // hours across
      // Deliberately not bound straight to scene.tod: that re-ran all 36
      // delegates every frame even with the strip hidden, which the idle drift
      // then made continuous.
      property real centre: 0
      Connections {
        target: scene
        function onTodChanged() {
          if (root.scrubbing || root.inspectMode > 0) {
            strip.centre = scene.tod
            root.refreshReadout()
          }
        }
      }
      onOpacityChanged: if (opacity > 0 && scene) centre = scene.tod
      function todAt(i) { return centre + (i - span / 2 + 0.5) / 24.0 }

      // a backing, so the strip reads against glittering water or bright cloud
      Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: height
        color: "#4d000000"
      }

      Row {
        anchors.fill: parent
        Repeater {
          model: strip.span
          Rectangle {
            width: strip.width / strip.span
            height: strip.height
            color: root.stripColour(strip.todAt(index))
            // a brighter edge where one day becomes the next
            Rectangle {
              visible: Math.floor(strip.todAt(index)) !== Math.floor(strip.todAt(index - 1))
              width: 1; height: parent.height
              color: "#4dffffff"
            }
          }
        }
      }

      // where the real clock is, so you always know how far you have wandered
      Rectangle {
        width: 2; height: parent.height * 2.6
        y: -parent.height * 0.8
        color: "#e8c07a"
        visible: x > -2 && x < strip.width + 2
        x: ((root.clockFraction() - strip.centre) * 24.0 / strip.span + 0.5) * strip.width - 1
      }

      // the playhead never moves; the day slides beneath it
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 2; height: parent.height * 3.0
        y: -parent.height * 1.0
        radius: 1
        color: "#f2ffffff"
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        event.accepted = true
        root.dismiss()
      }
    }
  }
}
