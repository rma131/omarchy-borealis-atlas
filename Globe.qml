// A small wireframe globe, orthographic, centred on wherever you are looking.
//
// Deliberately self-contained: this file and coastline.js are the whole of it,
// and deleting the pair removes the feature without touching anything else.
//
// It draws on a Canvas rather than in the shader because it is a caption, not
// scenery — and because it must repaint a handful of times per session, not
// sixty times a second. `tod` changes every frame while the sky drifts, so
// nothing here is allowed to depend on it. That is also why there is no
// day/night terminator, which is the obvious next thing to add and the one
// thing that would tie this to the clock.
import QtQuick
import "coastline.js" as Coastline

Canvas {
  id: globe

  // Where the marker goes. Null means there is nothing to draw yet.
  property var place: null
  // Drawn dimmer when the scene behind it is bright, so it reads either way.
  property color inkCoast: "#eaf0f8"
  property color inkGrid:  "#2a4460"
  property color inkMark:  "#e8a37c"
  property color inkSea:   "#0d1a2e"

  // It takes no input at all, so a finger on it still reaches the sky behind.
  enabled: false
  renderStrategy: Canvas.Threaded
  renderTarget: Canvas.Image

  readonly property real cx: width / 2
  readonly property real cy: height / 2
  readonly property real rad: Math.min(width, height) / 2 - 1

  // Repaint only when the thing it draws actually moves. Not on `tod`, not on
  // the weather, not on the frame clock.
  onPlaceChanged: requestPaint()
  onWidthChanged: requestPaint()
  onVisibleChanged: if (visible) requestPaint()
  Component.onCompleted: requestPaint()

  // Orthographic projection of one hemisphere, centred on (lat0, lon0). Returns
  // null for anything on the far side, which is what breaks the strokes at the
  // limb without needing a separate clip.
  function project(latDeg, lonDeg, la0, lo0, sinLa0, cosLa0) {
    var la = latDeg * Math.PI / 180, lo = lonDeg * Math.PI / 180
    var dl = lo - lo0
    var cosLa = Math.cos(la), sinLa = Math.sin(la)
    var cosc = sinLa0 * sinLa + cosLa0 * cosLa * Math.cos(dl)
    if (cosc < 0) return null                       // the far hemisphere
    return [globe.cx + globe.rad * (cosLa * Math.sin(dl)),
            globe.cy - globe.rad * (cosLa0 * sinLa - sinLa0 * cosLa * Math.cos(dl))]
  }

  // One polyline, broken wherever it goes round the back. Also broken on a
  // jump longer than the radius, which is the antimeridian and the limb both:
  // two points can be visible and still not be neighbours on screen.
  function stroke(ctx, pts) {
    var started = false, px = 0, py = 0
    for (var i = 0; i < pts.length; i++) {
      var p = pts[i]
      if (p === null) { if (started) ctx.stroke(); started = false; continue }
      if (started && Math.abs(p[0] - px) + Math.abs(p[1] - py) > globe.rad) {
        ctx.stroke(); started = false
      }
      if (!started) { ctx.beginPath(); ctx.moveTo(p[0], p[1]); started = true }
      else ctx.lineTo(p[0], p[1])
      px = p[0]; py = p[1]
    }
    if (started) ctx.stroke()
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    if (!place || rad < 4) return

    var la0 = place.lat * Math.PI / 180, lo0 = place.lon * Math.PI / 180
    var s0 = Math.sin(la0), c0 = Math.cos(la0)
    var i, j, pts

    // the sphere itself, so the wireframe reads against a bright sky
    ctx.beginPath()
    ctx.arc(cx, cy, rad, 0, 2 * Math.PI)
    ctx.fillStyle = inkSea
    ctx.globalAlpha = 0.55
    ctx.fill()
    ctx.globalAlpha = 1.0

    // graticule, every thirty degrees; the equator and the central meridian
    // carry full strength so there is something to read the tilt against
    ctx.lineWidth = Math.max(0.6, rad * 0.014)
    ctx.strokeStyle = inkGrid
    for (var mer = -180; mer < 180; mer += 30) {
      ctx.globalAlpha = (mer === 0) ? 0.95 : 0.45
      pts = []
      for (j = -90; j <= 90; j += 3) pts.push(project(j, mer, la0, lo0, s0, c0))
      stroke(ctx, pts)
    }
    var parallels = [-60, -30, 0, 30, 60]
    for (i = 0; i < parallels.length; i++) {
      ctx.globalAlpha = (parallels[i] === 0) ? 0.95 : 0.45
      pts = []
      for (j = -180; j <= 180; j += 3)
        pts.push(project(parallels[i], j, la0, lo0, s0, c0))
      stroke(ctx, pts)
    }

    // the coast
    ctx.globalAlpha = 0.82
    ctx.lineWidth = Math.max(1.0, rad * 0.024)
    ctx.strokeStyle = inkCoast
    var sc = Coastline.scale
    for (i = 0; i < Coastline.paths.length; i++) {
      var path = Coastline.paths[i]
      pts = []
      for (j = 0; j < path.length; j += 2)
        pts.push(project(path[j + 1] / sc, path[j] / sc, la0, lo0, s0, c0))
      stroke(ctx, pts)
    }

    // the limb, drawn last so the coast does not spill past the edge
    ctx.globalAlpha = 0.75
    ctx.lineWidth = Math.max(0.8, rad * 0.018)
    ctx.strokeStyle = inkGrid
    ctx.beginPath()
    ctx.arc(cx, cy, rad, 0, 2 * Math.PI)
    ctx.stroke()

    // and you, at the centre by construction
    ctx.globalAlpha = 1.0
    ctx.fillStyle = inkMark
    ctx.beginPath()
    ctx.arc(cx, cy, Math.max(1.5, rad * 0.055), 0, 2 * Math.PI)
    ctx.fill()
    ctx.strokeStyle = inkMark
    ctx.lineWidth = Math.max(0.8, rad * 0.02)
    ctx.globalAlpha = 0.7
    ctx.beginPath()
    ctx.arc(cx, cy, Math.max(3.5, rad * 0.13), 0, 2 * Math.PI)
    ctx.stroke()
  }
}
