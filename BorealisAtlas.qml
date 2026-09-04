// Borealis Atlas — a touchscreen sky and weather explorer.
//
// The scene is driven by real data, resolved here and handed to the shader as a
// handful of vec4s: the forecast where you are, the sun rising and setting when
// it really does, the horizon measured from elevation samples taken around you,
// water found rather than assumed, and snow lying above the freezing level. A
// finger drags time through 23 days of it; the shader does no lookups and holds
// no arrays, because the GLSL 120 target it compiles to rejects them.
//
// CREDIT. This is a derivative of marko-builds/borealis (MIT) by Marko
// Stankovic, and far more of it is his than the size of this file suggests:
// 87 of the 92 substantive lines of his Borealis.qml are still here verbatim,
// including the whole palette table below — all five palettes are his colours,
// digit for digit. See LICENSE and the Credits section of README.md.
//
// Dismiss rule: a quick tap dismisses (this is still something you park on a
// screen and must stay trivial to get out of, especially in tablet mode where
// there is no keyboard); press-and-hold past HOLD_MS, or any drag past
// DRAG_PX, is intent to interact and will not dismiss. Any key still dismisses.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // The id this plugin was actually installed under. The shell hands every
  // plugin its own manifest, so this is knowable rather than assumed — and it
  // has to be, because the id doubles as the key for the plugin's own entry in
  // shell.json. Hard-coding it meant that installing under any other id left
  // every setting silently dead: no error, no warning, just a scene that
  // ignored your location and your palette. The literal is only a fallback for
  // a direct load with no manifest injected.
  readonly property string pluginId: (manifest && manifest.id) || "io.github.rma131.borealis-atlas"

  // The single config surface: "palette" on this plugin's entry in
  // ~/.config/omarchy/shell.json, applied live on save (shellConfig is
  // reactive):  "plugins": [{ "id": "io.github.rma131.borealis-atlas",
  // "palette": "ember" }]  — aurora | ember | gold | nord | ice.
  // These five palettes are Marko Stankovic's, carried over from Borealis
  // unchanged — the stop positions, the six RGB triplets each, and the sky base
  // and amplitude tints, digit for digit. He ported them from his own
  // play/aurora.py PALETTES (0-255). They are the reason this looks the way it
  // does; do not "improve" them without saying so.
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
      if (e && e.id === root.pluginId
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
  // A tap may wander a little — 12 px is less than a fingertip shifts on
  // contact, and judging a tap by it meant a deliberate double tap after a drag
  // silently did nothing. But loosening that alone made the opposite failure:
  // the return home firing on mispresses. The missing constraint was never
  // distance-from-its-own-start, it was whether the two taps landed in the
  // *same place*. Two taps a hand's width apart are two separate taps.
  readonly property real tapSlopPx: 22
  readonly property real tapNearPx: 110
  readonly property int multiTapMs: 430
  // Days covered by dragging the full width of the screen. The window is now 23
  // days wide, so at 1.0 crossing it took 23 swipes; 2.5 still leaves about two
  // minutes of forecast per pixel, which is far finer than the hourly data.
  readonly property real todGain: 2.5

  // the clock is the default: whatever time it actually is when you summon it






  function clockFraction() {
    var n = root.nowAtLoc()
    return (n.getHours() * 3600 + n.getMinutes() * 60 + n.getSeconds()) / 86400.0
  }

  function syncTimeOfDay() {
    if (!scene) return
    root.todReturning = false
    root.pinned = false
    // The jump is animated, and the drift ticks on the same cadence — so a
    // tick landing mid-flight reads the intermediate value, writes it back and
    // strands the sky part-way. Seven hours is a big enough jump for that to
    // show. The drift stands off until the animation is done.
    root.settling = true
    settleTimer.restart()
    scene.tod = clockFraction()
    root.refreshReadout()
  }
  property bool settling: false
  Timer { id: settleTimer; interval: 320; onTriggered: root.settling = false }

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
    // `!todReturning` matters as much as `!scrubbing`: a drift tick assigns
    // tod, which cancels the return animation and leaves the sky stranded
    // wherever it had got to. That showed up the moment the return grew long
    // enough to outlive the readout timer.
    running: root.opened && !root.scrubbing && !root.todReturning
             && !root.pinned && !root.settling && root.inspectMode === 0
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
        // Between asking for a place and its forecast arriving, the only
        // honest thing to say is that we are still asking. Quoting the old
        // zone's time under the new place's name is how this got confusing.
        if (root.tzStale)
          return "Fetching " + ((root.loc && root.loc.name) || "the sky") + "\u2026"
        var o = root.sky
        var d = root.todToDate(scene.tod)
        var today = root.midnightAtLoc()
        var dd = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
                             - today.getTime()) / 86400000)
        // beyond tomorrow the date line underneath names the day already
        var tag = dd === -1 ? "Yesterday " : dd === 1 ? "Tomorrow " : ""
        var line = tag + Qt.formatTime(d, "HH:mm")
        // Only when it is not your own clock: naming the zone every time would
        // be noise, and its absence is itself the statement that they agree.
        if (root.tzElsewhere() && root.tzName) line += " " + root.tzName
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
    if (root.scrubbing || root.inspectMode > 0 || root.pinned || root.notice)
      root.readoutLine = buildReadout()
  }

  // Six seconds is long enough to read a line and short enough not to become
  // furniture. Deliberately not pinned: a place change still lets the sky
  // drift on afterwards, the way it always has.
  Timer {
    id: noticeTimer
    interval: 6000
    onTriggered: { root.notice = false; root.refreshReadout() }
  }

  // One finger: two taps come home to today, three leave. A single tap does
  // nothing on purpose — this is a screensaver you can hold a forecast in, so
  // leaving should be deliberate. Any key still exits immediately.
  property int tapCount: 0
  property real lastTapX: -9999
  property real lastTapY: -9999

  property real todReturnMs: 1300
  readonly property int readoutHoldMs: 1100
  property int readoutHold: readoutHoldMs
  // Clears the flag once the sky has actually arrived, so the drift may resume.
  Timer {
    id: returnDone
    interval: root.todReturnMs; repeat: false
    onTriggered: root.todReturning = false
  }
  function goToNow() {
    if (!scene) return
    // Rolling home has to be watchable. This used to snap to the nearest
    // *equivalent* of now — same clock time, still N days out — so the journey
    // was never more than half a day and 1300 ms suited it. Going to the real
    // present made the trip up to twenty times longer at the same duration,
    // which blurred three sunrises past in a little over a second and read as
    // no animation at all. Pace it by the distance instead.
    var dist = Math.abs(scene.tod - clockFraction())
    root.todReturnMs = Math.max(900, Math.min(4200, 600 + 800 * dist))
    root.todReturning = true
    root.drifting = false
    // the real present, not "this hour, still three days out" — which is what
    // rounding to the nearest equivalent of now used to do
    scene.tod = clockFraction()
    root.inspectMode = 0
    root.inspectReveal = 0
    root.scrubbing = true
    // the date rolling back is the point of the animation, so keep it readable
    // for the whole trip rather than hiding a third of the way through
    root.readoutHold = root.todReturnMs + 900
    readoutHideTimer.restart()
    returnDone.restart()
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
      if (e && e.id === root.pluginId && e.auroraFloor !== undefined) {
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
  onHorizonChanged: { _lastPush = -9999; pushSky() }
  onWaterChanged: { _lastPush = -9999; pushSky() }
  onClimateChanged: { _lastPush = -9999; pushSky() }
  // sky angular speed, for motion blur
  property real todVel: 0
  property real _velTod: 0
  property real _velMs: 0
  property real _lastPush: -9999
  // Location, in order of preference: explicit coordinates in shell.json, then
  // a place name there (geocoded once), then IP lookup. Set it per-plugin:
  //   { "id": "io.github.rma131.borealis-atlas", "location": "Reykjavik" }
  //   { "id": "io.github.rma131.borealis-atlas", "latitude": 64.15, "longitude": -21.94 }
  readonly property var configLoc: {
    var cfg = root.shell && root.shell.shellConfig
    var plugins = (cfg && cfg.plugins) || []
    for (var i = 0; i < plugins.length; i++) {
      var e = plugins[i]
      if (!e || e.id !== root.pluginId) continue
      var la = parseFloat(e.latitude), lo = parseFloat(e.longitude)
      if (!isNaN(la) && !isNaN(lo))
        return { lat: la, lon: lo, name: root.capStr(e.location || "Custom", root.maxStrLen) }
      if (e.location) return { name: root.capStr(e.location, root.maxStrLen) }   // geocode it
    }
    return null
  }
  // A place typed in by hand. It outranks shell.json and the IP alike, because
  // it is the only one of the three that was actually asked for.
  property var chosenLoc: null
  // Anything that pins the location: a late IP reply must overwrite neither.
  readonly property var lockedLoc: chosenLoc || configLoc

  property bool searching: false
  property string searchText: ""
  property string searchNote: ""

  function openSearch() {
    root.searching = true
    root.searchText = ""
    root.searchFailed = false; root.searchNote = ""
  }

  // ---- "when": a date, a time, or both -------------------------------------
  // The search line took a place and nothing else, which meant the only way to
  // reach a particular afternoon was to drag for it. It now takes a moment too.
  //
  // Written as `place @ when`, or `place, when`, or either half alone. Without
  // a separator the whole line is read as a moment only if it plainly is one —
  // it carries a digit, or it is one of a short list of words — because there
  // are towns called March and Sunday and a search box should not out-think
  // the person typing into it.
  readonly property var monthAbbr: ["jan","feb","mar","apr","may","jun",
                                    "jul","aug","sep","oct","nov","dec"]
  readonly property var weekdayAbbr: ["sun","mon","tue","wed","thu","fri","sat"]
  readonly property var plainMoments: ["today","tomorrow","yesterday","tonight",
                                       "noon","midday","midnight","morning",
                                       "afternoon","evening","night",
                                       "sunrise","sunset","dawn","dusk"]

  function looksTemporal(q) {
    var t = String(q).toLowerCase().trim()
    if (/\d/.test(t)) return true
    var w = t.split(/\s+/)
    for (var i = 0; i < w.length; i++)
      if (root.plainMoments.indexOf(w[i]) < 0) return false
    return w.length > 0
  }

  function daysUntilWeekday(di) {
    return (di - root.midnightAtLoc().getDay() + 7) % 7
  }

  // A day and a month with no year means the nearest one, which is what a
  // person means in December when they type "3 January".
  function daysUntilDate(y, mon, dom) {
    var mid = root.midnightAtLoc().getTime()
    var years = (y !== null) ? [y]
              : [root.midnightAtLoc().getFullYear() - 1,
                 root.midnightAtLoc().getFullYear(),
                 root.midnightAtLoc().getFullYear() + 1]
    var best = null
    for (var i = 0; i < years.length; i++) {
      var n = Math.round((new Date(years[i], mon, dom, 0, 0, 0, 0).getTime() - mid)
                         / 86400000)
      if (best === null || Math.abs(n) < Math.abs(best)) best = n
    }
    return best
  }

  // Returns { day, frac, solar } or null. One token it does not understand
  // means it understood none of them: a half-read date is worse than no date.
  function parseWhen(q) {
    var toks = String(q).toLowerCase().replace(/,/g, " ").split(/\s+/)
    var day = null, frac = null, solar = null, mon = null, dom = null, year = null
    var seen = 0
    for (var i = 0; i < toks.length; i++) {
      var t = toks[i], m
      if (!t.length) continue
      seen++
      if (t === "today")     { day = 0;  continue }
      if (t === "tomorrow")  { day = 1;  continue }
      if (t === "yesterday") { day = -1; continue }
      if (t === "tonight")   { if (day === null) day = 0; frac = 22 / 24; continue }
      if (t === "noon" || t === "midday") { frac = 0.5;      continue }
      if (t === "midnight")               { frac = 0.0;      continue }
      if (t === "morning")                { frac =  9 / 24;  continue }
      if (t === "afternoon")              { frac = 15 / 24;  continue }
      if (t === "evening")                { frac = 20 / 24;  continue }
      if (t === "night")                  { frac = 23 / 24;  continue }
      if (t === "sunrise" || t === "dawn") { solar = "rise"; continue }
      if (t === "sunset"  || t === "dusk") { solar = "set";  continue }
      m = t.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/)
      if (m) { year = parseInt(m[1], 10); mon = parseInt(m[2], 10) - 1
               dom = parseInt(m[3], 10); continue }
      m = t.match(/^([+-]\d{1,2})d?$/)
      if (m) { day = parseInt(m[1], 10); continue }
      m = t.match(/^(\d{1,2}):(\d{2})$/)
      if (m) { frac = (parseInt(m[1], 10) + parseInt(m[2], 10) / 60) / 24; continue }
      m = t.match(/^(\d{1,2})(?::(\d{2}))?(am|pm)$/)
      if (m) {
        var h = parseInt(m[1], 10) % 12
        if (m[3] === "pm") h += 12
        frac = (h + (m[2] ? parseInt(m[2], 10) / 60 : 0)) / 24; continue
      }
      m = t.match(/^(\d{1,2})h$/)
      if (m) { frac = parseInt(m[1], 10) / 24; continue }
      m = t.match(/^(\d{1,2})(?:st|nd|rd|th)?$/)
      if (m && parseInt(m[1], 10) >= 1 && parseInt(m[1], 10) <= 31) {
        dom = parseInt(m[1], 10); continue
      }
      if (t.length >= 3) {
        var mi = root.monthAbbr.indexOf(t.substring(0, 3))
        if (mi >= 0) { mon = mi; continue }
        var di = root.weekdayAbbr.indexOf(t.substring(0, 3))
        if (di >= 0) { day = root.daysUntilWeekday(di); continue }
      }
      return null
    }
    if (!seen) return null
    // A month with no day, or a day with no month, is not a date — it is far
    // more likely to be a place or a stray number.
    if ((mon === null) !== (dom === null)) return null
    if (mon !== null) day = root.daysUntilDate(year, mon, dom)
    if (day === null && frac === null && solar === null) return null
    return { day: (day === null ? 0 : day), frac: frac, solar: solar }
  }

  // Where the place ends and the moment begins.
  function splitQuery(q) {
    var at = q.indexOf("@")
    if (at >= 0) return { place: q.substring(0, at).trim(),
                          when:  q.substring(at + 1).trim() }
    var c = q.lastIndexOf(",")
    if (c >= 0 && root.parseWhen(q.substring(c + 1).trim()))
      return { place: q.substring(0, c).trim(), when: q.substring(c + 1).trim() }
    if (root.looksTemporal(q) && root.parseWhen(q))
      return { place: "", when: q }
    return { place: q, when: "" }
  }

  // Put the sky on the moment that was asked for. Called straight away when
  // only a date was given, and after the forecast lands when a place was too,
  // because sunrise depends on both the day and where you are standing.
  function applyWhen() {
    var w = root.pendingWhen
    root.pendingWhen = null
    if (!w || !scene) return
    var f = w.frac
    if (w.solar !== null) {
      var o = root.resolveSky(w.day + 0.5)
      f = (w.solar === "rise") ? o.rise : o.set
    }
    if (f === null) f = 0.5          // a bare date means the middle of that day
    var want = w.day + f
    root.todReturning = false
    root.drifting = false
    root.pinned = true
    root.inspectMode = 0
    scene.tod = Math.max(root.todMin, Math.min(root.todMax, want))
    root.notice = true
    noticeTimer.restart()
    root.refreshReadout()
  }

  function submitSearch() {
    var raw = root.searchText.trim()
    if (raw.length === 0) {        // empty means "wherever this machine is"
      root.searching = false
      root.pinned = false
      if (!root.chosenLoc) { root.syncTimeOfDay(); return }
      root.chosenLoc = null
      root.loc = null; root.fc = null; root.kp = null
      root.ring = null; root.climate = null; root.horizon = null; root.water = null
      root._lastPush = -9999
      refreshSky(true)
      return
    }
    var q = root.splitQuery(raw)
    var when = null
    if (q.when.length) {
      when = root.parseWhen(q.when)
      if (!when) { root.searchFailed = true; root.searchNote = "Not a date I know"; return }
      // The window is the fetch's, not the parser's, and saying so beats
      // silently snapping to the nearest edge.
      if (when.day < -7 || when.day > 16) {
        root.searchFailed = true; root.searchNote = "Only 7 days back and 16 forward"
        return
      }
    }
    if (!q.place.length) {
      if (!when) { root.searchFailed = true; root.searchNote = "Nothing to go to"; return }
      root.searching = false
      root.searchFailed = false; root.searchNote = ""
      root.pendingWhen = when
      root.applyWhen()
      return
    }
    root.pendingWhen = when        // applied when that place's forecast lands
    root.searchFailed = false; root.searchNote = "Looking for " + q.place + "…"
    root.geoForSearch = true
    geocode(q.place)
  }

  property bool geoForSearch: false

  // "Nothing found" was shown whatever went wrong, so an outage read as a
  // spelling mistake. The status model already knows the difference.
  function geoFailNote() {
    var h = root.srcOf("geocode")
    if (h === "offline")   return "No connection"
    if (h === "ratelimit") return "The place lookup is busy \u2014 try again in a moment"
    if (h === "timeout")   return "The place lookup is not answering"
    if (h !== "" && h !== "ok") return "Could not reach the place lookup"
    return "Nothing found"
  }
  // Notes that mean "that did not work", so the line can say so in amber
  // rather than in the same calm grey it uses for a hint.
  // Set beside every note rather than inferred from its text: the old
  // string-equality list had already drifted once and would drift again with
  // every new message.
  property bool searchFailed: false

  // editing shell.json re-resolves immediately, which is the point of having it
  // The ring and the climate belong to the old place, not the new one. Leaving
  // them behind showed Phoenix with Montreal's aridity for as long as the
  // archive took to answer — and wrote that pairing into the cache.
  onConfigLocChanged: {
    root.loc = null; root.ring = null; root.climate = null
    root.horizon = null; root.water = null; root.fc = null; root.kp = null
    refreshSky(true)
  }

  // ---- bounds -----------------------------------------------------------
  // Every network read is bounded twice, because a TLS-valid endpoint — or an
  // intermediary that terminates TLS — is not a trusted source of length.
  // curl aborts the transfer itself once the cap is passed (exit 63, and it
  // does so mid-stream, so a chunked reply of undeclared length is bounded
  // too), and the collected text is checked again here before it can reach
  // JSON.parse. Real replies measured at the time of writing: forecast 38 KB,
  // wttr 40 KB, climate 8.6 KB, Kp 6.9 KB, elevation 614 B, geocode 389 B.
  // The caps are an order of magnitude above those, so they bound an attack
  // without being a limit the services can trip by growing normally.
  readonly property int capForecast:  524288
  readonly property int capClimate:   262144
  readonly property int capWttr:      262144
  readonly property int capKp:        131072
  readonly property int capElevation:  65536
  readonly property int capMarine:    131072
  readonly property int capGeocode:    65536
  readonly property int capIp:         32768

  // Cardinalities. We ask for a 23-day hourly window (552 slots) and at most
  // 100 elevation points, so anything beyond these is a malformed reply rather
  // than a longer one, and is refused instead of iterated.
  readonly property int maxSeries: 1200
  readonly property int maxDaily:   400
  readonly property int maxPoints:  128
  readonly property int maxStrLen:  120

  // `--proto =https` pins the scheme so a redirect or a rewritten URL cannot
  // downgrade the transport; curl is never given -L, so it does not follow
  // redirects at all.
  // No --retry. curl counts 429 among its transient errors, so the flag meant
  // that hitting a rate limit answered it with two more requests against the
  // very limiter that had just said no — and five of the seven endpoints here
  // share one host. Retrying is the top-up timer's job below, because only
  // this side knows what a 429 means and how long to wait.
  //
  // It also makes the timeout honest: --max-time is per attempt, so a forecast
  // could take 10 + 2 + 10 + 2 + 10 = 34 s to be known dead while the retry
  // budget that was supposed to cover it expired after 13.
  function curlCmd(seconds, maxBytes, url) {
    return ["curl", "-fsS", "--proto", "=https",
            "--max-time", String(seconds),
            "--max-filesize", String(maxBytes), url]
  }

  // ---- what happened, as opposed to merely that nothing happened -----------
  // Every failure used to arrive at the same place — onStreamFinished with an
  // empty string — and be absorbed by a `return` or an empty catch. A dead
  // network and a malformed reply were indistinguishable by construction, so
  // the honest answer to "is it me or the app" could not be given because
  // nothing in the process knew it either.
  //
  // curl's exit code separates them cleanly, and its stderr carries the HTTP
  // status. That stderr is untrusted input like any other — it echoes the URL
  // back — so it is bounded, matched for three digits, and never rendered.
  function classifyExit(code, errText) {
    if (code === 0) return "ok"
    if (code === 6 || code === 7) return "offline"
    if (code === 28) return "timeout"
    if (code === 63) return "toobig"
    if (code === 35 || code === 60 || code === 77 || code === 91) return "tls"
    if (code === 22) {
      var m = root.capStr(errText, 200).match(/error:?\s*(\d{3})/)
      var h = m ? parseInt(m[1], 10) : 0
      if (h === 429) return "ratelimit"
      if (h >= 500) return "server"
      return "badrequest"
    }
    return "failed"
  }

  // One row per source, so the status line can name what is wrong rather than
  // saying something is.
  property var netStatus: ({})
  property int statusRev: 0
  // A 429 from one Open-Meteo host is a 429 from all of them, so the brake is
  // global rather than per-endpoint.
  property real backoffUntilMs: 0
  function heldBack() { return Date.now() < root.backoffUntilMs }

  function noteExit(src, code, errText, ok) {
    var how = ok ? "ok" : root.classifyExit(code, errText)
    var m = {}
    for (var k in root.netStatus) m[k] = root.netStatus[k]
    m[src] = { how: how, at: Date.now() }
    root.netStatus = m
    root.statusRev++
    if (how === "ratelimit") root.backoffUntilMs = Date.now() + 60000
  }
  // The scene used to fail beautifully: a dead network gave you a default sky
  // and a clock, with nothing anywhere saying so. This is the sentence that
  // was missing — which source is unhappy, and whether it is you or us.
  readonly property string trouble: {
    root.statusRev                      // recompute when a status lands
    if (!root.opened) return ""
    if (root.anySrc("offline"))
      return root.fc ? "No connection \u2014 this is the last sky I have"
                     : "No connection"
    if (root.heldBack())
      return "The weather service is busy \u2014 asking again shortly"
    var f = root.srcOf("forecast")
    if (f === "timeout")   return "The weather service is not answering"
    if (f === "server")    return "The weather service returned an error"
    if (f === "tls")       return "Could not make a secure connection"
    if (f === "toobig" || f === "badrequest")
                           return "The forecast reply was not usable"
    if (!root.fc && root.loc && root.topUps >= 2)
      return "No forecast for " + root.loc.name + " yet"
    var e = root.srcOf("elevation")
    if (e !== "" && e !== "ok" && !root.horizon)
      return "No measured horizon here"
    return ""
  }
  // Shown only once it has persisted: a single hiccup that then succeeds
  // should not flash an alarm across a screensaver.
  property bool troubleShown: false
  onTroubleChanged: {
    if (root.trouble === "") { root.troubleShown = false; troubleDelay.stop() }
    else troubleDelay.restart()
  }
  Timer { id: troubleDelay; interval: 5000; onTriggered: root.troubleShown = true }

  function srcOf(src) {
    var e = root.netStatus[src]
    return e ? e.how : ""
  }
  function anySrc(how) {
    for (var k in root.netStatus)
      if (root.netStatus[k] && root.netStatus[k].how === how) return true
    return false
  }

  // A parse that cannot be made to consume memory or to hand back something
  // shaped differently than expected. Overflow is a controlled failure: null,
  // which every caller already treats as "no data".
  function boundedParse(text, maxBytes) {
    var s = String(text || "")
    if (s.length === 0 || s.length > maxBytes) return null
    try {
      var v = JSON.parse(s)
      return (v && typeof v === "object") ? v : null
    } catch (e) { return null }
  }

  function capStr(v, n) {
    var s = (v === null || v === undefined) ? "" : String(v)
    return s.length > n ? s.substring(0, n) : s
  }

  // Rejects NaN and Infinity as well as out-of-range, so a reply cannot put a
  // non-finite number into a uniform and blank the scene.
  function finiteIn(v, lo, hi) {
    var n = parseFloat(v)
    return (isFinite(n) && n >= lo && n <= hi) ? n : null
  }

  function capArray(a, n) {
    if (!Array.isArray(a)) return null
    return a.length > n ? null : a       // too long is malformed, not truncatable
  }

  // Counting the elements is not checking them. These values go on to reach
  // arithmetic, Date construction, loop bounds and shader uniforms, and a
  // string or a NaN in one slot of one series surfaces a long way from here —
  // as a blank overlay, or a scrub that walks off the end of a day. So every
  // element that is consumed is checked for type and for a plausible range,
  // and a single bad one rejects the whole reply rather than being skipped:
  // a series with a hole in it is not a series this scene can index.
  function numArray(a, n, lo, hi, nullsOk) {
    if (!Array.isArray(a) || a.length > n) return null
    for (var i = 0; i < a.length; i++) {
      var v = a[i]
      if (v === null || v === undefined) { if (nullsOk) continue; return null }
      if (typeof v !== "number" || !isFinite(v) || v < lo || v > hi) return null
    }
    return a
  }

  function strArray(a, n, maxLen) {
    if (!Array.isArray(a) || a.length > n) return null
    for (var i = 0; i < a.length; i++) {
      var v = a[i]
      if (typeof v !== "string" || v.length > maxLen) return null
    }
    return a
  }

  // A location is two coordinates and two names, and it is used to build
  // request URLs, so it is canonicalised rather than trusted wherever it comes
  // from — the IP lookup, the geocoder, or a cache file on disk.
  function validLoc(o) {
    if (!o || typeof o !== "object") return null
    var la = root.finiteIn(o.lat !== undefined ? o.lat : o.latitude, -90, 90)
    var lo = root.finiteIn(o.lon !== undefined ? o.lon : o.longitude, -180, 180)
    if (la === null || lo === null) return null
    return { lat: la, lon: lo,
             name: root.capStr(o.name, root.maxStrLen),
             country: root.capStr(o.country, root.maxStrLen) }
  }

  property var loc: null      // { lat, lon, name, country }
  // The clock belongs to the place you are looking at, not to the machine you
  // are looking from. Everything in the scene already did — the forecast is
  // fetched with timezone=auto, so its hours are Istanbul's hours — but `tod`
  // was seeded from the local wall clock, which put Istanbul's data under
  // Montreal's sun. utc_offset_seconds comes back on the same reply the hours
  // do, so the two can never disagree.
  // Null means "not known yet", which behaves exactly as this did before: the
  // machine's own clock, unshifted.
  property var tzOffset: null       // seconds east of UTC, at the target
  property string tzName: ""        // e.g. "GMT+3", for the readout
  // True from the moment the place changes until that place's forecast lands.
  // Until then the clock on screen is still the one you came from, so the
  // readout says it is fetching rather than quoting a time it knows is wrong.
  property bool tzStale: false
  // The clock follows the zone, always. Catching every moment that ought to
  // re-seed it — the cache landing, the overlay opening, the forecast
  // arriving, the place changing — meant four orderings to get right and one
  // of them was always wrong. This is the invariant instead: if the zone the
  // scene is drawn in changes and you are not holding a moment yourself, the
  // clock moves to that zone's now.
  onTzOffsetChanged: {
    if (root.pendingWhen) return          // a date was asked for; it wins
    if (root.scrubbing || root.todReturning || root.pinned) return
    if (root.inspectMode !== 0) return
    root.syncTimeOfDay()
  }
  // A moment you asked for, as against one the drift wandered to. It holds the
  // sky still and keeps the readout up: a date you typed is a question, not
  // ambience, and it should not slide out from under you while you read it.
  property bool pinned: false
  // Something just changed that you should be told about — the place, or the
  // date. Shows the readout for a few seconds without pinning anything.
  property bool notice: false
  // Parsed out of the search line and applied once the forecast for that place
  // is here, because sunrise is a property of the day and the place.
  property var pendingWhen: null

  // Milliseconds to add to a real instant to get a Date whose *local* getters
  // read the target's wall clock. getTimezoneOffset() is read now rather than
  // cached because it is itself daylight-saving dependent.
  function tzShiftMs() {
    if (root.tzOffset === null) return 0
    return root.tzOffset * 1000 + new Date().getTimezoneOffset() * 60000
  }
  function nowAtLoc() { return new Date(Date.now() + root.tzShiftMs()) }
  function midnightAtLoc() {
    var d = root.nowAtLoc()
    d.setHours(0, 0, 0, 0)
    return d
  }
  // True when the place you are looking at is not on your own clock, which is
  // the only time the readout needs to say which clock it is quoting.
  function tzElsewhere() {
    return root.tzOffset !== null
        && Math.abs(root.tzShiftMs()) > 60000
  }

  // Every request carries the generation of the place it was made for. A reply
  // that arrives for a place you have already left is not late data, it is
  // wrong data: it would file Toronto's forecast under Istanbul's name.
  property int locGen: 0
  property real _genLat: 1e9
  property real _genLon: 1e9

  // A fetch already in flight makes the next one a no-op, which is exactly
  // backwards when the reason for the next one is that you have moved: typing
  // a new place while the old place's forecast was still on the wire silently
  // dropped the new one, and the scene kept the old sky, the old clock and no
  // forecast at all.
  //
  // Killing the running request and restarting it in the same turn is not
  // reliable — a false-then-true on `running` can collapse to no change — so
  // the old one is left to finish and its reply discarded by generation, and
  // the top-up below re-asks. A second and a half late is not a problem; the
  // wrong city's weather is.
  function beginFetch(p) { p.gen = root.locGen }
  function stale(p) { return p.gen !== root.locGen }

  // What the place you are looking at still owes you. Also covers a request
  // that simply failed — a timeout or a rate limit used to leave a hole until
  // the next refresh, which for the horizon meant no horizon at all.
  readonly property bool dataMissing:
    loc !== null && (fc === null || kp === null || climate === null
                     || horizon === null || water === null || !marineAsked)
  property int topUps: 0
  property real nextTopUpMs: 0
  // Asked once per place: a coastline does not move, and a null answer is as
  // final as a positive one.
  property bool marineAsked: false
  // Returns whether anything was actually asked for, so the budget counts
  // requests issued rather than timer ticks — the old one spent its whole
  // allowance on no-ops while the first request was still on the wire.
  function topUp() {
    if (!loc || root.heldBack()) return false
    var did = false
    if (!fc && !fcProc.running)        { fetchForecast(); did = true }
    if (!kp && !kpProc.running)        { fetchKp();       did = true }
    if (!climate && !climProc.running) { fetchClimate();  did = true }
    if ((!horizon || !water)
        && !elevProc.running && !fanProc.running && !nearProc.running)
      { fetchHorizon(); did = true }
    if (!marineAsked && !marineProc.running) { fetchMarine(); did = true }
    return did
  }
  Timer {
    interval: 1000; repeat: true
    // Bounded, so a place the elevation service will not answer for costs six
    // tries and then stops rather than hammering it for as long as you look.
    running: root.opened && root.dataMissing && root.topUps < 6
    onTriggered: {
      if (Date.now() < root.nextTopUpMs) return
      if (!root.topUp()) return
      root.topUps++
      // 2.5, 5, 10, 20, 40, 60 s — about two and a half minutes of patience
      // against a ten second request, where it used to be thirteen seconds.
      root.nextTopUpMs = Date.now()
                       + Math.min(2500 * Math.pow(2, root.topUps - 1), 60000)
    }
  }

  onLocChanged: {
    if (!loc) return
    if (Math.abs(loc.lat - root._genLat) < 1e-6
        && Math.abs(loc.lon - root._genLon) < 1e-6) return
    root._genLat = loc.lat; root._genLon = loc.lon
    root.locGen++
    root.topUps = 0
    // Everything below is a property of where you were.
    root.fc = null; root.kp = null; root.ring = null
    root.climate = null; root.horizon = null; root.water = null
    root.elevation = 0
    root._lastPush = -9999
    // The zone on screen is still the old one until the new forecast lands,
    // and the readout says as much rather than quoting a time it knows is
    // wrong. This is also what makes the arrival re-seed the clock even when
    // two places happen to share an offset.
    // Whatever we already know about this ground, before asking for any of it
    // again. A revisit costs a forecast and a Kp index, not seven requests.
    root.restoreTerrain()
    root.tzStale = true
    root.notice = true
    noticeTimer.restart()
    root.refreshReadout()
  }

  property real elevation: 0
  property var ring: null     // { spread (m across ~50 km), sea (0..1) }
  property var climate: null  // { ai } — a year of P / PET
  // { coef[12] the cosine fit, maxAng the highest thing in frame in degrees,
  //   base the altitude the ridge stands on and span the metres from there to
  //   its highest point — which is what turns a freezing level into a snowline }
  property var horizon: null
  // { level m, kind 0 none / 1 river / 2 lake / 3 sea, frac, az, dist }
  property var water: null

  // The shader's WATERLINE. Where the land stands and the water begins are the
  // same line in this scene, so QML has to agree with it to place a near bank.
  readonly property real waterline: 0.82

  // Where trees stop, which is not a fixed altitude: about 3500 m at the
  // equator, falling roughly 40 m per degree of latitude. Quito sits at 2920 m
  // and is therefore below its own treeline and green, while the top of
  // Pichincha is above it and bare — which the old sea-level `alpine` had
  // exactly backwards, drawing the whole city as grey rock.
  readonly property real treeline: 3500.0 - 40.0 * (loc ? Math.abs(loc.lat) : 45)

  // What the land here is like, from what the forecast already tells us: how
  // cold, how dry, how high, how lush. Four scalars the shader blends between,
  // rather than a list of named biomes — the world does not have hard edges.
  // A function, not a binding: as a `readonly property var` this evaluated once
  // while fc was still null and never re-ran, so every place on earth came out
  // with the same default terrain.
  function computeTerrain() {
    if (!fc || !fc.temp || !fc.temp.length)
      return { cold: 0.35, arid: 0.15, lush: 0.25, alpine: 0,
               relief: horizon
                 ? Math.pow(Math.max(0, Math.min(1, horizon.maxAng / 20.0)), 0.8)
                 : ring ? Math.max(0, Math.min(1, (ring.spread - 30.0) / 1200.0)) : 0.5,
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
    var alpine = cl((root.elevation - root.treeline) / 900)
    // Vegetation follows water, not warmth: Phoenix is hotter than Montreal and
    // far greener by this measure until the aridity index gets a say. Without
    // it, a desert came out lush 0.45 and the ground was drawn forest green.
    var wet    = climate ? cl((climate.ai - 0.55) / 0.55) : (1.0 - arid)
    var lush   = cl((meanT - 13.0) / 12.0) * wet * (1.0 - alpine)
    // very high latitude thins the treeline regardless of the local average
    cold = Math.max(cold, cl((absLat - 58.0) / 12.0) * 0.85)

    // How high the skyline stands — the apparent angle of the tallest thing in
    // frame, which is what you actually see rather than a spread in metres.
    // Dubai 0.01, Sahara 0.01, Phoenix 0.08, Montreal 0.19, Quito 0.53,
    // Tromso 0.60, Zermatt 1.0. The metre spread is kept as the fallback for
    // as long as the second pass has not landed, and 0.5 beyond that because
    // it reproduces the amplitude the ridge had before any of this was
    // measured, so a failed lookup changes nothing.
    var relief = horizon ? Math.pow(cl(horizon.maxAng / 20.0), 0.8)
               : ring ? cl((ring.spread - 30.0) / 1200.0) : 0.5

    // Water used to be inferred from humidity, because sea shows up in the ring
    // as points at zero elevation and lakes and rivers do not. That gave Quito a
    // lake for being wet. It is now found rather than guessed — see the near
    // field pass — and this is simply whether there is any.
    var water = root.water ? (root.water.kind > 0 ? 1.0 : 0.0)
              : (ring ? cl(ring.sea * 1.6) : 0.0)

    return { cold: cold, arid: arid, lush: lush, alpine: alpine,
             relief: relief, water: water }
  }
  property var fc: null       // { t0, code[], precip[], cloud[], temp[] }
  property var kp: null       // { t0, step, vals[] }
  property real lastFetchMs: 0

  // ---- moon: pure arithmetic, no network -----------------------------------
  // This used to be two counters ticking off a synodic and an anomalistic month
  // from one reference new moon. That is accurate to about half a day in phase,
  // which was fine while the moon was only ever a crescent in the corner — and
  // is not fine now that the moon has to be in the right place to the hour, or
  // an eclipse lands on the wrong evening. So the mean elements are Meeus'
  // (Astronomical Algorithms, ch. 45-47) with the largest periodic terms, which
  // is within about five hours across every eclipse of this decade.
  //
  // The sun's apparent radius is 0.2666 degrees and the moon's mean 0.2596, and
  // that near-equality is the only reason an eclipse is a thing that happens at
  // all. Offsets below are therefore measured in solar radii: the shader owns
  // the drawn size, this owns the angle.
  // The sun's apparent radius, used as the unit everything below is measured
  // in: the shader owns how big a disc is drawn, this owns the angle.
  readonly property real moonSunMean: 0.9737     // mean moon radius / sun radius

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
    // `date` is a wall-clock Date in the target's frame, so it goes back onto
    // the real timeline first: the moon is not in a time zone.
    var T = (date.getTime() - root.tzShiftMs() - Date.UTC(2000, 0, 1, 12, 0))
            / 86400000.0 / 36525.0
    var D  = 297.8501921 + 445267.1114034 * T   // mean elongation
    var M  = 357.5291092 +  35999.0502909 * T   // the sun's mean anomaly
    var Mp = 134.9633964 + 477198.8675055 * T   // the moon's mean anomaly
    var F  =  93.2720950 + 483202.0175233 * T   // argument of latitude
    var sd = function (a) {
      return Math.sin((((a % 360) + 360) % 360) * Math.PI / 180)
    }
    var cd = function (a) {
      return Math.cos((((a % 360) + 360) % 360) * Math.PI / 180)
    }
    var cl = function (v) { return Math.max(0, Math.min(1, v)) }

    // Elongation from the sun: the moon's true longitude less the sun's, which
    // is the mean elongation plus the moon's periodic terms less the sun's
    // equation of centre. The two-term version this replaced was out by up to
    // fourteen hours, and contact in a solar eclipse lasts about two — so the
    // moon has to be right to the minute or the alignment simply never happens
    // on the day it really does. This lands within about two minutes.
    var elong = D
      + 6.288774 * sd(Mp)         + 1.274027 * sd(2 * D - Mp)
      + 0.658314 * sd(2 * D)      + 0.213618 * sd(2 * Mp)
      - 2.099718 * sd(M)          - 0.114332 * sd(2 * F)
      + 0.058793 * sd(2 * D - 2 * Mp)  + 0.057066 * sd(2 * D - M - Mp)
      + 0.053322 * sd(2 * D + Mp)      + 0.045758 * sd(2 * D - M)
      - 0.040923 * sd(M - Mp)          - 0.034720 * sd(D)
      - 0.030383 * sd(M + Mp)          + 0.015327 * sd(2 * D - 2 * F)
      - 0.012528 * sd(Mp + 2 * F)      + 0.010980 * sd(Mp - 2 * F)
      + 0.010675 * sd(4 * D - Mp)      + 0.010034 * sd(3 * Mp)
      + 0.008548 * sd(4 * D - 2 * Mp)  - 0.019993 * sd(2 * M)
    var phase = (((elong % 360) + 360) % 360) / 360.0            // 0 new, .5 full

    // How far off the sun's own track it runs. The orbit is tilted about five
    // degrees, so most new moons pass well above or below the sun and nothing
    // happens — which is the entire reason an eclipse is rare rather than
    // monthly, and why this cannot be faked with the phase alone.
    var lat = 5.128122 * sd(F)
            + 0.280602 * sd(Mp + F)      + 0.277693 * sd(Mp - F)
            + 0.173237 * sd(2 * D - F)   + 0.055413 * sd(2 * D - Mp + F)
            + 0.046271 * sd(2 * D - Mp - F) + 0.032573 * sd(2 * D + F)
            + 0.017198 * sd(2 * Mp + F)  + 0.009266 * sd(2 * D + Mp - F)
            + 0.008822 * sd(2 * Mp - F)  + 0.008216 * sd(2 * D - M - F)
            + 0.004324 * sd(2 * D - 2 * Mp - F)

    // Distance in kilometres, which is also the apparent size and therefore
    // decides whether an eclipse is total or leaves a ring showing.
    var rkm = 385000.56
      - 20905.355 * cd(Mp)      - 3699.111 * cd(2 * D - Mp)
      -  2955.968 * cd(2 * D)   -  569.925 * cd(2 * Mp)
      +    48.888 * cd(M)       -    3.149 * cd(2 * F)
      +   246.158 * cd(2 * D - 2 * Mp)  - 152.138 * cd(2 * D - M - Mp)
      -   170.733 * cd(2 * D + Mp)      - 204.586 * cd(2 * D - M)
      -   129.620 * cd(M - Mp)  +  108.743 * cd(D) + 104.755 * cd(M + Mp)

    // The coincidence the whole idea of an eclipse rests on: both discs are
    // almost exactly half a degree wide, and which one is fractionally larger
    // changes from month to month.
    var sdMoon = Math.asin(1737.4 / rkm) * 180 / Math.PI
    var Rau    = 1.000140 - 0.016708 * cd(M) - 0.000139 * cd(2 * M)
    var sdSun  = 0.2665639 / Rau
    var ratio  = sdMoon / sdSun
    var dist   = rkm / 385000.56
    var illum  = (1 - Math.cos(2 * Math.PI * phase)) / 2

    // Offset from the sun in solar radii, the unit the discs are drawn in.
    var dlon = phase * 360.0
    if (dlon > 180.0) dlon -= 360.0
    var gx = dlon / sdSun, gy = -lat / sdSun     // north is up, uv.y runs down
    var gR = Math.sqrt(gx * gx + gy * gy)

    // Everything above is geocentric, and a solar eclipse is not: an observer
    // stands four thousand miles off the centre of the earth and sees the moon
    // displaced by up to its horizontal parallax, about a degree — which is
    // twice its own width and far more than the alignment needs. That is why
    // the geocentric separation at a *total* eclipse is around 0.9 degrees and
    // not zero, and why treating it as zero found no eclipses at all.
    //
    // This scene draws the sky rather than a shadow track, so it shows what the
    // best-placed observer would see: the separation less the parallax, floored
    // at zero. Which puts the threshold at about 1.5 degrees of latitude, and
    // reproduces every solar eclipse of this decade with the right kind — total
    // in 2026 and 2027 and 2028, annular in February of 2026 and 2027 — while
    // leaving the new moons between them alone.
    var par = Math.asin(6378.14 / rkm) * 180 / Math.PI
    var eff = Math.max(0, gR - par / sdSun)
    var k   = gR > 1e-6 ? eff / gR : 0
    var offX = gx * k, offY = gy * k

    // How much of the moon's drawn position that offset accounts for. Away from
    // conjunction it is zero and the moon keeps its ordinary place on the day's
    // arc — which is also what forbids the stylised sky's compressed month from
    // inventing an eclipse out of two bodies that merely look close. Contact
    // needs about two solar radii, so a handover that begins at three cannot
    // clip a real eclipse; the shader ignores anything under 0.55 outright, so
    // the crossfade itself cannot manufacture a shallow false one either.
    var blend = cl((4.5 - eff) / 1.5)
    var solar = cl(1 - eff / (1 + ratio))

    // Lunar: the same geometry against the earth's shadow, which sits exactly
    // opposite the sun and needs no parallax correction because it is out there
    // with the moon. The umbra is about 0.70 degrees of radius at that
    // distance, so the moon is grazed under 0.70 + its own radius and wholly
    // swallowed under 0.70 - it. Falling out of the geometry rather than a
    // hand-set window, this also gets the duration right on its own: three and
    // a half hours of shadow with an hour of totality inside it.
    var dlF  = (phase - 0.5) * 360.0
    var sepF = Math.sqrt(dlF * dlF + lat * lat)
    var umbral = cl((0.70 + sdMoon - sepF) / (2 * sdMoon))

    // a supermoon is a full moon that also happens near perigee
    var nearFull = 1 - Math.min(1, Math.abs(phase - 0.5) / 0.055)
    var nearPeri = 1 - Math.min(1, Math.max(0, dist - 0.955) / 0.030)
    var superness = cl(nearFull * nearPeri)

    var evName = superness > 0.5 ? "Supermoon" : ""
    if (umbral > 0.97)      evName = "Total lunar eclipse"
    else if (umbral > 0.02) evName = "Partial lunar eclipse"
    else if (solar > 0) {
      // total needs the moon to be the larger disc and to clear the sun's limb
      // all the way round; annular is the same statement with the sizes swapped
      if (ratio >= 1.0 && eff <= ratio - 1.0)     evName = "Total solar eclipse"
      else if (ratio < 1.0 && eff <= 1.0 - ratio) evName = "Annular solar eclipse"
      else                                        evName = "Partial solar eclipse"
    }

    return { phase: phase, dist: dist, illum: illum, lat: lat,
             ratio: ratio, offX: offX, offY: offY, blend: blend,
             solar: solar, umbral: umbral,
             // `event` decides whether inspect offers a moon panel and how much
             // emphasis the glow gets, so an eclipse counts as one.
             event: Math.max(superness, solar, umbral),
             name: moonName(phase),
             eventName: evName }
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
              instab: 0, severe: 0, gust: 0,
              snowCover: 0, frozen: 0, verglas: 0, wind: 0,
              rise: 0.25, set: 0.75, flz: null,
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

      // Intensity is no longer floored, so drizzle looks like drizzle. The
      // curve is what lets a downpour read as one: a linear 3 mm/h ceiling
      // saturated at moderate rain, so the 8 mm/h hour of a real cell drew
      // exactly the same rain as an ordinary wet afternoon.
      var mmph     = Math.max(0, lp(fc.precip))
      var wetRate  = Math.min(1, Math.pow(mmph / 8.0, 0.6))
      var snowRate = Math.max(0, Math.min(1, lp(fc.snowfall) / 2.0))
      var wA = kindWeights(fc.code[i]), wB = kindWeights(fc.code[i + 1])
      o.rain  = mixw(wA.rain,  wB.rain)  * Math.min(1, 0.12 + wetRate)
      o.snow  = mixw(wA.snow,  wB.snow)  * Math.min(1, 0.15 + snowRate)
      o.fog   = mixw(wA.fog,   wB.fog)

      // A thunderstorm is a state of the atmosphere, not a label. Toronto on
      // 2 September is the case that made this: a storm everyone outdoors
      // remembers, and the code said 82, "violent rain showers", so nothing in
      // this scene treated it as a storm at all. Asked about that same hour the
      // four global models said 82, 96, 95 and 51 — showers, thunderstorm with
      // hail, thunderstorm, drizzle. They cannot all be right, and picking one
      // is picking a coin toss.
      //
      // But every one of them put CAPE between 1450 and 2840 J/kg and the
      // lifted index between -4.8 and -7.2. That is not a disagreement, that is
      // a severe-thunderstorm atmosphere, and it is what the code is supposed
      // to be a summary of. So the physics decides and the code only votes.
      // 2200 J/kg is a strong cell and a lifted index of -6.5 is the same
      // statement made another way; either alone is enough.
      var cape = lp(fc.cape), li = lp(fc.li)
      var conv = Math.max(0, Math.min(1, Math.max(cape / 2200.0, -li / 6.5)))
      // Instability on its own is just a hot afternoon — Toronto had 2140 J/kg
      // at 14:00 under a clear sky. Something has to actually be falling out of
      // it before any of that is a storm you can see.
      var derived = conv * Math.min(1, wetRate * 1.6)
      o.storm = Math.max(mixw(wA.storm, wB.storm) * Math.min(1, 0.35 + wetRate),
                         derived)
      o.instab = conv
      if (o.storm > 0) o.rain = Math.max(o.rain, o.storm * 0.85)

      // The warning tier. There is no free global feed of official warnings —
      // they are national, and stitching NWS, MeteoAlarm and Environment Canada
      // together would be three more providers for three parts of the world. So
      // this is the threshold rather than the bulletin: Environment Canada and
      // the NWS both issue a severe thunderstorm warning at roughly 90 km/h
      // gusts, and a rainfall warning around 50 mm in an hour. The gust is
      // taken as the strongest of the hours either side, because a damaging
      // gust is a ten-minute event that an hourly sample lands on or misses.
      var gust = Math.max(lp(fc.gust),
                          (fc.gust && i > 0) ? fc.gust[i - 1] : 0,
                          (fc.gust && i + 2 < fc.gust.length) ? fc.gust[i + 2] : 0)
      var sv = Math.max((gust - 60.0) / 40.0,
                        (mmph - 12.0) / 25.0,
                        ((cape - 1500.0) / 1500.0) * Math.min(1, wetRate * 2.0))
      o.severe = Math.max(0, Math.min(1, sv)) * Math.max(o.storm, wetRate)
      // Gustiness as distinct from wind: how much the gust exceeds the steady
      // wind is what makes rain lash rather than slant.
      o.gust = Math.max(0, Math.min(1, (gust - lp(fc.wspd)) / 45.0))

      // The height of the 0 C isotherm, which is where snow starts lying on the
      // mountains whatever it is doing down here. Not every model carries it —
      // Tromso comes back 48/48 null with units "undefined" — so where it is
      // missing it is estimated from the surface temperature and the standard
      // 6.5 C/km lapse rate. Checked where both exist: Montreal 3153 m against
      // 3291 measured, Quito 5228 against 4925. Good to a few hundred metres,
      // which is well inside what a painted snowline needs.
      var fa = fc.flz ? fc.flz[i] : null, fb = fc.flz ? fc.flz[i + 1] : null
      o.flz = (fa !== null && fa !== undefined && fb !== null && fb !== undefined)
            ? fa + (fb - fa) * f
            : (o.temp !== null ? root.elevation + o.temp / 0.0065 : null)

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
      // If the atmosphere is holding a thunderstorm the readout should say so,
      // whatever the code called it — otherwise the sky flashes and the line
      // underneath it reads "Showers".
      if (o.severe > 0.35)     o.cond = "Severe thunderstorm"
      else if (o.storm > 0.45) o.cond = "Thunderstorm"
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
                       instab: 0, severe: 0, gust: 0,
                       frozen: 0, verglas: 0, wind: 0, temp: null, cond: "",
                       kp: null, aurora: 0.12, has: false })

  function pushSky() {
    if (!scene) return
    var o = resolveSky(scene.tod)
    root.sky = o
    var m = moonAt(todToDate(scene.tod))
    scene.wx = Qt.vector4d(o.cloud, o.rain, o.snow, o.storm)
    // Emphasis is now glow only: the disc's size is its real size, carried by
    // ecl.w, because two bodies that are the same size in the sky have to be
    // the same size on the screen or neither can hide the other.
    var emphasis = (1.0 / m.dist - 1.0) * 2.0 + m.event * 0.5
    scene.astro = Qt.vector4d(m.phase, o.aurora, root.inspectReveal, emphasis)
    // Where the moon is with respect to the sun, in solar radii, and how much
    // of its drawn position that accounts for. See moonCompute().
    scene.ecl = Qt.vector4d(m.offX, m.offY, m.blend, m.ratio)
    scene.umbra = Qt.vector4d(m.umbral, root.inspectMode === 2 ? root.inspectReveal : 0,
                              0, 0)
    scene.sev = Qt.vector4d(o.instab, o.severe, 0, 0)
    // A dead-still sky looks broken rather than calm, so the drift has a floor.
    var w = o.has ? o.wind : 0.0105
    if (Math.abs(w) < 0.0025) w = 0.0025
    scene.wx2 = Qt.vector4d(w, o.gust, o.fog, o.snowCover)
    scene.ice = Qt.vector4d(o.frozen, o.verglas, root.todVel, 0)
    var tr = root.computeTerrain()
    scene.land = Qt.vector4d(tr.cold, tr.arid, tr.lush, tr.alpine)
    scene.geo = Qt.vector4d(tr.relief, tr.water, o.rise, o.set)

    var c = root.horizon ? root.horizon.coef : root.defaultHills
    scene.hills0 = Qt.vector4d(c[0], c[1], c[2],  c[3])
    scene.hills1 = Qt.vector4d(c[4], c[5], c[6],  c[7])
    scene.hills2 = Qt.vector4d(c[8], c[9], c[10], c[11])

    // How tall the ridge stands on screen. Both ends are the old hard-coded
    // range's, kept deliberately: even flat country has a horizon you can see,
    // and the Alps walling off the sky was a bug once already — this is a
    // skyline, and the sky is most of what it is for.
    // Dubai lands at 0.062, Montreal 0.096, Quito 0.211, Zermatt 0.26.
    var rise = 0.06 + 0.20 * tr.relief

    // Both lines start off the top of the land, which is the same as absent —
    // no separate flag, and a place with no profile yet simply has no snowline
    // rather than an arbitrary one.
    var snowF = 2.0, treeF = 2.0
    var hz = root.horizon
    if (hz && hz.span > 0) {
      if (o.flz !== null && o.flz !== undefined)
        snowF = (o.flz - hz.base) / hz.span
      treeF = (root.treeline - hz.base) / hz.span
    }
    // Softness in uv. Wider than a pixel so the line does not crawl, tight
    // enough that it reads as a line and not as a gradient.
    scene.alt = Qt.vector4d(snowF, treeF, rise, 0.006)

    // How far toward you the water comes, which is the one number that carries
    // the difference between a river, a lake and an ocean. A river is a band
    // with a bank in front of it; a lake reaches nearly all the way in; an
    // ocean fills the foreground. At the waterline exactly there is none, and
    // the shader's water branch never runs.
    var kind = root.water ? root.water.kind : 0
    var bank = root.waterline, wave = 1.0, mirror = 3.2
    if (kind === 1)      { bank = 0.900; wave = 0.55; mirror = 2.2 }  // river
    else if (kind === 2) { bank = 0.965; wave = 1.00; mirror = 3.2 }  // lake
    else if (kind === 3) { bank = 1.000; wave = 1.50; mirror = 4.2 }  // sea
    scene.shore = Qt.vector4d(bank, wave, mirror, 0)
  }

  function hoursFromMidnightLocal(iso) {      // "2026-08-27T14:00", local
    var a = String(iso).split("T"), d = a[0].split("-"), t = (a[1] || "0:0").split(":")
    var dt = new Date(parseInt(d[0], 10), parseInt(d[1], 10) - 1, parseInt(d[2], 10),
                      parseInt(t[0], 10), parseInt(t[1] || "0", 10), 0)
    // Both sides are in the target's wall clock: the ISO string because the
    // forecast was fetched with timezone=auto, and midnight because it is
    // taken there too. Measuring one against the machine's midnight is what
    // offset the whole 23-day window by the difference between the two zones.
    return (dt.getTime() - root.midnightAtLoc().getTime()) / 3600000.0
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

  // NOAA time_tag is a real instant in UTC. Kp is a global number, but *when*
  // it applies is local — so the instants are kept and the hours derived from
  // them, rather than baked in at parse time. Baking them in meant a reply that
  // arrived before the forecast was measured against the zone we were leaving,
  // and an eight-hour error puts the aurora on the wrong side of the night.
  function epochOfUtc(iso) {
    return new Date(String(iso).replace(" ", "T") + "Z").getTime()
  }
  function rebuildKpHours() {
    if (!kp || !kp.ms) return
    var mid = root.midnightAtLoc().getTime(), sh = root.tzShiftMs()
    var h = []
    for (var i = 0; i < kp.ms.length; i++)
      h.push((kp.ms[i] + sh - mid) / 3600000.0)
    root.kp = { ms: kp.ms, vals: kp.vals, hrs: h }
  }

  // lastFetchMs is when data last actually LANDED; lastTryMs is when one was
  // last attempted. Stamping the first before anything succeeded marked a
  // failed refresh as fresh for half an hour.
  property real lastTryMs: 0
  function refreshSky(force) {
    if (!force && Date.now() - lastFetchMs < cacheMaxAgeMs) return
    if (Date.now() - lastTryMs < 5000) return      // re-entry guard, not freshness
    lastTryMs = Date.now()
    if (root.chosenLoc) {
      root.loc = root.chosenLoc
      fetchForecast(); fetchKp(); fetchHorizon(); fetchClimate(); fetchMarine()
      return
    }
    var c = configLoc
    if (c && c.lat !== undefined) {
      root.loc = c; fetchForecast(); fetchKp(); fetchHorizon(); fetchClimate(); fetchMarine(); return
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
    if (lockedLoc) return
    // A lookup already in flight is left alone, but only for as long as curl's
    // own timeout: a wedged one must not disable detection for the session.
    if ((locProc.running || locFallbackProc.running)
        && Date.now() - locStartedMs < 20000) return
    if (!force && Date.now() - lastLocMs < 8000) return
    lastLocMs = Date.now()
    locStartedMs = Date.now()
    locProc.running = true
  }

  function geocode(place) {
    if (geoProc.running || root.heldBack()) return
    geoProc.command = root.curlCmd(8, root.capGeocode,
      // Five rather than one, so a populated place can be preferred over a
      // country's centroid. Typing "Cyprus" used to land on 35N 33E — 689 m up
      // in the Troodos, thirty-five kilometres from any coast — and the scene
      // was then perfectly right to say there was no water.
      "https://geocoding-api.open-meteo.com/v1/search?count=5&language=en&format=json&name="
      + encodeURIComponent(place))
    geoProc.running = true
  }

  function fetchForecast() {
    if (!loc || root.heldBack() || fcProc.running) return
    root.beginFetch(fcProc)
    fcProc.command = root.curlCmd(10, root.capForecast,
      "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + loc.lat + "&longitude=" + loc.lon
      + "&hourly=weather_code,precipitation,cloud_cover,temperature_2m"
      + ",snowfall,snow_depth,soil_temperature_0cm,wind_speed_10m,wind_direction_10m"
      + ",freezing_level_height"
      // What a forecaster actually looks at to call a thunderstorm. See the
      // note in resolveSky(): the weather code is the one field the models
      // disagree about, and these three are the ones they agree on.
      + ",cape,lifted_index,wind_gusts_10m"
      + "&daily=sunrise,sunset,daylight_duration"
      + "&past_days=7&forecast_days=16&timezone=auto")   // 16 is the API max
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
    if (!loc || root.heldBack() || climProc.running) return
    root.beginFetch(climProc)
    // the archive runs a few days behind live, so end a week back
    var end = new Date(Date.now() - 7 * 86400000)
    var start = new Date(end.getTime() - 365 * 86400000)
    var iso = function (d) {
      var m = d.getMonth() + 1, dd = d.getDate()
      return d.getFullYear() + "-" + (m < 10 ? "0" : "") + m
                             + "-" + (dd < 10 ? "0" : "") + dd
    }
    climProc.command = root.curlCmd(12, root.capClimate,
      "https://archive-api.open-meteo.com/v1/archive?latitude=" + loc.lat
      + "&longitude=" + loc.lon
      + "&start_date=" + iso(start) + "&end_date=" + iso(end)
      + "&daily=precipitation_sum,et0_fao_evapotranspiration&timezone=auto")
    climProc.running = true
  }

  // ---- the horizon, measured -------------------------------------------------
  // The skyline used to be three sines with hand-tuned constants, scaled by one
  // relief number, so every place on earth got the same invented range. It is
  // now the country that is actually out there, in two passes of a hundred
  // points — a hundred exactly, because the elevation API takes 100 coordinates
  // and answers 101 with a 400.
  //
  //   pass 1  a centre and 33 azimuths at 4, 11 and 25 km. Does the old job
  //           (spread for relief, points at sea level for water) and says which
  //           way the country rises.
  //   pass 2  20 azimuths across the 150 degrees facing that way, five
  //           distances each. This is the profile that gets drawn.
  //
  // Together they find 4565 m west of Quito — Pichincha, and within 80 m of
  // what this dataset holds anywhere on that massif — and one 177 m swell 2 km
  // west of Montreal, which is Mount Royal and nothing else. Pass 2 on its own
  // found only 4007 m, and the merge is what makes the snow work: it is the
  // last few hundred metres that the freezing level actually crosses.
  readonly property var hzRings: [4000, 11000, 25000]
  readonly property int hzAz: 33
  readonly property var hzFan: [2500, 6000, 11000, 18000, 27000]
  readonly property int hzFanAz: 20
  readonly property real hzFov: 150.0
  // twice the earth's radius with the standard 7/6 optical correction, so a
  // distant summit is not pushed below the horizon by curvature it does not
  // visually suffer
  readonly property real hzTwoR: 14865667.0
  // The cosine fit of the ridge that used to be hard-coded, at its old mid
  // relief and rescaled to the height this draws it at. Nothing but a fallback:
  // it is what shows before the first pass answers, and what stays if it never
  // does.
  readonly property var defaultHills: [
     0.7376,  0.0982, -0.0576,  0.0779,
    -0.0566, -0.0229,  0.0079,  0.0035,
    -0.0001,  0.0022, -0.0007,  0.0015]

  function offsetLL(lat, lon, d, azDeg) {
    var a = azDeg * Math.PI / 180
    var la = lat + (d * Math.cos(a)) / 111320.0
    var lo = lon + (d * Math.sin(a))
                 / (111320.0 * Math.max(0.05, Math.cos(lat * Math.PI / 180)))
    la = Math.max(-89.5, Math.min(89.5, la))
    while (lo > 180) lo -= 360
    while (lo < -180) lo += 360
    return [la, lo]
  }

  // How high something d metres away and h metres up appears to stand. This
  // decides which way to face and how tall to draw the whole ridge — 177 m of
  // Mount Royal at 2 km reads as 2.3 degrees, a 4565 m Pichincha at 11 km as
  // 14. It deliberately does not decide the ridge's shape: see the fan handler.
  function apparentDeg(h, h0, d) {
    return Math.atan2(h - h0 - d * d / root.hzTwoR, d) * 180 / Math.PI
  }

  function elevationUrl(la, lo) {
    return "https://api.open-meteo.com/v1/elevation?latitude=" + la.join(",")
         + "&longitude=" + lo.join(",")
  }

  function fetchHorizon() {
    if (!loc || root.heldBack() || elevProc.running) return
    root.beginFetch(elevProc)
    var la = [loc.lat.toFixed(4)], lo = [loc.lon.toFixed(4)]
    for (var k = 0; k < root.hzAz; k++) {
      var az = 360.0 * k / root.hzAz
      for (var r = 0; r < root.hzRings.length; r++) {
        var pt = root.offsetLL(loc.lat, loc.lon, root.hzRings[r], az)
        la.push(pt[0].toFixed(4)); lo.push(pt[1].toFixed(4))
      }
    }
    elevProc.command = root.curlCmd(8, root.capElevation, root.elevationUrl(la, lo))
    elevProc.running = true
  }

  property real hzH0: 0        // eye height: the ground, or the water you stand on
  // Every sample the earlier passes took, as metres east and north of the place
  // and an elevation — [dx, dy, h, dx, dy, h, ...]. Kept because pass 2 samples
  // only a slice of the compass at its own distances, and 200 more looks at the
  // same ground cost nothing. Offsets rather than coordinates because the
  // viewpoint may not be the place: they are re-projected onto wherever it is.
  property var hzPts: null
  property real hzAim: 0       // the azimuth the view faces
  property real hzTerrainAim: 0   // where the country rises, from pass 1
  property real hzVx: 0        // the viewpoint, as metres east and north
  property real hzVy: 0
  property var hzRingsUsed: null

  // Where the eye stands and which way it looks. Given water, that is the far
  // side of it looking back — the picture this scene has always been composing
  // is a view across water toward land, and standing anywhere else fights it.
  function fetchHorizonFan(vx, vy, centreAz, rings) {
    if (!loc || root.heldBack() || fanProc.running) return
    root.beginFetch(fanProc)
    var vd = Math.sqrt(vx * vx + vy * vy)
    var vlat = loc.lat, vlon = loc.lon
    if (vd > 1.0) {
      var pv = root.offsetLL(loc.lat, loc.lon, vd,
                             Math.atan2(vx, vy) * 180 / Math.PI)
      vlat = pv[0]; vlon = pv[1]
    }
    var la = [], lo = []
    for (var j = 0; j < root.hzFanAz; j++) {
      var az = centreAz - root.hzFov * 0.5
             + root.hzFov * j / (root.hzFanAz - 1)
      for (var r = 0; r < rings.length; r++) {
        var pt = root.offsetLL(vlat, vlon, rings[r], az)
        la.push(pt[0].toFixed(5)); lo.push(pt[1].toFixed(5))
      }
    }
    root.hzAim = centreAz; root.hzVx = vx; root.hzVy = vy
    root.hzRingsUsed = rings
    fanProc.command = root.curlCmd(8, root.capElevation, root.elevationUrl(la, lo))
    fanProc.running = true
  }

  // ---- pass 3, the near field ------------------------------------------------
  // A hundred points on a 12 km square, 1.3 km apart. Two jobs: find the water,
  // and give the viewpoint somewhere to stand.
  //
  // Water is found by the one thing that makes it unmistakable in a DEM — it is
  // flat. Copernicus conditions water surfaces to a single exact value, and real
  // terrain essentially never repeats an exact metre, so a repeated value is a
  // water surface. Quito comes back with 95 distinct values out of 100 and no
  // repeats at all, which is how "there is no water here" gets said.
  //
  // Flat farmland is the one confound, and two further properties settle it:
  // water is the LOWEST level present, and it is an isolated spike rather than
  // a smooth cluster. Kansas repeats 508 m seven times, but 507 and 509 are
  // there too and 508 sits at 71% of the local range; Lake Michigan repeats
  // 174 m forty-eight times with nothing at 173 or 175, at the very bottom.
  //
  //   place       level  share  isolation  lowest   -> verdict
  //   New York      0 m    32%       5.9     yes       sea
  //   Chicago     174 m    42%      48.0     yes       lake
  //   Montreal      4 m     6%       2.5     yes       river
  //   Kansas      508 m     7%       0.7     no        dry
  //   Quito         -       -         -       -        dry
  readonly property real nearHalf: 6000.0
  readonly property int nearN: 10

  function fetchNearField() {
    if (!loc || root.heldBack() || nearProc.running) return
    root.beginFetch(nearProc)
    var la = [], lo = []
    for (var i = 0; i < root.nearN; i++) {
      for (var j = 0; j < root.nearN; j++) {
        var dy = root.nearHalf - 2 * root.nearHalf * i / (root.nearN - 1)
        var dx = -root.nearHalf + 2 * root.nearHalf * j / (root.nearN - 1)
        var d = Math.sqrt(dx * dx + dy * dy)
        var pt = root.offsetLL(loc.lat, loc.lon, d < 1.0 ? 1.0 : d,
                               Math.atan2(dx, dy) * 180 / Math.PI)
        la.push(pt[0].toFixed(5)); lo.push(pt[1].toFixed(5))
      }
    }
    nearProc.command = root.curlCmd(8, root.capElevation, root.elevationUrl(la, lo))
    nearProc.running = true
  }

  // No water, or no answer: stand where you are and face whatever rises
  // highest, which is what this did before there was any water in it.
  // ---- water, from any set of samples ---------------------------------------
  // Lifted out of the near-field handler because the near field is not the only
  // place that has already measured the ground. Pass 1 samples a 25 km disc and
  // its elevations are kept anyway, so a lake beyond the near field's 6 km box
  // costs nothing extra to notice — which is what Toronto turned out to need:
  // the geocoder puts it about 7 km inland, so Lake Ontario barely entered the
  // near field and the scene drew a city on the shore of a lake with no water
  // in it at all.
  //
  // The gates are deliberately unchanged. Widening the near grid to reach the
  // lake instead was tried and loses Montreal's river — at more than about
  // 1.4 km spacing the St Lawrence stops repeating an exact metre four times —
  // and loosening them to admit Amsterdam admits drained polder with it, which
  // is the same shape of evidence as Kansas farmland. A false ocean is a much
  // louder failure than a missing river.
  //
  // refArea is what `frac` is measured against. It has to be passed in because
  // the two passes cover very different footprints, and the 0.12 river/lake
  // threshold was calibrated as a share of ground, not a share of samples.
  function findWater(dx, dy, e, refArea, cellArea) {
    var n0 = e.length, i, q
    var count = {}, levels = []
    for (i = 0; i < n0; i++) {
      var v = e[i]
      if (count[v] === undefined) { count[v] = 0; levels.push(v) }
      count[v]++
    }
    levels.sort(function (a, b) { return a - b })
    var at = function (v) { return count[v] === undefined ? 0 : count[v] }

    var lvl = null, best = 0
    for (q = 0; q < levels.length; q++) {
      var v2 = levels[q], n = at(v2)
      if (n < 4) continue
      // an isolated spike, not the shoulder of a smooth cluster
      var isol = n / (1 + at(v2 - 1) + at(v2 + 1) + at(v2 - 2) + at(v2 + 2))
      // and the lowest ground around: water is where water collects
      if (isol >= 1.5 && q <= 1 && n > best) { best = n; lvl = v2 }
    }
    if (lvl === null) return null

    var frac = Math.min(1.0, (best * cellArea) / refArea)
    // Sea is water the DEM conditions to zero, give or take a metre of
    // rounding. Water genuinely below sea level is an inland body — the Dead
    // Sea at -430 m and a Dutch canal at -5 are not oceans filling the whole
    // foreground, which is what a bare `lvl <= 1.0` used to call them.
    var kind = (lvl >= -2.0 && lvl <= 1.0) ? 3 : (frac >= 0.12 ? 2 : 1)

    // Which way it lies, and how far out it reaches along that bearing.
    var sx = 0, sy = 0
    for (i = 0; i < n0; i++)
      if (e[i] === lvl) { sx += dx[i]; sy += dy[i] }
    sx /= best; sy /= best
    var waz = (Math.atan2(sx, sy) * 180 / Math.PI + 360) % 360

    var ds = []
    for (i = 0; i < n0; i++) {
      if (e[i] !== lvl) continue
      var a4 = Math.atan2(dx[i], dy[i]) * 180 / Math.PI
      var rel4 = ((a4 - waz + 540) % 360) - 180
      if (Math.abs(rel4) <= 25)
        ds.push(Math.sqrt(dx[i] * dx[i] + dy[i] * dy[i]))
    }
    ds.sort(function (a, b) { return a - b })
    // The median and not the farthest: the grid is a square, so its corners
    // are 8.5 km out and a river running diagonally across one pushed the
    // viewpoint to the cap and shrank Mount Royal by half.
    var med = ds.length ? ds[Math.floor(ds.length / 2)] : 3000.0
    return { level: lvl, kind: kind, frac: frac, az: waz, dist: med,
             src: "ground" }
  }

  // Ground beats sea-model, then nearer beats further.
  //
  // The ground has measured the actual surface and knows a lake from an ocean;
  // the marine model only knows "there is open water in this nine-kilometre
  // cell", which for Toronto would call Lake Ontario a sea filling the whole
  // foreground when the elevation pass has correctly called it a lake. So the
  // probe is a fallback for the places the ground cannot describe, not a rival
  // to it — and among equals, water at the end of the street beats water on
  // the horizon.
  function adoptWater(w) {
    if (!w) return
    var cur = root.water
    if (!cur || cur.kind === 0) { root.water = w; return }
    var curGround = cur.src !== "marine", newGround = w.src !== "marine"
    if (curGround && !newGround) return
    if (!curGround && newGround) { root.water = w; return }
    if (cur.dist <= w.dist) return
    root.water = w
  }

  // ---- open water, asked rather than inferred -------------------------------
  // The elevation test cannot see Amsterdam. Copernicus conditions the
  // Netherlands' *land* flat too, so the water there is neither the lowest
  // thing around nor an isolated spike — it is a smear from -5 m to +3 m with
  // no repeated surface in it, and the -5 m that does repeat is the
  // Haarlemmermeer polder floor, which is drained farmland and the same shape
  // of evidence as Kansas. Loosening the gates to admit it would light up
  // polder, playa and floodplain worldwide, and a false ocean is a much louder
  // failure than a missing river.
  //
  // So this asks instead of inferring. The marine model answers with a wave
  // height wherever there is open water and with nulls everywhere else, which
  // is a direct statement about sea rather than a guess from the shape of the
  // ground. Same provider as everything else, so no new host to justify.
  // Measured: Limassol, Istanbul and Toronto answer; Quito, Nicosia and
  // Montreal correctly do not; Amsterdam answers 25 km out, which is where the
  // North Sea approaches actually are.
  readonly property var marineRings: [5000.0, 12000.0, 25000.0]
  readonly property int marineAz: 4
  property var marinePts: []

  function fetchMarine() {
    if (!loc || root.heldBack() || marineProc.running) return
    root.beginFetch(marineProc)
    var la = [], lo = [], pts = []
    for (var r = 0; r < root.marineRings.length; r++) {
      for (var k = 0; k < root.marineAz; k++) {
        var az = 360.0 * k / root.marineAz + (r % 2 ? 45.0 : 0.0)
        var d = root.marineRings[r]
        var pt = root.offsetLL(loc.lat, loc.lon, d, az)
        la.push(pt[0].toFixed(4)); lo.push(pt[1].toFixed(4))
        pts.push(d * Math.sin(az * Math.PI / 180), d * Math.cos(az * Math.PI / 180))
      }
    }
    root.marinePts = pts
    root.marineAsked = true
    marineProc.command = root.curlCmd(8, root.capMarine,
      "https://marine-api.open-meteo.com/v1/marine?latitude=" + la.join(",")
      + "&longitude=" + lo.join(",")
      + "&hourly=wave_height&forecast_days=1")
    marineProc.running = true
  }

  function fallbackFan() {
    root.fetchHorizonFan(0, 0, root.hzTerrainAim, root.hzFan.concat([]))
  }

  // Twelve terms of a half-range cosine series. A cosine fit and not a Fourier
  // one on purpose: a Fourier fit forces profile(0) == profile(1) and puts a
  // seam down the edge of the frame. Twelve places the summit within 0.03 of
  // where it belongs and fits in three vec4s; eight was visibly soft.
  function cosineFit(f, terms) {
    var n = f.length, a = [], sum = 0
    for (var i = 0; i < n; i++) sum += f[i]
    a.push(sum / n)
    for (var k = 1; k < terms; k++) {
      var c = 0
      for (var m = 0; m < n; m++) c += f[m] * Math.cos(Math.PI * k * (m + 0.5) / n)
      a.push(2.0 * c / n)
    }
    return a
  }

  // No generation stamp: Kp is one global number, so a reply that arrives for
  // the place you have just left is still perfectly good data. Only *when* it
  // applies is local, and rebuildKpHours() re-derives that on every zone
  // change, which is what actually makes it place-independent.
  function fetchKp() {
    if (kpProc.running || root.heldBack()) return
    kpProc.running = true
  }

  // The cache holds your location and 23 days of where you have been looking,
  // so how it is written matters as much as what is in it.
  //
  // It used to go through argv, which is wrong twice over: /proc/PID/cmdline is
  // world-readable, so any process on the machine could read the payload while
  // the write ran, and a long payload runs into ARG_MAX. It also wrote straight
  // over the destination, which follows a symlink planted at the known path,
  // leaves the file truncated and half-written for a concurrent reader, and
  // lets two saves interleave.
  //
  // Now the payload goes over stdin, the directory is created 0700 and the file
  // 0600, a symlinked or non-regular destination is refused, and the data lands
  // on a same-directory temporary that is flushed and then renamed — atomic on
  // one filesystem, so a reader sees the old file or the new one, never a torn
  // one.
  property string _pendingCache: ""
  // ---- terrain, remembered per place ----------------------------------------
  // The ground does not change. But every visit to a city re-asked for it:
  // three elevation passes, a marine probe and a year of climate normals, five
  // of the seven requests a location change costs. Trying city after city —
  // which is exactly how you use a thing like this — walked straight into the
  // service's rate limit, and because every failure here was silent, the scene
  // just quietly stopped having a horizon.
  //
  // Two decimal places is about 1.1 km. Fine enough that two places never
  // collide, since the near field is 12 km across, and coarse enough to absorb
  // the jitter between successive IP lookups of one address.
  readonly property int maxTerrainPlaces: 24
  readonly property real terrainMaxAgeMs: 90 * 86400000
  property var terrain: ({})

  function terrainKey(l) {
    return l ? (l.lat.toFixed(2) + "," + l.lon.toFixed(2)) : ""
  }

  function validTerrain(t) {
    if (!t || typeof t !== "object" || Array.isArray(t)) return null
    var el = root.finiteIn(t.elevation, -500, 9000)
    var h0 = root.finiteIn(t.hzH0, -500, 9000)
    if (el === null || h0 === null) return null
    var o = { elevation: el, hzH0: h0,
              at: root.finiteIn(t.at, 0, 4102444800000) || 0,
              marineAsked: t.marineAsked === true }
    o.ring = (t.ring && root.finiteIn(t.ring.spread, 0, 9000) !== null
                     && root.finiteIn(t.ring.sea, 0, 1) !== null)
           ? { spread: +t.ring.spread, sea: +t.ring.sea } : null
    o.climate = (t.climate && root.finiteIn(t.climate.ai, 0, 100) !== null)
              ? { ai: +t.climate.ai } : null
    o.horizon = null
    if (t.horizon && root.numArray(t.horizon.coef, 16, -100, 100, false)
                  && t.horizon.coef.length === 12
                  && root.finiteIn(t.horizon.maxAng, -90, 90) !== null
                  && root.finiteIn(t.horizon.base, -500, 9000) !== null
                  && root.finiteIn(t.horizon.span, 0, 9000) !== null)
      o.horizon = { coef: t.horizon.coef, maxAng: +t.horizon.maxAng,
                    base: +t.horizon.base, span: +t.horizon.span }
    o.water = null
    if (t.water && t.water.src !== "marine") t.water.src = "ground"
    if (t.water && root.finiteIn(t.water.kind, 0, 3) !== null
                && root.finiteIn(t.water.level, -500, 9000) !== null
                && root.finiteIn(t.water.frac, 0, 1) !== null
                && root.finiteIn(t.water.az, 0, 360) !== null
                && root.finiteIn(t.water.dist, 0, 60000) !== null)
      o.water = { kind: +t.water.kind, level: +t.water.level, src: t.water.src,
                  frac: +t.water.frac, az: +t.water.az, dist: +t.water.dist }
    return o
  }

  // The keys here are the one part of the cache an attacker could choose, and
  // every Object.prototype name answers a plain lookup in this engine — the
  // palette table above documents the same hazard. So the shape of a key is
  // checked before it is trusted, and every lookup is an own-property lookup.
  readonly property var terrainKeyRe:
    /^-?\d{1,2}(\.\d{1,2})?,-?\d{1,3}(\.\d{1,2})?$/

  function loadTerrain(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return ({})
    var keys = Object.keys(raw)
    if (keys.length > root.maxTerrainPlaces) return ({})   // too many is malformed
    var out = {}, now = Date.now()
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      if (!root.terrainKeyRe.test(k)) continue
      if (!Object.prototype.hasOwnProperty.call(raw, k)) continue
      var v = root.validTerrain(raw[k])
      if (!v) continue
      if (now - v.at > root.terrainMaxAgeMs) continue
      out[k] = v
    }
    return out
  }

  function rememberTerrain() {
    if (!loc) return
    var k = root.terrainKey(loc)
    if (!k) return
    var m = {}
    for (var q in root.terrain)
      if (Object.prototype.hasOwnProperty.call(root.terrain, q)) m[q] = root.terrain[q]
    m[k] = { at: Date.now(), elevation: root.elevation, hzH0: root.hzH0,
             ring: root.ring, climate: root.climate, horizon: root.horizon,
             water: root.water, marineAsked: root.marineAsked }
    // Oldest out first, and trimmed before the payload is built rather than
    // after: saveCache() silently declines to write anything over the cap, so
    // an unbounded map would end up costing us the forecast as well.
    var ks = Object.keys(m)
    while (ks.length > root.maxTerrainPlaces) {
      var oldest = null
      for (var j = 0; j < ks.length; j++)
        if (oldest === null || (m[ks[j]].at || 0) < (m[oldest].at || 0)) oldest = ks[j]
      delete m[oldest]
      ks = Object.keys(m)
    }
    root.terrain = m
  }

  // Everything a place owes us that we may already have. Called when the place
  // changes, before anything is asked for.
  function restoreTerrain() {
    if (!loc) return false
    var k = root.terrainKey(loc)
    if (!Object.prototype.hasOwnProperty.call(root.terrain, k)) return false
    var t = root.terrain[k]
    if (!t) return false
    if (t.ring) root.ring = t.ring
    if (t.climate) root.climate = t.climate
    if (t.horizon) root.horizon = t.horizon
    if (t.water) root.water = t.water
    root.elevation = t.elevation
    root.hzH0 = t.hzH0
    root.marineAsked = t.marineAsked
    t.at = Date.now()
    root._lastPush = -9999
    return true
  }

  function saveCache() {
    if (!loc) return
    var payload = { at: Date.now(), loc: loc, fc: fc, kp: kp,
                    ring: ring, elevation: elevation, climate: climate,
                    horizon: horizon, hzH0: hzH0, water: water,
                    chosen: chosenLoc,
                    terrain: terrain,
                    // without this the cached hours are read against the wrong
                    // midnight for as long as it takes the first fetch to land
                    tz: tzOffset, tzn: tzName }
    root.rememberTerrain()
    payload.terrain = root.terrain
    var b64 = Qt.btoa(JSON.stringify(payload))
    if (b64.length > root.capCache) return   // never write what we would refuse to read
    // Concurrent saves are coalesced rather than raced: a write already in
    // flight keeps only the newest payload and runs again when it finishes.
    if (cacheWriteProc.running) { root._pendingCache = b64; return }
    root._pendingCache = ""
    cacheWriteProc.payload = b64
    cacheWriteProc.command = ["sh", "-c", root.cacheWriteScript, "sh", cachePath,
                              String(b64.length)]
    cacheWriteProc.running = true
  }

  // Written the careful way, because the path is known and another process
  // running as you can sit on it. Ordinary redirection to a predictable
  // `.tmp.$$` can be pre-created as a symlink, and checking the destination by
  // pathname and then renaming by pathname leaves a window in which the parent
  // components can be swapped between the two.
  //
  // So: the directory is verified once and then made the working directory, and
  // every subsequent operation uses a bare filename resolved against it rather
  // than a path that can be re-pointed underneath us. The temporary is created
  // by mktemp, which is exclusive-create with an unpredictable name, so it
  // cannot be pre-planted. A trap removes it on any exit, and only a rename
  // within that one verified directory publishes the result.
  readonly property string cacheWriteScript:
      "set -eu\n"
    + "f=$1\n"
    + "n=$2\n"
    + "d=${f%/*}\n"
    + "b=${f##*/}\n"
    + "umask 077\n"
    + "mkdir -p \"$d\"\n"
    + "if [ -L \"$d\" ]; then exit 1; fi\n"
    + "if [ ! -d \"$d\" ]; then exit 1; fi\n"
    + "chmod 700 \"$d\" 2>/dev/null || true\n"
    + "cd \"$d\" || exit 1\n"
    + "if [ -L \"$b\" ]; then exit 1; fi\n"
    + "if [ -e \"$b\" ] && [ ! -f \"$b\" ]; then exit 1; fi\n"
    + "t=$(mktemp \"./.${b}.XXXXXXXX\") || exit 1\n"
    + "trap 'rm -f \"$t\"' EXIT INT TERM HUP\n"
    // Exactly $2 bytes are read and no more. Waiting for EOF instead hangs:
    // closing the write end of stdin is not something this side can rely on,
    // and a base64 blocked on a pipe that never closes leaves the temporary
    // orphaned and queues every later save behind it forever. An exact count
    // is also a bound in itself — the reader cannot be made to consume more
    // than the writer declared.
    + "head -c \"$n\" | base64 -d > \"$t\"\n"
    + "chmod 600 \"$t\"\n"
    + "sync -d \"$t\" 2>/dev/null || sync\n"
    + "mv -f \"$t\" \"$b\"\n"
    + "trap - EXIT INT TERM HUP\n"

  // The cache is written by this plugin, but it is a file on disk at a known
  // path: it is treated as untrusted input, bounded before it is parsed and
  // shape-checked after. A cache that fails any of this is simply no cache.
  readonly property int capCache: 2097152

  // One definition of "a usable forecast", so the cache cannot install a shape
  // the network path would have refused.
  // A cache file is as untrusted as a reply, and it feeds exactly the same
  // indexing, arithmetic and uniforms — so it gets exactly the same ranges the
  // network path applies rather than a count and the benefit of the doubt.
  readonly property var fcRanges: [
    ["code",      0, 99], ["precip", 0, 1000], ["cloud", 0, 100],
    ["temp",   -120, 80], ["snowfall", 0, 500], ["depth", 0, 100],
    ["soil",  -120, 100], ["wspd",   0,  500], ["wdir",  0, 360]]

  function validFc(f) {
    if (!f || typeof f !== "object") return null
    var n = -1
    for (var i = 0; i < root.fcRanges.length; i++) {
      var r = root.fcRanges[i]
      var a = root.numArray(f[r[0]], root.maxSeries, r[1], r[2], true)
      if (!a || a.length < 2) return null
      if (n < 0) n = a.length
      else if (a.length !== n) return null
    }
    // Optional series: absent is normal — freezing level is missing at some
    // places, and the convective fields are simply not in a cache written
    // before they were fetched. Present and malformed is not normal.
    var opt = [["flz", -1000, 30000], ["cape", -2000, 20000],
               ["li", -40, 60], ["gust", 0, 500]]
    for (var k = 0; k < opt.length; k++) {
      var o = opt[k]
      if (f[o[0]] === null || f[o[0]] === undefined) continue
      var z = root.numArray(f[o[0]], root.maxSeries, o[1], o[2], true)
      if (!z || z.length !== n) return null
    }
    if (root.finiteIn(f.t0, -100000, 100000) === null) return null
    return f
  }

  function loadCache(txt) {
    try {
      var c = root.boundedParse(txt, root.capCache)
      if (!c || !c.loc || typeof c.loc !== "object") return
      var clat = root.finiteIn(c.loc.lat, -90, 90)
      var clon = root.finiteIn(c.loc.lon, -180, 180)
      if (clat === null || clon === null) return
      c.loc = { lat: clat, lon: clon,
                name: root.capStr(c.loc.name, root.maxStrLen),
                country: root.capStr(c.loc.country, root.maxStrLen) }
      // a cache for somewhere else is not a cache for here
      var want = root.configLoc
      if (want && want.name && c.loc.name
          && String(c.loc.name).toLowerCase() !== want.name.toLowerCase()) {
        refreshSky(true); return
      }
      // `chosen` is not decoration: a later refresh installs it over the
      // sanitised location, after which its fields build request URLs and are
      // handed to numeric methods. It gets the same canonicalisation, and is
      // dropped rather than kept if it fails.
      if (c.chosen && !root.configLoc) root.chosenLoc = root.validLoc(c.chosen)
      loc = c.loc
      root.terrain = root.loadTerrain(c.terrain)
      // Restored before fc, for the same reason the network path sets it
      // first: t0 was measured against this zone's midnight.
      var ctz = root.finiteIn(c.tz, -50400, 50400)
      if (ctz !== null) { root.tzOffset = ctz; root.tzName = root.capStr(c.tzn, 12) }
      // Series are re-checked exactly as they are on arrival from the network,
      // because a file can be edited and a cached fc feeds the same indexing.
      fc = root.validFc(c.fc)
      // Instants, not hours: a cache written under another zone would
      // otherwise restore that zone's idea of when tonight is.
      kp = (c.kp && root.numArray(c.kp.ms, root.maxDaily, 0, 4102444800000, false)
                 && root.numArray(c.kp.vals, root.maxDaily, 0, 9, false)
                 && c.kp.ms.length === c.kp.vals.length)
         ? { ms: c.kp.ms, vals: c.kp.vals, hrs: [] } : null
      root.rebuildKpHours()
      ring = (c.ring && root.finiteIn(c.ring.spread, 0, 9000) !== null
                     && root.finiteIn(c.ring.sea, 0, 1) !== null) ? c.ring : null
      elevation = root.finiteIn(c.elevation, -500, 9000) || 0
      climate = (c.climate && root.finiteIn(c.climate.ai, 0, 100) !== null) ? c.climate : null
      // The twelve coefficients go straight into hills0/1/2 as shader
      // uniforms, so a string or a null in one slot is a NaN in a uniform and
      // a blank overlay — which is the exact failure finiteIn() exists to
      // stop. Counting them was never enough.
      horizon = (c.horizon && root.numArray(c.horizon.coef, 16, -100, 100, false)
                           && c.horizon.coef.length === 12
                           && root.finiteIn(c.horizon.maxAng, -90, 90) !== null
                           && root.finiteIn(c.horizon.base, -500, 9000) !== null
                           && root.finiteIn(c.horizon.span, 0, 9000) !== null) ? c.horizon : null
      hzH0 = root.finiteIn(c.hzH0, -500, 9000) || 0
      // frac, az and dist were going unchecked; dist scales the viewpoint and
      // az points it, so a bad one aims the whole scene at nothing.
      // `src` is absent in caches written before it existed; "ground" is the
      // right default there, since every verdict then came from elevation.
      if (c.water && c.water.src !== "marine") c.water.src = "ground"
      water = (c.water && root.finiteIn(c.water.kind, 0, 3) !== null
                       && root.finiteIn(c.water.level, -500, 9000) !== null
                       && root.finiteIn(c.water.frac, 0, 1) !== null
                       && root.finiteIn(c.water.az, 0, 360) !== null
                       && root.finiteIn(c.water.dist, 0, 60000) !== null) ? c.water : null
      lastFetchMs = root.finiteIn(c.at, 0, 4102444800000) || 0
      pushSky()
      if (!ring || !horizon || !water) fetchHorizon()
      if (!climate) fetchClimate()
      // the cache says where you were, not where you are
      checkLocation(true)
      if (Date.now() - lastFetchMs >= cacheMaxAgeMs) refreshSky(true)
    } catch (e) { /* a corrupt cache is simply no cache */ }
  }

  function todToDate(todValue) {
    return new Date(root.midnightAtLoc().getTime() + todValue * 86400000)
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
    // Re-summoning is the retry. The top-up gives up after six attempts so a
    // place the service will not answer for does not get asked forever — but
    // that left no way back short of changing location. Opening it again is
    // the obvious gesture and costs no new key, which matters because "any
    // key dismisses" is the one property a screensaver must not lose.
    root.topUps = 0
    root.nextTopUpMs = 0
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
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // An IP lookup started before shell.json was read can land after it; without
  // the configLoc guard it would quietly overwrite an explicit location.
  function adoptIpLocation(lat, lon, name, country) {
    if (root.lockedLoc) return
    if (!isFinite(lat) || !isFinite(lon)) return
    // Names come from an API and are rendered, so they are capped where they
    // enter rather than where they are drawn.
    var nl = { lat: lat, lon: lon,
               name: root.capStr(name, root.maxStrLen),
               country: root.capStr(country, root.maxStrLen) }
    // a fifth of a degree is roughly 20 km: far enough to be somewhere else
    var moved = !root.loc || Math.abs(nl.lat - root.loc.lat) > 0.2
                          || Math.abs(nl.lon - root.loc.lon) > 0.2
    root.loc = nl
    if (moved) { root.fc = null; root.kp = null; root.ring = null
                 root.climate = null; root.horizon = null; root.water = null
                 root._lastPush = -9999 }
    root.fetchForecast(); root.fetchKp()
    if (moved || !root.ring || !root.horizon || !root.water) root.fetchHorizon()
    if (moved || !root.climate) root.fetchClimate()
  }

  // Location by IP. geojs is asked first because it tracks VPN and hosting
  // ranges, which is exactly the case that matters here: on a Packethub exit
  // registered in Egypt it answers Cairo, while wttr.in — the chain Omarchy's
  // own weather widget uses — answered Vila Prota, Brazil for the same address.
  // wttr.in stays as the fallback, so nothing new has to be reachable.
  Process {
    id: locProc
    property string src: "ip"
    property bool ok: false          // set by a good parse, read by onExited
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true
                             onStreamFinished: locProc.errText = text }
    onExited: function (code, status) {
      root.noteExit(locProc.src, code, locProc.errText, locProc.ok)
      locProc.ok = false; locProc.errText = ""
    }
    command: root.curlCmd(8, root.capIp, "https://get.geojs.io/v1/ip/geo.json")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          if (root.lockedLoc) return
          var j = root.boundedParse(text, root.capIp)
          if (j) locProc.ok = true
          // A throw and not a return: this catch is what starts the wttr.in
          // fallback, so returning here meant that being offline — the one
          // case a fallback exists for — was the one case that never used it.
          if (!j) throw new Error("no reply")
          var lat = parseFloat(j.latitude), lon = parseFloat(j.longitude)
          if (!isFinite(lat) || !isFinite(lon)) throw new Error("no fix")
          root.adoptIpLocation(lat, lon, j.city, j.country)
        } catch (e) {
          if (!root.lockedLoc && !locFallbackProc.running) locFallbackProc.running = true
        }
      }
    }
  }

  Process {
    id: locFallbackProc
    property string src: "ip"
    property bool ok: false          // set by a good parse, read by onExited
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true
                             onStreamFinished: locFallbackProc.errText = text }
    onExited: function (code, status) {
      root.noteExit(locFallbackProc.src, code, locFallbackProc.errText, locFallbackProc.ok)
      locFallbackProc.ok = false; locFallbackProc.errText = ""
    }
    command: root.curlCmd(8, root.capWttr, "https://wttr.in/?format=j1")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          if (root.lockedLoc) return
          var wj = root.boundedParse(text, root.capWttr)
          if (wj) locFallbackProc.ok = true
          var na = wj && root.capArray(wj.nearest_area, 8)
          if (!na || !na.length) return
          var a = na[0]
          root.adoptIpLocation(parseFloat(a.latitude), parseFloat(a.longitude),
                               a.areaName && a.areaName[0] && a.areaName[0].value,
                               a.country && a.country[0] && a.country[0].value)
        } catch (e) { /* offline: the scene simply stays as it is */ }
      }
    }
  }

  Process {
    id: nearProc
    property string src: "elevation"
    property bool ok: false          // set by a good parse, read by onExited
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true
                             onStreamFinished: nearProc.errText = text }
    onExited: function (code, status) {
      root.noteExit(nearProc.src, code, nearProc.errText, nearProc.ok)
      nearProc.ok = false; nearProc.errText = ""
    }
    property int gen: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.stale(nearProc)) return   // a reply for a place we have left
        try {
          var ej = root.boundedParse(text, root.capElevation)
          if (ej) nearProc.ok = true
          var e = ej && root.numArray(ej.elevation, root.maxPoints, -500, 9000, false)
          var want = root.nearN * root.nearN
          if (!e || e.length < want) { root.fallbackFan(); return }

          // Offsets in metres, matching the order fetchNearField built them.
          var dx = [], dy = [], q, i, j
          for (i = 0; i < root.nearN; i++) {
            for (j = 0; j < root.nearN; j++) {
              dy.push(root.nearHalf - 2 * root.nearHalf * i / (root.nearN - 1))
              dx.push(-root.nearHalf + 2 * root.nearHalf * j / (root.nearN - 1))
            }
          }
          for (i = 0; i < want; i++) root.hzPts.push(dx[i], dy[i], e[i])

          // The near field's own verdict. Its cells are the grid step squared
          // and it measures the same 12 km box it always did.
          var step0 = 2 * root.nearHalf / (root.nearN - 1)
          var near = root.findWater(dx, dy, e,
                                    4 * root.nearHalf * root.nearHalf,
                                    step0 * step0)
          if (!near && !(root.water && root.water.kind > 0)) {
            root.water = { level: 0, kind: 0, frac: 0, az: 0, dist: 0 }
          }
          root.adoptWater(near)
          if (!root.water || root.water.kind === 0) { root.fallbackFan(); return }

          var lvl = root.water.level, waz = root.water.az, med = root.water.dist

          // Stand across it, facing back. Near enough that the far shore still
          // reads, far enough that the water is genuinely in front of you.
          var D = Math.max(2000.0, Math.min(med + 1200.0, 8000.0))
          var vx = D * Math.sin(waz * Math.PI / 180)
          var vy = D * Math.cos(waz * Math.PI / 180)
          // Standing on the water means the eye is at the water's own level,
          // which is exactly where this scene puts the horizon.
          root.hzH0 = lvl
          // Rings scaled to how far back we stand, so whatever we came to look
          // at is actually sampled. Fixed rings at 6 and 11 km straddled a 2 km
          // hill 7 km away and missed Mount Royal completely.
          root.fetchHorizonFan(vx, vy, (waz + 180.0) % 360.0,
                               [D * 0.30, D * 0.60, D, D * 1.80, D * 3.20])
        } catch (err) { root.fallbackFan() }
      }
    }
  }

  Process {
    id: fanProc
    property string src: "elevation"
    property bool ok: false          // set by a good parse, read by onExited
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true
                             onStreamFinished: fanProc.errText = text }
    onExited: function (code, status) {
      root.noteExit(fanProc.src, code, fanProc.errText, fanProc.ok)
      fanProc.ok = false; fanProc.errText = ""
    }
    property int gen: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.stale(fanProc)) return   // a reply for a place we have left
        try {
          var ej = root.boundedParse(text, root.capElevation)
          if (ej) fanProc.ok = true
          var e = ej && root.numArray(ej.elevation, root.maxPoints, -500, 9000, false)
          var want = root.hzFanAz * (root.hzRingsUsed || root.hzFan).length
          if (!e || e.length < want) return
          var h0 = root.hzH0

          // One value per screen column: the highest ground along that bearing.
          // Altitude and not apparent angle, and the difference matters: a
          // near 3400 m ridge subtends more than Pichincha does behind it, so
          // an angular profile drew the near ridge as the summit and scaled
          // Quito's mountain at 718 m of altitude per unit of ridge when the
          // truth is 1707 — which put the snowline on the wrong mountain and,
          // being past the top of it, on no mountain at all. Height is what
          // snow and trees answer to, so height is what the shape is made of;
          // how big the whole thing looks is a separate number, and that one
          // is angular.
          //
          // No floor at the observer's own height, tempting as it looks: the
          // drawn ridge is normalised between its own lowest and highest column
          // and can never fall below the waterline anyway, so the floor bought
          // nothing — and it broke the one case it was supposed to help.
          // The geocoder puts "Montreal" on top of Mount Royal, where every
          // direction is downhill; floored, all twenty columns came back equal,
          // the profile normalised to zero, and the land vanished entirely.
          var rings = root.hzRingsUsed || root.hzFan
          var col = [], ang = [], i = 0
          for (var j = 0; j < root.hzFanAz; j++) {
            var bh = -12000, ba = -999
            for (var r = 0; r < rings.length; r++) {
              if (e[i] > bh) bh = e[i]
              var a = root.apparentDeg(e[i], h0, rings[r])
              if (a > ba) ba = a
              i++
            }
            col.push(bh); ang.push(ba)
          }

          // Fold in every sample the earlier passes took, re-projected onto
          // wherever the eye actually stands. Purely extra evidence about the
          // same ground, and it is what raised Quito's summit from 4007 m to
          // 4565 — at 90 m postings a summit is one cell wide, so every extra
          // look at it counts.
          var pp = root.hzPts
          if (pp && pp.length >= 3) {
            var half = root.hzFov * 0.5
            var step = root.hzFov / (root.hzFanAz - 1)
            for (var k = 0; k + 2 < pp.length; k += 3) {
              var ox = pp[k] - root.hzVx, oy = pp[k + 1] - root.hzVy
              var od = Math.sqrt(ox * ox + oy * oy)
              if (od < 400.0) continue          // under your feet, not a skyline
              var oa = Math.atan2(ox, oy) * 180 / Math.PI
              var rel = ((oa - root.hzAim + 540.0) % 360.0) - 180.0
              if (Math.abs(rel) > half) continue
              var c = Math.round((rel + half) / step)
              c = Math.max(0, Math.min(root.hzFanAz - 1, c))
              var hv = pp[k + 2]
              if (hv > col[c]) col[c] = hv
              var av = root.apparentDeg(hv, h0, od)
              if (av > ang[c]) ang[c] = av
            }
          }

          var hMin = col[0], hMax = col[0], maxAng = ang[0]
          for (var q = 1; q < col.length; q++) {
            if (col[q] < hMin) hMin = col[q]
            if (col[q] > hMax) hMax = col[q]
            if (ang[q] > maxAng) maxAng = ang[q]
          }
          // A metre of altitude is worth this much of the drawn ridge, which is
          // the whole of what the snowline and the treeline need to know.
          var span = Math.max(hMax - hMin, 1.0)
          var f = []
          for (var w = 0; w < col.length; w++) f.push((col[w] - hMin) / span)

          root.horizon = { coef: root.cosineFit(f, 12), maxAng: maxAng,
                           base: hMin, span: span }
          root.pushSky(); root.saveCache()
        } catch (err) { /* no profile: the ridge falls back to its old shape */ }
      }
    }
  }

  Process {
    id: fcProc
    property string src: "forecast"
    property bool ok: false          // set by a good parse, read by onExited
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true
                             onStreamFinished: fcProc.errText = text }
    onExited: function (code, status) {
      root.noteExit(fcProc.src, code, fcProc.errText, fcProc.ok)
      fcProc.ok = false; fcProc.errText = ""
    }
    property int gen: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.stale(fcProc)) return   // a reply for a place we have left
        try {
          var j = root.boundedParse(text, root.capForecast)
          if (j) fcProc.ok = true
          if (!j) return
          var h = j.hourly
          if (!h) return

          // Every series is bounded and must be the same length as the time
          // axis it is indexed by. Anything else is a malformed reply, not a
          // longer one: resolveSky() reads these arrays in parallel at one
          // index, so a short series next to a long axis is an out-of-bounds
          // read waiting for a scrub to reach it.
          var t = root.strArray(h.time, root.maxSeries, 40)
          if (!t || t.length < 2) return
          // Ranges are what these quantities can physically be, not what the
          // service happens to send: a reply outside them is wrong whoever
          // produced it. Nulls are tolerated only where the API really does
          // send them for a valid reason.
          var series = function (a, lo, hi, nullsOk) {
            var v = root.numArray(a, root.maxSeries, lo, hi, nullsOk)
            return (v && v.length === t.length) ? v : null
          }
          // Nulls are real here: the tail of the 23-day window comes back
          // with them, and kindWeights() already treats an unknown code as
          // clear. Rejecting them threw the whole forecast away.
          var code  = series(h.weather_code, 0, 99, true)
          var precip= series(h.precipitation, 0, 1000, true)
          var cloud = series(h.cloud_cover, 0, 100, true)
          var temp  = series(h.temperature_2m, -120, 80, true)
          var snowf = series(h.snowfall, 0, 500, true)
          var depth = series(h.snow_depth, 0, 100, true)
          var soil  = series(h.soil_temperature_0cm, -120, 100, true)
          var wspd  = series(h.wind_speed_10m, 0, 500, true)
          var wdir  = series(h.wind_direction_10m, 0, 360, true)
          // CAPE is an energy per unit mass and 20 kJ/kg is past anything the
          // atmosphere does; the lifted index is a temperature difference and
          // goes negative when the air is unstable, which is the whole point
          // of it. Both come back negative sometimes, so neither is floored.
          var cape  = series(h.cape, -2000, 20000, true)
          var li    = series(h.lifted_index, -40, 60, true)
          var gust  = series(h.wind_gusts_10m, 0, 500, true)
          if (!code || !precip || !cloud || !temp || !snowf || !depth
              || !soil || !wspd || !wdir || !cape || !li || !gust) return
          // Absent at some locations — Tromso sends nulls throughout — so a
          // missing series is expected, but a present-and-malformed one is not.
          var flz = null
          if (h.freezing_level_height !== undefined) {
            flz = series(h.freezing_level_height, -1000, 30000, true)
            if (!flz) return
          }

          root.elevation = root.finiteIn(j.elevation, -500, 9000) || 0

          // The zone has to be set BEFORE the hours are measured against it:
          // t0 is the first sample's distance from the target's midnight, and
          // taking it against the old zone's midnight would shift the entire
          // 23-day window by the difference. Fourteen hours is not a rounding
          // error, it is night for day.
          var off = root.finiteIn(j.utc_offset_seconds, -50400, 50400)
          var moved = (off !== null && off !== root.tzOffset)
          if (off !== null) root.tzOffset = off
          root.tzName = root.capStr(j.timezone_abbreviation, 12)

          var sr = root.parseDaylight(j.daily)
          root.fc = { t0: root.hoursFromMidnightLocal(t[0]),
                      code: code, precip: precip,
                      cloud: cloud, temp: temp,
                      snowfall: snowf, depth: depth,
                      soil: soil,
                      wspd: wspd, wdir: wdir,
                      cape: cape, li: li, gust: gust,
                      flz: flz,
                      rise: sr.rise, set: sr.set }
          // Kp's hours are measured against the target's midnight, and the
          // target may only just have changed.
          root.rebuildKpHours()

          // Re-seeding the clock is onTzOffsetChanged's job above, and it has
          // already run if the offset moved. What is left here is the case it
          // cannot see: the same offset, but a place we had marked as not yet
          // answered for — and the date, if one was typed with the place.
          var wasStale = root.tzStale
          root.tzStale = false
          if (root.pendingWhen) root.applyWhen()
          else if (wasStale && !moved && root.opened && !root.scrubbing
                   && !root.todReturning && !root.pinned
                   && root.inspectMode === 0)
            root.syncTimeOfDay()
          if (wasStale) { root.notice = true; noticeTimer.restart() }
          root.lastFetchMs = Date.now()      // landed, not merely attempted
          root.pushSky(); root.refreshReadout(); root.saveCache()
        } catch (e) {}
      }
    }
  }

  Process {
    id: kpProc
    property string src: "kp"
    property bool ok: false          // set by a good parse, read by onExited
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true
                             onStreamFinished: kpProc.errText = text }
    onExited: function (code, status) {
      root.noteExit(kpProc.src, code, kpProc.errText, kpProc.ok)
      kpProc.ok = false; kpProc.errText = ""
    }
    property int gen: 0
    command: root.curlCmd(8, root.capKp,
      "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var pj = root.boundedParse(text, root.capKp)
          if (pj) kpProc.ok = true
          var arr = root.capArray(pj, root.maxDaily)
          if (!arr) return
          // Rows are objects — { time_tag, kp, ... } — and only those carrying
          // a kp are consumed, so a row without one is skipped rather than
          // rejected. A row that does carry one must have a usable timestamp
          // and an index in the range the scale actually has.
          for (var q = 0; q < arr.length; q++) {
            var row = arr[q]
            if (!row || typeof row !== "object" || Array.isArray(row)) return
            if (row.kp === undefined || row.kp === null) continue
            if (typeof row.time_tag !== "string" || row.time_tag.length > 40) return
            if (root.finiteIn(row.kp, 0, 9) === null) return
          }
          var ms = [], vals = []
          for (var i = 0; i < arr.length; i++) {
            var e = arr[i]
            if (!e || e.kp === undefined || e.kp === null) continue
            ms.push(root.epochOfUtc(e.time_tag))
            vals.push(parseFloat(e.kp))
          }
          root.kp = { ms: ms, vals: vals, hrs: [] }
          root.rebuildKpHours()
          root.pushSky(); root.saveCache()
        } catch (e) {}
      }
    }
  }

  Process {
    id: climProc
    property string src: "climate"
    property bool ok: false          // set by a good parse, read by onExited
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true
                             onStreamFinished: climProc.errText = text }
    onExited: function (code, status) {
      root.noteExit(climProc.src, code, climProc.errText, climProc.ok)
      climProc.ok = false; climProc.errText = ""
    }
    property int gen: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.stale(climProc)) return   // a reply for a place we have left
        try {
          var cj = root.boundedParse(text, root.capClimate)
          if (cj) climProc.ok = true
          var d = cj && cj.daily
          if (!d) return
          var dp = root.numArray(d.precipitation_sum, root.maxDaily, 0, 5000, true)
          var de = root.numArray(d.et0_fao_evapotranspiration, root.maxDaily, 0, 200, true)
          // Read in parallel at one index, so unequal lengths are refused
          // rather than walked off the end of the shorter one.
          if (!dp || !de || dp.length !== de.length || !dp.length) return
          // Iterated over the validated length, not over d.time: the two
          // series have been checked against each other, and the time axis is
          // not read here at all.
          var ps = 0, es = 0
          for (var i = 0; i < dp.length; i++) {
            ps += dp[i] || 0
            es += de[i] || 0
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
    property string src: "elevation"
    property bool ok: false          // set by a good parse, read by onExited
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true
                             onStreamFinished: elevProc.errText = text }
    onExited: function (code, status) {
      root.noteExit(elevProc.src, code, elevProc.errText, elevProc.ok)
      elevProc.ok = false; elevProc.errText = ""
    }
    property int gen: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.stale(elevProc)) return   // a reply for a place we have left
        try {
          var ej = root.boundedParse(text, root.capElevation)
          if (ej) elevProc.ok = true
          var e = ej && root.numArray(ej.elevation, root.maxPoints, -500, 9000, false)
          var want = 1 + root.hzAz * root.hzRings.length
          if (!e || e.length < want) { root.fetchNearField(); return }
          var h0 = e[0]
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

          // Which way to face. The most prominent thing on the horizon wins,
          // so the peak a place is known for is always in frame — at the price
          // that the view no longer points any particular compass direction,
          // and the sun keeps rising on the left whichever way you are looking.
          var bestAng = -999, bestAz = 0, k = 1
          for (var a = 0; a < root.hzAz; a++) {
            for (var r = 0; r < root.hzRings.length; r++) {
              var ang = root.apparentDeg(e[k], h0, root.hzRings[r]); k++
              if (ang > bestAng) { bestAng = ang; bestAz = 360.0 * a / root.hzAz }
            }
          }
          root.hzH0 = h0
          // Kept, not thrown away: pass 1 samples the whole compass and pass 2
          // only a slice of it, but at distances pass 2 does not visit. Merging
          // the two raised Quito's summit from 4007 m to 4565 — and at 90 m
          // postings a summit is one cell wide, so every extra look at it
          // counts. Held as offsets in metres so they can be re-projected onto
          // a viewpoint that is not the place.
          var pts = []
          var kk = 1
          for (var a3 = 0; a3 < root.hzAz; a3++) {
            var ra = 2.0 * Math.PI * a3 / root.hzAz
            for (var r3 = 0; r3 < root.hzRings.length; r3++) {
              pts.push(root.hzRings[r3] * Math.sin(ra),
                       root.hzRings[r3] * Math.cos(ra), e[kk]); kk++
            }
          }
          root.hzPts = pts
          root.hzTerrainAim = bestAz

          // Pass 1 has just measured a 25 km disc, and water beyond the near
          // field's 6 km box is exactly what it can see and the near field
          // cannot. Toronto is the case: the geocoder puts it about 7 km
          // inland, so Lake Ontario only grazes the near grid, while out here
          // it is 23% of the samples at a dead flat 74 m. Costs no request —
          // these elevations were fetched for the skyline anyway.
          //
          // The rings are 33 azimuths at 4, 11 and 25 km, so a sample stands
          // for a wedge of its annulus rather than a square cell.
          var ringArea = Math.PI * 25000.0 * 25000.0
          var cellA = ringArea / (root.hzAz * root.hzRings.length)
          var rdx = [], rdy = [], rel = []
          for (var w1 = 0; w1 < pts.length; w1 += 3) {
            rdx.push(pts[w1]); rdy.push(pts[w1 + 1]); rel.push(pts[w1 + 2])
          }
          root.adoptWater(root.findWater(rdx, rdy, rel, ringArea, cellA))

          root.pushSky(); root.saveCache()
          root.fetchNearField()
        } catch (err) {
          // The near field only needs `loc`, so one failed ring request must
          // not take the whole three-pass terrain chain down with it — which
          // is what calling it only from the success path used to do.
          root.fetchNearField()
        }
      }
    }
  }

  // Same geocoder Omarchy's weather panel uses, so no new service is involved.
  Process {
    id: marineProc
    property int gen: 0
    property string src: "marine"
    property bool ok: false
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true
                             onStreamFinished: marineProc.errText = text }
    onExited: function (code, status) {
      root.noteExit(marineProc.src, code, marineProc.errText, marineProc.ok)
      marineProc.ok = false; marineProc.errText = ""
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.stale(marineProc)) return   // a reply for a place we have left
        try {
          // A multi-coordinate marine request answers with an ARRAY, one entry
          // per point, unlike every other endpoint here.
          var mj = root.boundedParse("{\"a\":" + String(text || "") + "}",
                                     root.capMarine)
          var arr = mj && root.capArray(mj.a, 32)
          if (!arr) return
          marineProc.ok = true
          var want = root.marineRings.length * root.marineAz
          if (arr.length !== want || root.marinePts.length !== want * 2) return

          // The nearest point that answers with a real wave height is the
          // nearest open water. A null is not missing data here, it is the
          // model saying "this is land" — which is exactly the question.
          var bestD = 1e9, bx = 0, by = 0
          for (var i = 0; i < want; i++) {
            var e = arr[i]
            if (!e || typeof e !== "object" || Array.isArray(e)) return
            var h = e.hourly
            if (!h) continue
            var wv = root.numArray(h.wave_height, 48, 0, 60, true)
            if (!wv) return
            var got = false
            for (var j = 0; j < wv.length; j++)
              if (wv[j] !== null && wv[j] !== undefined) { got = true; break }
            if (!got) continue
            // Where the model actually answered, not where we asked. Its grid
            // cells are about nine kilometres across, so a probe snaps to the
            // nearest wet cell and the two can differ by more than the probe
            // radius — which had Limassol reporting the Mediterranean to the
            // north of it. The reply echoes the cell it used, so use that.
            var mlat = root.finiteIn(e.latitude, -90, 90)
            var mlon = root.finiteIn(e.longitude, -180, 180)
            var dx, dy
            if (mlat !== null && mlon !== null) {
              dy = (mlat - root.loc.lat) * 111320.0
              dx = (mlon - root.loc.lon) * 111320.0
                 * Math.max(0.05, Math.cos(root.loc.lat * Math.PI / 180))
            } else {
              dx = root.marinePts[2 * i]; dy = root.marinePts[2 * i + 1]
            }
            var d = Math.sqrt(dx * dx + dy * dy)
            if (d < bestD) { bestD = d; bx = dx; by = dy }
          }
          if (bestD > 1e8) return          // no open water anywhere we asked

          // Only ever adds sea the ground could not show us; it never
          // overrules a river or a lake the elevation pass actually measured.
          root.adoptWater({ level: 0, kind: 3, src: "marine",
                            frac: bestD <= 8000.0 ? 0.30 : 0.14,
                            az: (Math.atan2(bx, by) * 180 / Math.PI + 360) % 360,
                            dist: bestD })
          root.pushSky(); root.saveCache()
        } catch (err) { /* no marine answer: the ground's verdict stands */ }
      }
    }
  }

  Process {
    id: geoProc
    property string src: "geocode"
    property bool ok: false          // set by a good parse, read by onExited
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true
                             onStreamFinished: geoProc.errText = text }
    onExited: function (code, status) {
      root.noteExit(geoProc.src, code, geoProc.errText, geoProc.ok)
      geoProc.ok = false; geoProc.errText = ""
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var gj = root.boundedParse(text, root.capGeocode)
          if (gj) geoProc.ok = true
          var gr = gj && root.capArray(gj.results, 32)
          // A country answers with its centroid, which is a point in a field
          // somewhere. Somewhere people live is usually what was meant — but
          // only in the same country: the five answers for "Cyprus" are the
          // republic, the island, a village in Jamaica, a hamlet in England
          // and a town in South Africa, and preferring a populated place
          // without checking the country sends you to Jamaica, which is a
          // worse answer than the mountain it replaced.
          if (gr && gr.length > 1) {
            var cc0 = root.capStr(gr[0].country_code, 4)
            var top = root.capStr(gr[0].feature_code, 12)
            if (cc0 && top.substring(0, 3) !== "PPL") {
              for (var gi = 1; gi < gr.length; gi++) {
                if (!gr[gi]) continue
                if (root.capStr(gr[gi].country_code, 4) !== cc0) continue
                if (root.capStr(gr[gi].feature_code, 12).substring(0, 3) !== "PPL") continue
                gr = [gr[gi]].concat(gr)
                break
              }
            }
          }
          if (!gr || !gr.length) { if (root.geoForSearch) { root.geoForSearch = false; root.searching = false; root.pendingWhen = null; root.searchFailed = true; root.searchNote = root.geoFailNote() } return }
          var r = root.validLoc(gr[0])
          if (!r) { if (root.geoForSearch) { root.geoForSearch = false; root.searching = false; root.pendingWhen = null; root.searchFailed = true; root.searchNote = root.geoFailNote() } return }
          // validLoc has already canonicalised the coordinates and capped the
          // strings, so this is the sanitised object, not the reply.
          var nl = r
          // Forward geocoding hands back the name and country with the
          // coordinates, so a typed place needs no second lookup to be labelled.
          if (root.geoForSearch) {
            root.geoForSearch = false
            root.chosenLoc = nl
            root.fc = null; root.kp = null
            root.ring = null; root.climate = null; root.horizon = null; root.water = null
            root._lastPush = -9999
            root.searching = false; root.searchFailed = false; root.searchNote = ""
          }
          root.loc = nl
          root.fetchForecast(); root.fetchKp(); root.fetchHorizon(); root.fetchClimate()
          root.fetchMarine()
          root.saveCache()
        } catch (e) {
          if (root.geoForSearch) {
            // say so rather than silently going somewhere else
            root.geoForSearch = false
            root.pendingWhen = null
            root.searchFailed = true; root.searchNote = root.geoFailNote()
          } else if (!locProc.running) locProc.running = true
        }
      }
    }
  }

  // The payload reaches the script on stdin, never on the command line.
  // Closing stdin is what signals EOF to base64, so the write only completes
  // once the data has been handed over in full.
  Process {
    id: cacheWriteProc
    property string payload: ""
    stdinEnabled: true
    onStarted: {
      write(payload)
      payload = ""
    }
    onExited: function (code, status) {
      if (code !== 0)
        console.warn("borealis-atlas: could not write the sky cache (exit "
                     + code + "); the scene is unaffected")
      // A save that arrived while this one was in flight runs now, with only
      // the newest payload.
      if (root._pendingCache.length > 0) {
        var next = root._pendingCache
        root._pendingCache = ""
        payload = next
        stdinEnabled = true
        command = ["sh", "-c", root.cacheWriteScript, "sh", root.cachePath,
                   String(next.length)]
        running = true
      }
    }
  }

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
          duration: root.todReturning ? root.todReturnMs
                  : (root.drifting ? root.driftMs : 110)
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
      // The measured skyline, and the two altitude lines cutting across it.
      // The defaults are the cosine fit of the ridge this replaced, at its old
      // mid relief, so an overlay opened with no data and no cache draws
      // exactly the horizon it used to — and both lines start above every
      // summit, which is the same as having none.
      property vector4d hills0: Qt.vector4d(root.defaultHills[0], root.defaultHills[1],
                                            root.defaultHills[2], root.defaultHills[3])
      property vector4d hills1: Qt.vector4d(root.defaultHills[4], root.defaultHills[5],
                                            root.defaultHills[6], root.defaultHills[7])
      property vector4d hills2: Qt.vector4d(root.defaultHills[8], root.defaultHills[9],
                                            root.defaultHills[10], root.defaultHills[11])
      property vector4d alt: Qt.vector4d(2.0, 2.0, 0.15, 0.006)
      // near bank, wave scale, mirror compression. The default is a lake,
      // which is what the scene drew everywhere before any of this.
      property vector4d shore: Qt.vector4d(0.965, 1.0, 3.2, 0)
      // Moon against sun: offset in solar radii, how much of the moon's
      // position that offset accounts for, and the ratio of the two radii.
      // The default blend of 0 is "no override", which is every moment that is
      // not within a couple of hours of a new moon.
      property vector4d ecl: Qt.vector4d(0, 0, 0, root.moonSunMean)
      // shadow depth, inspect zoom
      property vector4d umbra: Qt.vector4d(0, 0, 0, 0)
      // convective instability, warning tier
      property vector4d sev: Qt.vector4d(0, 0, 0, 0)
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
      property real gestureMaxDist: 0
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
        root.pinned = false
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
            touchArea.gestureMaxDist = 0
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
            touchArea.gestureMaxDist = Math.max(touchArea.gestureMaxDist,
                                                Math.sqrt(dx * dx + dy * dy))
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
        var quick = touchArea.gestureMaxDist < root.tapSlopPx && held < root.holdMs
        var fingers = touchArea.gestureMaxPoints
        var relX = points.length > 0 ? points[0].x : touchArea.gestureStartX
        var relY = points.length > 0 ? points[0].y : touchArea.gestureStartY
        touchArea.gestureId = -1
        touchArea.gestureMaxPoints = 0

        // Letting go keeps the hour you landed on, so a forecast can actually
        // be read. Double tap comes home; see goToNow().
        root.readoutHold = root.readoutHoldMs
        readoutHideTimer.restart()

        // one quick tap is the way out; two fingers recolours the sky; holding
        // or dragging means "I am playing" and does neither
        if (quick && fingers >= 2) root.cyclePalette()
        else if (quick) {
          // A tap far from the last one starts a new count rather than
          // continuing it, so playing with the light in two places cannot add
          // up to "go home".
          var ddx = relX - root.lastTapX, ddy = relY - root.lastTapY
          if (root.tapCount > 0 && Math.sqrt(ddx * ddx + ddy * ddy) > root.tapNearPx)
            root.tapCount = 0
          root.lastTapX = relX; root.lastTapY = relY
          root.tapCount++
          tapTimer.restart()
        }
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
      interval: root.multiTapMs; repeat: false
      onTriggered: {
        if (root.tapCount >= 3) root.dismiss()
        else if (root.tapCount === 2) root.goToNow()
        root.tapCount = 0
      }
    }

    Timer {
      id: readoutHideTimer
      interval: root.readoutHold; repeat: false
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
      opacity: (root.scrubbing || root.inspectMode > 0 || root.pinned) ? 1
             : root.notice ? 0.92
             : root.awayFromNow ? 0.78 : 0
      Behavior on opacity { NumberAnimation { duration: 280 } }

    Text {
      // Anything rendered here can carry API- or user-supplied text, and AutoText would
      // interpret it as markup. Set on every Text without exception, so the rule is
      // checkable by grep rather than by reading each binding.
      textFormat: Text.PlainText
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
      // Anything rendered here can carry API- or user-supplied text, and AutoText would
      // interpret it as markup. Set on every Text without exception, so the rule is
      // checkable by grep rather than by reading each binding.
      textFormat: Text.PlainText
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
      opacity: (root.scrubbing || root.inspectMode > 0 || root.pinned
                || root.notice || root.awayFromNow) ? 0.72 : 0
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
          // Also while parked or announcing: a jump to a typed date is
          // animated, and without this the line kept whatever time it read as
          // the animation set off rather than the one it arrived at.
          if (root.scrubbing || root.inspectMode > 0
              || root.pinned || root.notice) {
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

    // Typing a place. IP geolocation is guesswork through a VPN — on one
    // address this session four services disagreed across three continents —
    // and this machine has a keyboard, so the shortest honest answer is to be
    // told where you are.
    Item {
      id: searchLayer
      anchors.fill: parent
      z: 40
      visible: opacity > 0.01
      opacity: root.searching ? 1 : 0
      enabled: false                       // keys only; it takes no pointer
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

      Rectangle { anchors.fill: parent; color: "#070b14"; opacity: 0.55 }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.30
        spacing: root.sceneH * 0.018

        Text {
          // Anything rendered here can carry API- or user-supplied text, and AutoText would
          // interpret it as markup. Set on every Text without exception, so the rule is
          // checkable by grep rather than by reading each binding.
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          color: "#eaf0f8"; opacity: 0.55
          font.pixelSize: Math.max(11, root.sceneH * 0.0165)
          font.letterSpacing: 0.4
          text: "Go to"
        }

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.max(root.sceneH * 0.42, entry.width + root.sceneH * 0.06)
          height: entry.height + root.sceneH * 0.030
          radius: root.sceneH * 0.008
          color: "#0d1a2e"
          border.color: "#2a4460"; border.width: 1

          Text {
            // Anything rendered here can carry API- or user-supplied text, and AutoText would
            // interpret it as markup. Set on every Text without exception, so the rule is
            // checkable by grep rather than by reading each binding.
            textFormat: Text.PlainText
            id: entry
            anchors.centerIn: parent
            color: "#eaf0f8"
            font.pixelSize: Math.max(16, root.sceneH * 0.030)
            text: root.searchText + (caret.on ? "\u2502" : " ")
          }
          Item {
            id: caret
            property bool on: true
            Timer { interval: 520; repeat: true; running: root.searching
                    onTriggered: caret.on = !caret.on }
          }
        }

        Text {
          // Anything rendered here can carry API- or user-supplied text, and AutoText would
          // interpret it as markup. Set on every Text without exception, so the rule is
          // checkable by grep rather than by reading each binding.
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          color: root.searchFailed ? "#e8a37c" : "#eaf0f8"
          opacity: 0.62
          font.pixelSize: Math.max(11, root.sceneH * 0.0155)
          horizontalAlignment: Text.AlignHCenter
          text: root.searchNote !== "" ? root.searchNote
              : (root.chosenLoc
                 ? "A place, a moment, or both: Istanbul @ tomorrow 15:00"
                   + "  \u00b7  empty Enter follows this machine again"
                   + "  \u00b7  Esc to cancel"
                 : "A place, a moment, or both: Istanbul @ tomorrow 15:00"
                   + "  \u00b7  Esc to cancel")
        }
      }
    }

    // Anchored to the top, deliberately: the readout Column at the bottom gates
    // all its children through one opacity, and this is the one line that must
    // not fade out with the six-second notice.
    Text {
      // Anything rendered here can carry API- or user-supplied text, and AutoText would
      // interpret it as markup. Set on every Text without exception, so the rule is
      // checkable by grep rather than by reading each binding.
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: parent.height * 0.06
      horizontalAlignment: Text.AlignHCenter
      color: "#e8a37c"
      style: Text.Outline
      styleColor: "#66000000"
      font.pixelSize: Math.max(11, root.sceneH * 0.0155)
      font.letterSpacing: 0.4
      opacity: (root.troubleShown && root.trouble !== "") ? 0.88 : 0
      visible: opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: 280 } }
      // Only fixed strings and the already-capped place name are ever shown
      // here — never curl's stderr, which echoes the request URL back.
      text: root.trouble
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        event.accepted = true
        if (root.searching) {
          if (event.key === Qt.Key_Escape) {
            root.searching = false; root.searchText = ""; root.searchFailed = false; root.searchNote = ""
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submitSearch()
          } else if (event.key === Qt.Key_Backspace) {
            root.searchText = root.searchText.slice(0, -1)
            root.searchFailed = false; root.searchNote = ""
          } else if (event.text && event.text.length === 1
                     && event.text >= " " && root.searchText.length < 60) {
            root.searchText += event.text
            root.searchFailed = false; root.searchNote = ""
          }
          return
        }
        // "/" opens the search. Every other key still dismisses, which is the
        // one property a screensaver must not lose — grabbing letters to start
        // typing would mean a cat on the keyboard opens a search box instead of
        // getting out of the way.
        if (event.key === Qt.Key_Slash) { root.openSearch(); return }
        root.dismiss()
      }
    }
  }
}
