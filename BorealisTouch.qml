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

  property var loc: null      // { lat, lon, name }
  property var fc: null       // { t0, code[], precip[], cloud[], temp[] }
  property var kp: null       // { t0, step, vals[] }
  property real lastFetchMs: 0

  // ---- moon: pure arithmetic, no network -----------------------------------
  readonly property real synodicDays: 29.530588853
  readonly property real anomalisticDays: 27.554549878

  function moonAt(date) {
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
    if (c === 45 || c === 48) return { kind: "cloud", label: "Fog" }
    if (c >= 51 && c <= 57) return { kind: "rain", label: "Drizzle" }
    if (c === 61 || c === 63 || c === 65) return { kind: "rain", label: "Rain" }
    if (c === 66 || c === 67) return { kind: "rain", label: "Freezing rain" }
    if (c >= 71 && c <= 77) return { kind: "snow", label: "Snow" }
    if (c >= 80 && c <= 82) return { kind: "rain", label: "Showers" }
    if (c === 85 || c === 86) return { kind: "snow", label: "Snow showers" }
    if (c >= 95) return { kind: "storm", label: "Thunderstorm" }
    return { kind: "cloud", label: "Cloudy" }
  }

  // ---- resolve the whole sky for one moment --------------------------------
  // todValue is hours/24 from *today's* local midnight and may run past 1, so
  // dragging into tomorrow reads tomorrow's forecast.
  function resolveSky(todValue) {
    var hr = todValue * 24.0
    var o = { cloud: 0, rain: 0, snow: 0, storm: 0,
              temp: null, cond: "", kp: null, aurora: auroraFloor, has: false }

    var x = fc ? hr - fc.t0 : -1
    if (fc && fc.code.length > 1 && x >= 0 && x <= fc.code.length - 1) {
      var i = Math.floor(x), f = x - i
      i = Math.max(0, Math.min(fc.code.length - 2, i))
      var lp = function (a) { return a[i] + (a[i + 1] - a[i]) * f }
      o.cloud = Math.max(0, Math.min(1, lp(fc.cloud) / 100))
      o.temp  = lp(fc.temp)
      // codes are categorical: take the nearer sample, never the average
      var k = classifyCode(fc.code[f < 0.5 ? i : i + 1])
      var inten = Math.max(0, Math.min(1, lp(fc.precip) / 2.5))
      if (k.kind === "rain")  o.rain = Math.max(0.28, inten)
      if (k.kind === "snow")  o.snow = Math.max(0.32, inten)
      if (k.kind === "storm") { o.storm = Math.max(0.5, inten); o.rain = Math.max(o.rain, 0.55) }
      o.cond = k.label
      o.has = true
    }

    if (kp && kp.vals.length > 0) {
      var best = 0, bd = 1e9
      for (var j = 0; j < kp.hrs.length; j++) {
        var dd = Math.abs(kp.hrs[j] - hr)
        if (dd < bd) { bd = dd; best = j }
      }
      if (bd < 6) o.kp = kp.vals[best]      // don't claim Kp far outside the data
    }
    o.aurora = auroraProbability(o.kp)
    return o
  }

  // ---- push the resolved sky into the two uniforms -------------------------
  function pushSky() {
    if (!scene) return
    var o = resolveSky(scene.tod)
    var m = moonAt(todToDate(scene.tod))
    scene.wx = Qt.vector4d(o.cloud, o.rain, o.snow, o.storm)
    // apparent size swings with distance; a real event adds emphasis on top
    var emphasis = (1.0 / m.dist - 1.0) * 2.0 + m.event * 0.5
                   + (root.inspectMode === 2 ? 0.5 : 0.0)
    scene.astro = Qt.vector4d(m.phase, o.aurora, root.inspectReveal, emphasis)
  }

  function hoursFromMidnightLocal(iso) {      // "2026-08-27T14:00", local
    var a = String(iso).split("T"), d = a[0].split("-"), t = (a[1] || "0:0").split(":")
    var dt = new Date(parseInt(d[0], 10), parseInt(d[1], 10) - 1, parseInt(d[2], 10),
                      parseInt(t[0], 10), parseInt(t[1] || "0", 10), 0)
    var mid = new Date(); mid.setHours(0, 0, 0, 0)
    return (dt.getTime() - mid.getTime()) / 3600000.0
  }

  function hoursFromMidnightUtc(iso) {        // NOAA time_tag, UTC, no suffix
    var dt = new Date(String(iso).replace(" ", "T") + "Z")
    var mid = new Date(); mid.setHours(0, 0, 0, 0)
    return (dt.getTime() - mid.getTime()) / 3600000.0
  }

  function refreshSky(force) {
    if (!force && Date.now() - lastFetchMs < cacheMaxAgeMs) return
    lastFetchMs = Date.now()
    if (loc) { fetchForecast(); fetchKp() }
    else if (!locProc.running) locProc.running = true
  }

  function fetchForecast() {
    if (!loc || fcProc.running) return
    fcProc.command = ["curl", "-fsS", "--max-time", "10",
      "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + loc.lat + "&longitude=" + loc.lon
      + "&hourly=weather_code,precipitation,cloud_cover,temperature_2m"
      + "&past_days=7&forecast_days=16&timezone=auto"]   // 16 is the API max
    fcProc.running = true
  }

  function fetchKp() {
    if (kpProc.running) return
    kpProc.running = true
  }

  function saveCache() {
    if (!loc) return
    var payload = { at: Date.now(), loc: loc, fc: fc, kp: kp }
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
      loc = c.loc; fc = c.fc || null; kp = c.kp || null
      lastFetchMs = c.at || 0
      pushSky()
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
          var a = JSON.parse(String(text || "")).nearest_area[0]
          root.loc = { lat: parseFloat(a.latitude), lon: parseFloat(a.longitude),
                       name: (a.areaName && a.areaName[0] && a.areaName[0].value) || "" }
          root.fetchForecast(); root.fetchKp()
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
          var h = JSON.parse(String(text || "")).hourly
          root.fc = { t0: root.hoursFromMidnightLocal(h.time[0]),
                      code: h.weather_code, precip: h.precipitation,
                      cloud: h.cloud_cover, temp: h.temperature_2m }
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
          duration: root.todReturning ? 1300 : 110
          easing.type: root.todReturning ? Easing.InOutSine : Easing.OutCubic
        }
      }
      // the real sky, resolved in QML (see resolveSky)
      property vector4d wx: Qt.vector4d(0, 0, 0, 0)
      property vector4d astro: Qt.vector4d(0.5, root.auroraFloor, 0, 0)
      onTodChanged: root.pushSky()
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

        // Ease back to the real time, the short way round: tod is unbounded, so
        // the nearest equivalent of "now" may be a whole day up or down.
        var nowF = root.clockFraction()
        root.todReturning = true
        scene.tod = nowF + Math.round(scene.tod - nowF)
        root.inspectMode = 0
        root.inspectReveal = 0
        readoutHideTimer.restart()

        // one quick tap is the way out; two fingers recolours the sky; holding
        // or dragging means "I am playing" and does neither
        if (quick && fingers >= 2) root.cyclePalette()
        else if (quick) root.dismiss()
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
      id: readoutHideTimer
      interval: 1100; repeat: false
      onTriggered: root.scrubbing = false
    }

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: parent.height * 0.075
      spacing: parent.height * 0.008
      opacity: (root.scrubbing || root.inspectMode > 0) ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 280 } }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      color: "#eaf0f8"
      style: Text.Outline
      styleColor: "#66000000"
      font.pixelSize: Math.max(15, root.sceneH * 0.025)
      font.letterSpacing: 0.5
      text: {
        if (!scene) return ""
        var o = root.resolveSky(scene.tod)
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
    }

    // the day being explored, quieter than the line above it
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      color: "#eaf0f8"
      opacity: 0.62
      style: Text.Outline
      styleColor: "#66000000"
      font.pixelSize: Math.max(11, root.sceneH * 0.0165)
      font.letterSpacing: 0.4
      text: scene ? Qt.formatDate(root.todToDate(scene.tod), "dddd d MMMM") : ""
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
