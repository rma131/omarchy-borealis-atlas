// Borealis Atlas — GPU-procedural sky over water.
//
// ORIGIN AND CREDIT. This file is a derivative of the aurora shader in
// marko-builds/borealis (MIT), by Marko Stankovic, which he ported from his own
// play/aurora.py via lookdev/index.html. 118 of his 171 substantive lines are
// still here unchanged, and the ones that matter most are entirely his:
//
//   ramp()     the six-stop colour interpolation, and the palettes it walks
//   curtain()  the aurora itself — not one character altered
//   meteors()  the streaks
//   vnoise()   value noise, used by everything
//   hash21()   the hash all of it is seeded from
//   dither()   the 8-bit banding fix on the dark gradients
//
// His too: the composition (curtains over a starfield, meteors, a crescent
// moon, a forested ridge standing on water that mirrors the sky), the layering
// order, and the choice to pass the palette as six vec4 uniforms rather than a
// const array — which is also why none of the additions below may introduce one.
//
// Added since: a touch field the light is sampled through, a real sun and moon
// on the day's true sunrise and sunset, a horizon fitted to measured elevation,
// water detected rather than assumed, snow above the freezing level, and
// weather. All of it built around his aurora, none of it replacing it.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;   // y = 0 at top
layout(location = 0) out vec4 fragColor;

// NO const arrays anywhere: the shell's OpenGL RHI translates this to old
// GLSL targets where constant-array initializers do not exist (runtime
// "C7516: OpenGL does not allow constant arrays" with a blank overlay,
// while qsb itself compiles clean). The palette arrives as six vec4
// uniforms (rgb + stop position in w) computed in QML — portable, and
// palette switching is live.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;
    vec4 stop0;
    vec4 stop1;
    vec4 stop2;
    vec4 stop3;
    vec4 stop4;
    vec4 stop5;
    vec4 skyBase;   // rgb used
    vec4 skyAmp;    // rgb used
    // Touch slots: xy = position in uv, z = birth stamp on the same clock as
    // `time`, w = 1.0 while the finger is still down. QML writes these only on
    // a real touch event; the age is derived here so a held or drifting finger
    // costs no per-frame uniform traffic.
    vec4 touch0;
    vec4 touch1;
    vec4 touch2;
    // Time of day as a fraction of 24 h: 0.00 midnight, 0.50 midday. Sunrise
    // and sunset are not fixed — they come from geo.zw. Seeded from the real
    // clock, dragged left to right.
    float tod;
    // Real sky data, resolved in QML so the shader needs no arrays or lookups.
    vec4 wx;      // x cloud cover, y rain, z snow, w thunder
    vec4 astro;   // x lunar phase (0 new .5 full), y aurora probability,
                  // z inspect reveal, w special-moon emphasis
    vec4 wx2;     // x wind (uv/s, signed), y wind gust, z fog, w lying snow
    vec4 ice;     // x frozen lake, y verglas, z sky angular speed, w spare
    // What the land here is like. Blended, not switched: the world has no hard
    // edges between a forest and a desert.
    vec4 land;    // x cold, y arid, z lush, w alpine
    // Where the place is, as opposed to what its weather is. relief is how
    // high the tallest thing in frame stands in apparent degrees, water whether
    // there is any, and the last two the day's real sunrise and sunset as
    // fractions of 24 h.
    vec4 geo;     // x relief, y water, z sunrise, w sunset
    // The skyline, measured rather than invented: twelve coefficients of a
    // half-range cosine fit to the real horizon around this place, sampled as
    // apparent angle over a 150-degree window facing whatever rises highest.
    // A cosine series and not a Fourier one because a Fourier fit forces
    // profile(0) == profile(1) and puts a seam down the edge of the frame.
    vec4 hills0;  // a0..a3
    vec4 hills1;  // a4..a7
    vec4 hills2;  // a8..a11
    // The two horizontal lines that cut across it. Both are fractions of the
    // ridge's own height, so 1.0 sits on the highest summit and anything above
    // that means the line is off the top of the land and does not apply.
    vec4 alt;     // x snowline, y treeline, z ridge rise in uv, w line softness
    // What the water in front of you is, if there is any. A river is a band you
    // stand back from, a lake reaches most of the way in, an ocean fills the
    // whole foreground — so the one number that carries the difference is how
    // far toward you it comes. At the waterline exactly, there is none.
    vec4 shore;   // x near bank in uv, y wave scale, z mirror compression, w spare
};

// The sun used to rise at 06:00 and set at 18:00 everywhere on earth, every
// day of the year: dayPhase was simply (td - 0.25) * 2.0. This maps the real
// sunrise and sunset onto the same 0..1-across-daylight axis, so everything
// downstream — day, gold, night, the arc, the cloud underlight, the glitter —
// keeps working unchanged and merely sits on a true day length.
// The clamp is what makes the polar circles safe: a 0.96 day is a sun that
// dips for an hour, which is what a Tromso June actually looks like.
float solarPhase(float td) {
  float dayLen = clamp(geo.w - geo.z, 0.04, 0.96);
  float x = fract(td - geo.z);                     // 0 at sunrise
  return (x < dayLen) ? x / dayLen
                      : 1.0 + (x - dayLen) / (1.0 - dayLen);
}

// How high it gets, which is a separate question from when it is up. A short
// winter day has to keep the sun low, and a polar night must never lift it above
// the horizon at all. Scaling only the duration gave polar night a brief
// blazing noon — worse than the fixed twelve-hour day it replaced.
// sin(altitude) has the form A + B cos(hour angle), and the day length fixes
// A/B on its own, because the sun is up exactly while the cosine clears -A/B.
float solarAlt(float td) {
  float f   = clamp(geo.w - geo.z, 0.0, 1.0);
  float mid = (geo.z + geo.w) * 0.5;               // local solar noon
  float c0  = cos(3.14159265 * f);
  // Normalised so a twelve-hour day still peaks at exactly 1.0 — the look this
  // grew out of — while the summer end is held back enough that a midnight sun
  // cannot climb out of the top of the frame.
  return (cos(6.28318531 * (td - mid)) - c0) / (1.0 + max(-c0, 0.0) * 0.85);
}

const float PI = 3.14159265;
// The land never thins to a hairline: the profile is normalised to its own
// range, so the lowest column would otherwise sit exactly on the waterline and
// a flat place would have no shore at all. The altitude lines are lifted onto
// the same scale, or the snowline would drift against the ridge it cuts.
const float RIDGE_BASE = 0.18;
const float WATERLINE = 0.82;
const float HORIZON  = 0.795;   // where sun and moon cross
const float SUN_ARC  = 0.62;    // how high the sun climbs at noon

// piecewise-linear ramp, aurora.py ramp()/np.interp — chained clamped mixes
// reproduce the 6-stop interp exactly (each clamp saturates before the next
// segment starts)
vec3 ramp(float p) {
  vec3 c = stop0.rgb;
  c = mix(c, stop1.rgb, clamp((p - stop0.w) / (stop1.w - stop0.w), 0.0, 1.0));
  c = mix(c, stop2.rgb, clamp((p - stop1.w) / (stop2.w - stop1.w), 0.0, 1.0));
  c = mix(c, stop3.rgb, clamp((p - stop2.w) / (stop3.w - stop2.w), 0.0, 1.0));
  c = mix(c, stop4.rgb, clamp((p - stop3.w) / (stop4.w - stop3.w), 0.0, 1.0));
  c = mix(c, stop5.rgb, clamp((p - stop4.w) / (stop5.w - stop4.w), 0.0, 1.0));
  return c;
}

float hash21(vec2 p) {
  p = fract(p * vec2(234.34, 435.345));
  p += dot(p, p + 34.23);
  return fract(p.x * p.y);
}

// breaks 8-bit banding on the dark gradients: +-0.5/255 of hash noise
vec3 dither(vec2 uv) {
  return vec3(hash21(uv * resolution) - 0.5) / 255.0;
}

// smooth 2D value noise — wind gusts on the water
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i),                 hash21(i + vec2(1.0, 0.0)), f.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Dawn keeps its real colours where it matters — the warm horizon and the sun
// are lit by physics, not by the theme. Only the cool half of the scene (the
// zenith and the shaded side of the cloud) takes a hint of the palette, so a
// warm palette reads as contrast against a cool sky and a cool one harmonises
// with it. Kept a hint on purpose: this is a sunrise, not a colour swap.
const float PALETTE_TINT = 0.30;
// Fallback drift when no wind data has arrived: the value this used to be
// hard-coded to, chosen to complement the brightest curtain's -0.030.
const float CLOUD_WIND = 0.0105;

// the palette's identity with its brightness divided out, so only hue carries
vec3 paletteSig() {
  vec3 c = stop2.rgb;
  return c / max(max(max(c.r, c.g), c.b), 0.001);
}

// Wispy cloud deck. Stretched hard in x so the bands run parallel to the
// curtains — texture rather than weather. Two octaves is plenty at this
// opacity, and it is held at zero through the night.
//
// Wind. The brightest curtain drifts left at ~0.030 uv/s (its ray term is
// sin(fx*23 + t*0.7), which travels at -rayS/rayF), so the deck goes the same
// way at about a third of that: one weather system seen at two altitudes, the
// far one lagging. Sampling at p.x + t*v moves content toward -x.
float cloudField(vec2 p, float t) {
  // a slow swell so the deck breathes instead of sliding as a rigid sheet
  float swell = sin(p.x * 3.0 + t * 0.05) * 0.006;
  // wx2.x is the true wind, signed, so the deck reverses when the wind does
  float wind = wx2.x;
  vec2 lo = vec2((p.x + t * wind) * 2.6, (p.y + swell) * 13.0);
  vec2 hi = vec2((p.x + t * wind * 0.45) * 5.3, (p.y - swell) * 26.0 + 4.7);
  return vnoise(lo) * 0.65 + vnoise(hi) * 0.35;
}

// ---- precipitation --------------------------------------------------------
// Composited in main() over the finished scene rather than inside upperScene:
// rain falls in FRONT of the water's reflection, so drawing it there is both
// more correct and skips the five reflection taps entirely.
float rainLayer(vec2 p, float t, float speed, float scale, float slant) {
  vec2 q = vec2((p.x + p.y * slant) * scale, p.y * scale * 0.55 - t * speed);
  vec2 c = floor(q), f = fract(q);
  float h = hash21(c);
  if (h < 0.62) return 0.0;
  float x = smoothstep(0.055, 0.0, abs(f.x - fract(h * 7.3)));
  // a short dash inside the cell, not a full-height scratch
  return x * smoothstep(0.0, 0.10, f.y) * smoothstep(0.60, 0.16, f.y);
}

float snowLayer(vec2 p, float t, float speed, float scale) {
  vec2 q = vec2(p.x * scale, p.y * scale - t * speed);
  vec2 c = floor(q), f = fract(q);
  float h = hash21(c);
  if (h < 0.62) return 0.0;
  // sway, so flakes drift rather than fall on rails
  vec2 ctr = vec2(fract(h * 7.3) + sin(t * 0.7 + h * 30.0) * 0.20, fract(h * 3.1));
  return smoothstep(0.17, 0.0, length(f - ctr));
}

// ---- touch: a repulsion field ------------------------------------------
// The finger is a repulsor in the aurora, not a lamp painted on top of it.
// Each slot contributes a radial field; the aurora is sampled through that
// field, so the curtains are pushed outward, and the field's DIVERGENCE drives
// emission: where the light piles up it burns brighter, where it is rarefied it
// thins out and the starfield behind reads through it.
//
// The guards test uniforms, not varyings, so with nothing touching the whole
// section costs three scalar compares and the scene renders exactly as stock.
const float RIPPLE_LIFE = 3.0;
const float WAVE_SPEED  = 0.34;
const float WAVE_K      = 55.0;
const float WAVE_TIGHT  = 700.0;
const float WAVE_AMP    = 0.028;
const float PUSH_AMP    = 0.115;   // how far a finger shoves the light
const float PUSH_SIGMA  = 0.10;    // tighter than the push => steeper gradient
const float COMPRESS    = 2.7;     // divergence -> emission
// Spring-back after release: the light overshoots and settles rather than
// snapping, which is what makes it read as displaced matter instead of a mask
// being switched off.
const float RELAX_TAU   = 0.26;
const float RELAX_OMEGA = 6.2;
const float RELAX_LIFE  = 1.3;

// How hard this slot is currently pushing. s.w encodes the state: > 0.5 means
// the finger is down, 0.0 means dead, and a negative value carries
// -(release time + 1) so the decay can be measured from it.
float holdOf(vec4 s, float t) {
  if (s.w > 0.5) return 1.0;
  if (s.w > -0.5) return 0.0;
  float u = t - (-s.w - 1.0);
  if (u < 0.0 || u > RELAX_LIFE) return 0.0;
  return exp(-u / RELAX_TAU) * cos(u * RELAX_OMEGA);
}

// xy = how far the light is pushed (aspect space), z = divergence of that push
vec3 touchField1(vec2 p, vec4 s, float t, float aspect) {
  float hold = holdOf(s, t);
  float age = t - s.z;
  bool waveLive = (age >= 0.0 && age <= RIPPLE_LIFE);
  if (hold == 0.0 && !waveLive) return vec3(0.0);

  vec2 q = p - vec2(s.x * aspect, s.y);
  float d = max(length(q), 1e-4);
  vec2 dir = q / d;

  // Standing repulsion under a held finger. The (d/sigma) factor makes the push
  // vanish at the exact centre, so the field stays smooth there instead of
  // going singular, and it peaks about a fingertip out.
  float g    = exp(-0.5 * d * d / (PUSH_SIGMA * PUSH_SIGMA));
  float bub  = PUSH_AMP * (d / PUSH_SIGMA) * g * hold;
  float dBub = (PUSH_AMP / PUSH_SIGMA) * g * (1.0 - d * d / (PUSH_SIGMA * PUSH_SIGMA)) * hold;

  // Travelling wave launched at touch-down; crests and troughs alternate
  // compression and rarefaction, which is what banks the light into rings.
  float ring = d - age * WAVE_SPEED;
  float env  = exp(-ring * ring * WAVE_TIGHT) * clamp(1.0 - age / RIPPLE_LIFE, 0.0, 1.0);
  float wav  = WAVE_AMP * sin(ring * WAVE_K) * env;
  float dWav = WAVE_AMP * WAVE_K * cos(ring * WAVE_K) * env;

  float mag = bub + wav;
  // divergence of the radial field mag*dir in 2D: d(mag)/dd + mag/d
  return vec3(dir * mag, (dBub + dWav) + mag / d);
}

vec3 touchField(vec2 p, float t, float aspect) {
  return touchField1(p, touch0, t, aspect)
       + touchField1(p, touch1, t, aspect)
       + touchField1(p, touch2, t, aspect);
}

// field -> (uv displacement, emission gain, how far the aurora has thinned)
vec4 fieldParams(vec3 fld, float aspect) {
  if (fld.z == 0.0) return vec4(fld.x / aspect, fld.y, 1.0, 0.0);
  float gain = clamp(exp(-COMPRESS * fld.z), 0.10, 5.0);
  return vec4(fld.x / aspect, fld.y, gain, clamp(1.0 - gain, 0.0, 1.0));
}

// One curtain layer — aurora.py Sky.frame l. 259-287
vec3 curtain(vec2 uv, float t,
             float baseY, float len, float alpha,
             vec3 f, vec3 a, vec3 s, float rayF, float rayS) {
  float fx = uv.x;
  float top = baseY
    + a.x * sin(fx * f.x * 6.28318 + t * s.x)
    + a.y * sin(fx * f.y * 6.28318 + t * s.y)
    + a.z * sin(fx * f.z * 6.28318 + t * s.z);
  float rel = (uv.y - top) / len;
  float inside = step(0.0, rel) * step(rel, 1.0);
  float b = clamp(1.0 - rel, 0.0, 1.0) * clamp(rel / 0.04, 0.0, 1.0) * inside;
  float rays = 0.55
    + 0.30 * sin(fx * rayF + t * rayS)
    + 0.15 * sin(fx * rayF * 2.3 - t * rayS * 1.7);
  b *= pow(clamp(rays, 0.0, 1.0), 1.6);
  b *= 0.75 + 0.25 * sin(t * 0.6 + baseY * 9.0);
  return ramp(rel) * b * alpha;
}

// Meteors — gather form of aurora.py _draw_meteors; two co-prime slots
vec3 meteors(vec2 uv, float t, float aspect) {
  vec3 acc = vec3(0.0);
  vec3 warm = vec3(1.0, 0.969, 0.894);
  for (int i = 0; i < 2; i++) {
    float P = (i == 0) ? 19.0 : 31.0;
    float cyc = floor(t / P) + float(i) * 7.0;
    float h1 = fract(sin(cyc * 12.9898) * 43758.5453);
    float h2 = fract(sin(cyc * 78.2330) * 12543.1230);
    float h3 = fract(sin(cyc * 39.4250) * 65231.7700);
    float t0 = (0.15 + 0.50 * h1) * P;
    float dur = 0.9 + 0.5 * h2;
    float p = (t - floor(t / P) * P - t0) / dur;
    if (p < 0.0 || p > 1.0) continue;
    float env = sqrt(sin(3.14159 * p));
    float theta = (0.20 + 0.25 * h3) * 3.14159;   // capped ~81deg, no plumb lines
    float sx = (h2 > 0.5) ? 1.0 : -1.0;
    vec2 start = vec2((0.05 + 0.90 * fract(h1 * 7.31)) * aspect,
                      0.02 + 0.40 * fract(h3 * 5.17));
    float dist = (0.25 + 0.25 * h2) * aspect;
    vec2 dir = normalize(vec2(cos(theta) * sx, sin(theta)));
    vec2 head = start + dir * dist * p;
    float tail = (0.07 + 0.05 * h1) * aspect;
    vec2 q = vec2(uv.x * aspect, uv.y) - head;
    float along = dot(q, -dir);
    float perp = length(q + dir * along);
    float ta = clamp(along / tail, 0.0, 1.0);
    float streak = (along > 0.0) ? pow(1.0 - ta, 2.0) : 0.0;
    streak *= exp(-perp * perp / (2.0 * 0.0000022));
    float bloom = exp(-dot(q, q) / (2.0 * 0.0000045));
    acc += warm * (streak * 1.3 + bloom * 1.5) * env * (0.8 + 0.5 * h3);
  }
  return acc;
}

// One sample of the starfield. Pulled out of upperScene so motion blur can take
// several of them along the direction the vault is turning; sampling the whole
// field is more robust than stretching a single cell, which clips its own trail
// at the cell boundary.
vec3 starsAt(vec2 uv, float t, float thin, float angOff) {
  float aspect = resolution.x / resolution.y;
  vec2 piv = vec2(0.5, 1.08);
  vec2 q = (uv - piv) * vec2(aspect, 1.0);
  float a = -tod * 1.10 + angOff;
  float ca = cos(a), sa = sin(a);
  q = vec2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);
  vec2 suv = piv + vec2(q.x / aspect, q.y);

  vec2 g = suv * resolution / 14.0;
  vec2 cell = floor(g);
  if (hash21(cell) <= 0.55) return vec3(0.0);
  vec2 pos = vec2(hash21(cell + 7.3), hash21(cell + 3.1));
  float d = length((fract(g) - pos) * 14.0);
  float mag = 0.3 + 0.7 * hash21(cell + 11.7);
  float twk = 0.55 + 0.45 * sin(t * (1.5 + 2.5 * hash21(cell + 5.2))
                                + 6.28318 * hash21(cell + 9.4));
  return smoothstep(1.2, 0.0, d) * mag * twk * 0.78 * vec3(0.85, 0.9, 1.0)
         * (1.0 + thin * 1.6);
}

// Everything above the waterline; the water mirrors this whole stack.
// fp = (duv.x, duv.y, emission gain, thinning)
vec3 upperScene(vec2 uv, float t, vec4 fp) {
  float aspect = resolution.x / resolution.y;

  // ---- where the sun and moon are, and therefore what kind of sky this is --
  // dayPhase runs 0 at sunrise to 1 at sunset; outside that the sine goes
  // negative and both bodies simply sit below the horizon, so the cycle needs
  // no special-casing for night.
  // tod is unbounded (QML lets it run past 1 so a drag through midnight does
  // not animate backwards through the whole day); wrap it for positions.
  float td        = fract(tod);
  float dayPhase  = solarPhase(td);
  float sunAlt    = solarAlt(td);
  vec2  sunUV     = vec2(mix(0.10, 0.90, clamp(dayPhase, 0.0, 1.0)),
                         HORIZON - sunAlt * SUN_ARC);

  // The moon's offset from the sun IS its phase: new rides with the sun, full
  // opposes it, first quarter transits at 18:00. The old fract(td + 0.5)
  // silently assumed a full moon every night.
  float lunar     = astro.x;
  float moonDay   = solarPhase(fract(td - lunar));
  float moonAlt   = solarAlt(fract(td - lunar));
  vec2  moonUV    = vec2(mix(0.10, 0.90, clamp(moonDay, 0.0, 1.0)),
                         HORIZON - moonAlt * SUN_ARC);

  float day   = smoothstep(-0.04, 0.32, sunAlt);        // 1 in full daylight
  // Snow and ice are bright under a moon, so winter is lit by whatever light is
  // actually up. Keying it to `day` alone made winter disappear at night.
  float moonLit = smoothstep(-0.05, 0.15, solarAlt(fract(td - astro.x)))
                * (0.15 + 0.85 * ((1.0 - cos(6.28318 * astro.x)) * 0.5));
  float lit = max(day, moonLit * 0.60);
  float gold  = exp(-sunAlt * sunAlt * 26.0);           // the golden-hour band
  float night = 1.0 - smoothstep(-0.20, 0.04, sunAlt);  // 1 in full night
  vec3  sig   = paletteSig();

  // sky: night as shipped, warmed through the golden hour, opening out to day
  vec3 col = skyBase.rgb + skyAmp.rgb * (1.0 - uv.y);
  if (day > 0.0 || gold > 0.002) {
    vec3 zen0 = vec3(0.07, 0.12, 0.30);
    // multiply rather than blend toward the hue: shifts colour, keeps luminance
    vec3 zenT = mix(zen0, zen0 * (0.45 + 0.95 * sig), PALETTE_TINT);
    vec3 goldSky = mix(zenT, vec3(0.98, 0.54, 0.26), smoothstep(0.05, 0.82, uv.y));
    vec3 daySky  = mix(vec3(0.22, 0.45, 0.86), vec3(0.74, 0.86, 0.96),
                       smoothstep(0.0, 0.85, uv.y));
    col = mix(col, daySky, day);
    col = mix(col, goldSky, gold * 0.80);
  }

  float starAmt = night;

  // starfield: sampled once when still, several times along the direction of
  // travel when the vault is turning fast enough to smear
  if (uv.y < 0.7 && starAmt > 0.0) {
    // Blur by winding the vault's ROTATION back and forth, not by sliding the
    // sample point: sliding lands each tap on a different cell, so seven
    // unrelated stars pile up dimly instead of one star drawing its arc. Turning
    // the angle instead traces the same star along the path it actually takes,
    // and the direction comes out tangential for free.
    float angSpan = min(ice.z * 1.10 / 60.0, 0.11);   // one frame of turning
    vec3 acc = vec3(0.0);
    if (angSpan > 0.0006) {
      for (int i = 0; i < 7; i++)
        acc += starsAt(uv, t, fp.w, (float(i) - 3.0) * angSpan * 0.1667);
      // a point smeared over a path is genuinely fainter; compensate only partly
      acc *= (1.0 / 7.0) * min(1.0 + angSpan * 20.0, 2.6);
    } else {
      acc = starsAt(uv, t, fp.w, 0.0);
    }
    col += acc * starAmt;
  }

  // ---- aurora: drawn here, beneath the moon and the cloud, because it is
  // 100 km up and the weather is not. Held in a variable so the cloud and the
  // ridge can be lit by it further down.
  vec3 auroraCol = vec3(0.0);
  float auroraAmt = night * max(astro.y, 0.0) * (1.0 + astro.z * 1.10);
  if (auroraAmt > 0.0) {
    // sampling at uv - duv moves the light outward, away from the finger
    vec2 cuv = uv - fp.xy;
    vec3 cur = curtain(cuv, t, 0.18, 0.55, 1.00,
                       vec3(1.3, 2.7, 5.1), vec3(0.05, 0.03, 0.015),
                       vec3(0.21, -0.13, 0.31), 23.0, 0.7)
             + curtain(cuv, t, 0.30, 0.42, 0.75,
                       vec3(0.9, 2.1, 4.3), vec3(0.06, 0.035, 0.02),
                       vec3(-0.15, 0.19, -0.27), 17.0, -0.5)
             + curtain(cuv, t, 0.42, 0.32, 0.55,
                       vec3(1.7, 3.3, 6.5), vec3(0.04, 0.025, 0.012),
                       vec3(0.11, -0.23, 0.17), 31.0, 0.9);
    auroraCol = cur * fp.z * auroraAmt;
    col += auroraCol;
  }

  // the moon, with a real terminator
  // a real moon is faintly there in daylight too, so the day fade is gentle
  float moonAmt = smoothstep(-0.06, 0.08, moonAlt) * (1.0 - day * 0.55);
  if (moonAmt > 0.0) {
    float r  = 0.055 * (1.0 + astro.w * 0.40);   // perigee + event emphasis
    vec2  mp = (uv - moonUV) * vec2(aspect, 1.0);
    float d1 = length(mp);
    float disc = smoothstep(r, r - 0.0035, d1);
    // The terminator projects to an ellipse whose x-radius is cos(2*pi*phase);
    // waxing lights the right limb, waning the left.
    vec2  q  = mp / r;
    float c  = cos(6.28318 * lunar);
    float xt = c * sqrt(max(0.0, 1.0 - q.y * q.y));
    float sunlit = (lunar < 0.5) ? smoothstep(xt - 0.06, xt + 0.06, q.x)
                                 : smoothstep(-xt + 0.06, -xt - 0.06, q.x);
    float illum = (1.0 - c) * 0.5;
    vec3 moonCol = vec3(0.95, 0.93, 0.85);
    // Earthshine is a ghost, not a grey disc: the unlit limb stays mostly
    // transparent so the sky shows through, and it only reads at all once the
    // sky is dark.
    // Markings are fixed in the moon's own frame, since it is tidally locked.
    // Deliberately barely there, and with no limb darkening: the disc should
    // stay a flat clean circle with just enough unevenness to not be a plain
    // white dot. Shading it like a sphere read as modelled, not minimal.
    float mar = vnoise(q * 2.1 + vec2(3.7, 1.9)) * 0.62
              + vnoise(q * 5.1 + vec2(8.1, 4.4)) * 0.38;
    float face = 1.0 - 0.065 * smoothstep(0.46, 0.90, mar);

    float ashen = 0.04 + 0.11 * night;
    col = mix(col, moonCol * face, disc * moonAmt * (ashen + (1.0 - ashen) * sunlit));
    // Close aureole, tight to the disc.
    col += moonCol * exp(-d1 * 38.0) * 0.085 * moonAmt * (0.25 + 0.75 * illum)
           * (1.0 + astro.w * 0.8);

    // And the halo proper: a faint ring thrown out at roughly 22 degrees by ice
    // crystals, which is what the disc alone was missing. Stronger through thin
    // cloud, because that is when you actually see one.
    float hRad = r * 3.3;
    float halo = exp(-pow((d1 - hRad) / (r * 0.66), 2.0));
    col += moonCol * halo * moonAmt * illum * (0.030 + 0.060 * wx.x);
  }

  // Cloud deck. Displaced by the touch field exactly like the curtains, so
  // pushing the sky slides the sunlit highlight across the cloud instead of the
  // cloud simply moving under a fixed glow. Held at zero through the night, so
  // the night scene costs exactly what it did before the cycle existed.
  // real cover overrides the fair-weather default, and holds through the night
  float cloudAmt = clamp(max(0.85 * day + 0.55 * gold, wx.x), 0.0, 1.0);
  cloudAmt *= 1.0 - astro.z * 0.88;            // inspect parts the deck
  if (cloudAmt > 0.02) {
    vec2 puv = uv - fp.xy;
    float cd = cloudField(puv, t);
    // Cover does two things: it lowers the threshold so the deck closes up
    // instead of staying wispy, and it widens the band vertically. Without
    // this, 95% cover still rendered as a few streaks over a sunny sky.
    cd = smoothstep(mix(0.60, 0.16, cloudAmt), mix(0.92, 0.52, cloudAmt), cd);
    float cTop = 0.16 - 0.12 * cloudAmt;
    float cBot = 0.60 + 0.18 * cloudAmt;
    cd *= smoothstep(cTop, cTop + 0.18, uv.y)
        * (1.0 - smoothstep(cBot, cBot + 0.18, uv.y));
    if (cd > 0.0) {
      // grazing sun gives red underlight, high sun gives white
      float prox = exp(-length((puv - sunUV) * vec2(aspect, 1.0)) * 2.4);
      vec3 lit    = mix(vec3(1.00, 0.42, 0.26), vec3(1.00, 0.97, 0.93),
                        smoothstep(0.0, 0.50, sunAlt));
      vec3 shade0 = mix(vec3(0.20, 0.19, 0.32), vec3(0.55, 0.60, 0.70), day);
      // a storm deck is bruised, not bright
      shade0 = mix(shade0, shade0 * 0.30, wx.w);
      vec3 shade  = mix(shade0, shade0 * (0.45 + 0.95 * sig), PALETTE_TINT);
      // the deck is lit from above by the aurora, so overcast auroral nights
      // read as glowing cloud rather than a hidden aurora
      shade += auroraCol * 1.30;
      // compression concentrates the highlight, same as it does the aurora
      vec3 cc = mix(shade, lit, clamp(prox * fp.z, 0.0, 1.0));
      col = mix(col, cc, cd * mix(0.55, 0.94, cloudAmt));
    }
  }

  // heavy weather kills the light
  col *= 1.0 - 0.50 * wx.w - 0.22 * max(0.0, wx.x - 0.55);

  // the sun itself, once it clears the horizon
  float sunAmt = smoothstep(-0.10, 0.01, sunAlt);
  if (sunAmt > 0.0) {
    vec2 sp = (uv - sunUV) * vec2(aspect, 1.0);
    float sd = length(sp);
    vec3 sunCol = mix(vec3(1.00, 0.58, 0.30), vec3(1.00, 0.96, 0.88),
                      smoothstep(0.0, 0.45, sunAlt));
    sunCol = mix(sunCol, sunCol * (0.72 + 0.46 * sig), 0.15);
    col += sunCol * exp(-sd *  9.0) * 0.30 * sunAmt;   // broad haze
    col += sunCol * exp(-sd * 42.0) * 0.55 * sunAmt;   // tight halo
    col = mix(col, vec3(1.0, 0.97, 0.90), smoothstep(0.030, 0.025, sd) * sunAmt);
  }

  // meteors streak over the curtains
  col += meteors(uv, t, aspect) * starAmt;

  // forested ridge standing on the waterline
  float fx = uv.x;
  // This used to be three sines with hand-tuned constants, scaled by one
  // relief number — so every place on earth got the same invented range, taller
  // or shorter. It is now the horizon that is actually out there: the cosine
  // series QML fitted to a fan of elevation samples, which puts Pichincha west
  // of Quito and one 177 m swell west of Montreal because that is where they
  // are. Written out flat rather than looped over an array: GLSL ES 1.00 will
  // not index a uniform array by a non-constant, and there is no need to.
  float rel = geo.x;
  float ridge = hills0.x
    + hills0.y * cos(PI *  1.0 * fx) + hills0.z * cos(PI *  2.0 * fx)
    + hills0.w * cos(PI *  3.0 * fx) + hills1.x * cos(PI *  4.0 * fx)
    + hills1.y * cos(PI *  5.0 * fx) + hills1.z * cos(PI *  6.0 * fx)
    + hills1.w * cos(PI *  7.0 * fx) + hills2.x * cos(PI *  8.0 * fx)
    + hills2.y * cos(PI *  9.0 * fx) + hills2.z * cos(PI * 10.0 * fx)
    + hills2.w * cos(PI * 11.0 * fx);
  ridge = RIDGE_BASE + (1.0 - RIDGE_BASE) * clamp(ridge, 0.0, 1.0);
  // A twelve-term fit is smooth by construction and rock is not, so the fine
  // detail stays synthetic — but only where the country is genuinely rugged.
  // Two octaves, because one gave an even scallop that read as dunes.
  ridge += rel * (0.042 * abs(sin(fx * 23.0 + 1.3))
                + 0.020 * abs(sin(fx * 51.0 + 4.7)));
  // alt.z is how tall all of that stands, in uv. Both ends of its range are
  // held in QML: even flat country has a horizon you can see, and the Alps
  // walling off the sky was a bug once already.
  float ridgeTop = WATERLINE - ridge * alt.z;

  // Altitude reads as a horizontal line across the picture, because that is
  // what a contour is: a snowline cuts straight through a range, it does not
  // drape itself over each crest in turn. Both lines are fractions of the
  // ridge's own height, so a value past 1.0 lifts the line clear of every
  // summit and it simply stops applying — which is Quito on nineteen days out
  // of twenty, and is why this needs no separate "has snow" flag.
  float snowY = WATERLINE - (RIDGE_BASE + (1.0 - RIDGE_BASE) * alt.x) * alt.z;
  float treeY = WATERLINE - (RIDGE_BASE + (1.0 - RIDGE_BASE) * alt.y) * alt.z;
  // Trees stand on the crest, so what decides whether they grow is the height
  // of the crest, not the height of the pixel. The band is wide where the ridge
  // is tall — about a tenth of its height, which is a couple of hundred metres
  // of altitude on a real mountain, and is roughly how long a treeline takes to
  // give up. At the snowline's width instead, the crossing was a knife edge:
  // one column of forest, then a vertical seam, then bare rock.
  float treeBand = max(alt.z * 0.10, 0.004);
  float aboveTree = smoothstep(treeY + treeBand, treeY - treeBand, ridgeTop);

  float tw = 170.0;
  float cell = floor(fx * tw);
  float hcell = hash21(vec2(cell, 3.7));
  // A hot wet coast grows palms. Drawn 170 across, a tree is a few pixels tall,
  // so shape can only mean proportion: taller, thinner and standing further
  // apart is the whole of what survives, and it is enough to read as a palm.
  // Genuinely hot, not merely green: lush reaches 0.72 around a 21 C mean, and
  // below that a temperate lakeside was growing palms.
  float palm = clamp((land.z - 0.72) * 3.0, 0.0, 1.0) * (1.0 - land.x) * geo.y;
  // Dry ground, bare rock and hard cold all thin the treeline out — and above
  // the treeline proper, nothing grows at all. The line is where it really is:
  // roughly 3500 m at the equator falling 40 m per degree of latitude, which
  // is why Quito's 2920 m floor is forest and the top of Pichincha is not.
  float bare = clamp(0.12 + 0.80 * max(land.y, land.w) + 0.40 * land.x
                     + 0.25 * palm, 0.0, 0.97);
  bare = mix(bare, 0.97, aboveTree);
  float grow = (1.0 - land.y) * (1.0 - 0.85 * land.w) * (0.45 + 0.75 * land.z);
  float th = (hcell < bare) ? 0.0
           : (0.004 + 0.012 * hcell) * clamp(grow, 0.15, 1.4) * (1.0 + 1.3 * palm);
  // Conifers come to a point where it is cold or high; broadleaf and palm
  // canopies are rounder, so the exponent carries the whole difference.
  float shp = mix(0.55, 2.3, clamp(land.x + land.w * 0.7, 0.0, 1.0));
  shp = mix(shp, 3.6, palm);
  float spike = pow(max(1.0 - abs(fract(fx * tw) * 2.0 - 1.0), 0.0), shp);
  float silTop = ridgeTop - th * spike;

  float px = 1.5 / resolution.y;
  float m = smoothstep(silTop - px, silTop + px, uv.y);
  if (m > 0.0) {
    float into = clamp((uv.y - ridgeTop) / max(1.0 - ridgeTop, 0.001), 0.0, 1.0);
    // Daylight ground, blended from what the climate implies rather than
    // chosen from a list: boreal green by default, sand as it dries, deep green
    // as it gets lush, bare rock as it rises.
    float dep = clamp(into * 1.7, 0.0, 1.0);
    vec3 gNear = mix(vec3(52.0, 66.0, 50.0), vec3(150.0, 124.0, 86.0), land.y);
    vec3 gFar  = mix(vec3(24.0, 34.0, 26.0), vec3( 98.0,  80.0, 56.0), land.y);
    gNear = mix(gNear, vec3(38.0, 80.0, 42.0), land.z);
    gFar  = mix(gFar,  vec3(16.0, 42.0, 24.0), land.z);
    // Bare rock is what is above the treeline, not what is high above the sea.
    // land.w still speaks for the ground you are standing on; aboveTree speaks
    // for the crest, and a valley floor under a bare summit needs both.
    float rock = max(land.w, aboveTree);
    gNear = mix(gNear, vec3(98.0, 100.0, 106.0), rock);
    gFar  = mix(gFar,  vec3(54.0,  57.0,  64.0), rock);
    // night keeps its blue, warmed a little over dry ground
    vec3 nNear = mix(vec3(11.0, 14.0, 24.0), vec3(22.0, 18.0, 20.0), land.y * 0.7);
    vec3 nFar  = mix(vec3( 4.0,  5.0,  9.0), vec3(10.0,  8.0,  8.0), land.y * 0.7);
    vec3 mtn = mix(mix(nNear, nFar, dep), mix(gNear, gFar, dep), day) / 255.0;
    mtn += vec3(0.030, 0.045, 0.060) * exp(-into * 50.0);
    mtn += auroraCol * 0.30;   // the land is bathed in it, not lit past it

    // Snow lies above the freezing level and nowhere else. This used to key off
    // land.w — the observer's own height above the sea — which put Quito at
    // alpine 1.0 and drew the entire city as grey rock under permanent caps.
    // Now it is one comparison against a real altitude, so the same mountain is
    // bare in the afternoon and white after a cold night, which is what it does.
    float capAmt = smoothstep(snowY + alt.w, snowY - alt.w, uv.y);
    if (capAmt > 0.0)
      mtn = mix(mtn, vec3(0.88, 0.91, 0.96) * (0.16 + 0.84 * lit), capAmt * 0.88);

    // Lying snow (snow_depth), which is a different thing from snow falling:
    // the slope goes white while the conifers stay dark, the way it looks.
    if (wx2.w > 0.0) {
      // `spike` is a sawtooth across the whole width, so masking by it alone
      // striped the entire slope. The conifers only break the crest, so the
      // dark-tree term is confined to the band just below the silhouette.
      float treeBand = exp(-into * 30.0);
      float tree = spike * step(0.0001, th) * treeBand;
      float lay  = clamp(wx2.w * (1.0 - 0.65 * tree), 0.0, 1.0);
      mtn = mix(mtn, vec3(0.86, 0.90, 0.96) * (0.16 + 0.84 * lit), lay * 0.92);
    }
    // Verglas: rain frozen onto the ground reads as a hard glassy sheen, not
    // the soft scatter of snow.
    if (ice.y > 0.0) {
      float gl = pow(max(0.0, 1.0 - abs(uv.x - sunUV.x) * 1.9), 10.0);
      mtn += vec3(0.55, 0.62, 0.74) * gl * ice.y * (0.18 + 0.82 * lit);
    }
    col = mix(col, mtn, m);
  }

  return col;
}

void main() {
  vec2 uv = qt_TexCoord0;
  float t = time;
  float aspect = resolution.x / resolution.y;
  vec2 tp = vec2(uv.x * aspect, uv.y);   // aspect-corrected, for touch only
  // One screen-space field per frame: the water's surface chop, the sky's
  // displacement and the precipitation all read the same disturbance. It used
  // to be evaluated separately in both branches.
  vec3 screenFld = touchField(tp, t, aspect);

  // where the light is, for the water's glitter column and the fog's colour
  float td       = fract(tod);
  float dayPhase = solarPhase(td);
  float sunAlt   = solarAlt(td);
  vec2  sunUV    = vec2(mix(0.10, 0.90, clamp(dayPhase, 0.0, 1.0)),
                        HORIZON - sunAlt * SUN_ARC);
  float moonDay  = solarPhase(fract(td - astro.x));
  float moonAlt  = solarAlt(fract(td - astro.x));
  vec2  moonUV   = vec2(mix(0.10, 0.90, clamp(moonDay, 0.0, 1.0)),
                        HORIZON - moonAlt * SUN_ARC);
  float day      = smoothstep(-0.04, 0.32, sunAlt);
  float moonLit  = smoothstep(-0.05, 0.15, moonAlt)
                 * (0.15 + 0.85 * ((1.0 - cos(6.28318 * astro.x)) * 0.5));
  float lit      = max(day, moonLit * 0.60);

  vec3 col;

  // A lake in the Sahara was the last thing in the scene that ignored where you
  // are — and then a lake in Quito, which is drier only in the sense that it
  // has no lake. Wet or dry is a property of the place, not something that
  // animates, so this is a hard branch and neither path ever costs the other.
  // shore.x is where the water stops on its way toward you: the bottom of the
  // frame for an ocean, a bank part way in for a river, and the waterline
  // itself where there is no water, which switches this branch off entirely.
  float bank = max(shore.x, WATERLINE);
  if (uv.y >= WATERLINE && uv.y < bank) {
    // water: stretched mirror of the upper scene, rippled, gust-blurred,
    // shimmer-broken, darkening with depth
    float span = max(bank - WATERLINE, 0.001);
    float depth = (uv.y - WATERLINE) / span;
    // How hard the mirror is squashed says how wide the water is: a channel
    // gives back a short section of sky, an ocean a long one.
    float K = shore.z;
    vec2 ruv = vec2(uv.x, WATERLINE - (uv.y - WATERLINE) * K);
    // A frozen lake has no ripple, no chop, and gives nothing back to a
    // finger pushed across it — which is most of what makes ice read as ice.
    float liquid = 1.0 - ice.x;
    // Wave scale, from the size of the body: an ocean has a long swell, a
    // river a fine quick chop. The frequencies divide by it and the amplitudes
    // multiply, so both ends stay wave-shaped rather than merely bigger.
    float wv = shore.y;
    ruv.x += (0.0015 + 0.004 * depth) * wv
             * sin(uv.y * 34.0 / wv + t * 1.4)
             * sin(uv.y * 11.0 / wv - t * 0.9) * liquid;
    ruv.y += 0.004 * depth * wv * sin(uv.x * 18.0 / wv + uv.y * 26.0 + t * 0.8) * liquid;
    // Surface chop where the finger actually meets the water, on screen.
    ruv.x += screenFld.x * 0.30 * liquid;
    ruv.y += screenFld.y * 0.22 * liquid;
    ruv = clamp(ruv, 0.0, 1.0);

    // 5 taps at tight spacing (sparse wide taps ghost thin features);
    // gusts scale the spacing mildly
    float gust = vnoise(vec2(uv.x * 6.0 - t * 0.18, uv.y * 3.0 + t * 0.06));
    float s = (0.003 + 0.005 * depth) * (0.7 + 0.6 * gust) * shore.y;
    // The reflection carries the same disturbance: evaluate the field once at
    // the mirrored sky point and let all five taps share it. The taps sit a few
    // thousandths apart — far finer than the field varies — so evaluating it
    // per tap would cost five times as much for no visible difference.
    vec4 rfp = fieldParams(touchField(vec2(ruv.x * aspect, ruv.y), t, aspect), aspect);
    vec3 refl = upperScene(ruv, t, rfp) * 0.30
              + upperScene(vec2(ruv.x, clamp(ruv.y - s, 0.0, 1.0)), t, rfp) * 0.22
              + upperScene(vec2(ruv.x, clamp(ruv.y + s, 0.0, 1.0)), t, rfp) * 0.22
              + upperScene(vec2(ruv.x, clamp(ruv.y - 2.0 * s, 0.0, 1.0)), t, rfp) * 0.13
              + upperScene(vec2(ruv.x, clamp(ruv.y + 2.0 * s, 0.0, 1.0)), t, rfp) * 0.13;

    float cx = uv.x * 48.0;
    float ci = floor(cx);
    float cf = fract(cx); cf = cf * cf * (3.0 - 2.0 * cf);
    float colPhase = 3.5 * mix(hash21(vec2(ci, 0.0)), hash21(vec2(ci + 1.0, 0.0)), cf);
    float shimmer = 0.86 + 0.14 * sin(uv.y * 38.0 + colPhase + t * 1.8);
    shimmer *= 0.94 + 0.06 * sin(uv.y * 9.0 - t * 1.1 + colPhase * 0.7);

    // Warm shallow water runs turquoise, cold water runs to steel.
    col *= mix(vec3(1.0), vec3(0.70, 1.08, 1.10), land.z * 0.85);
    col *= mix(vec3(1.0), vec3(0.88, 0.95, 1.08), land.x * 0.6);

    shimmer = mix(shimmer, 1.0, ice.x);      // ice does not shimmer
    col = refl * shimmer * (0.62 - 0.34 * depth) + vec3(0.010, 0.018, 0.038);
    col += vec3(0.05, 0.08, 0.10) * smoothstep(0.015, 0.0, uv.y - WATERLINE);
    // and a matching brightening where it meets the near bank, so a river does
    // not simply stop against the ground
    col += vec3(0.04, 0.06, 0.08) * smoothstep(0.012, 0.0, bank - uv.y)
           * step(bank, 0.995);

    // Glitter: whichever light is actually up lays a broken column toward the
    // viewer, widening with depth. The water's own facet noise stands in for
    // the slope of each wavelet, so this costs one noise lookup.
    float sA = smoothstep(-0.02, 0.12, sunAlt);
    float mA = smoothstep(-0.02, 0.12, moonAlt) * (1.0 - day * 0.75);
    float gAmt = max(sA, mA);
    if (gAmt > 0.0 && ice.x < 0.999) {
      vec2  gUV = (sA >= mA) ? sunUV : moonUV;
      vec3  gCol = (sA >= mA) ? vec3(1.00, 0.88, 0.66) : vec3(0.82, 0.86, 0.95);
      float w  = 0.035 + 0.34 * depth;
      float dx = (uv.x - gUV.x) * aspect;
      float column = exp(-dx * dx / (w * w));
      float facet = vnoise(vec2(uv.x * 62.0 + t * 0.7, uv.y * 190.0 - t * 2.3));
      // a low light glitters hardest; overhead it just brightens the water
      float lowness = 1.0 - smoothstep(0.10, 0.75, max(sunAlt, moonAlt));
      col += gCol * column * smoothstep(0.56, 0.93, facet)
             * gAmt * (0.35 + 0.95 * lowness) * (1.0 - ice.x);
    }

    // Frozen: the mirror goes matte and pale, and the depth gradient flattens.
    if (ice.x > 0.0) {
      vec3 iceCol = mix(col, vec3(0.62, 0.70, 0.80) * (0.14 + 0.86 * lit), 0.78);
      col = mix(col, iceCol, ice.x);
    }
  } else if (uv.y >= WATERLINE) {
    // ---- the ground you are standing on, where water does not reach -------
    // Everything from the near bank down: the whole foreground where there is
    // no water at all, a strip of bank in front of a river, nothing at all
    // under an ocean. What it is made of comes from the climate rather than
    // from a choice — crested dunes where it is genuinely arid, smooth pasture
    // where it is not, stone where it is cold. The Sahara and the paramo above
    // Quito are the same code with different numbers.
    float near = (uv.y - bank) / max(1.0 - bank, 0.001);
    // Crest lines run across the sand and crowd toward the horizon. Distance
    // along a ground plane goes as 1/depth, which is what makes them crowd;
    // pow(near, k) does the exact opposite and drew fine corduroy at the
    // viewer's feet instead. Each line wanders in x, more so nearby where
    // there is room for it, so the field does not read as a ruler.
    float persp = 1.0 / (0.085 + near * 0.92);
    float wob   = 0.30 * sin(uv.x * 4.1 + 0.7) + 0.15 * sin(uv.x * 8.3 + 2.9)
                + 0.07 * sin(uv.x * 15.7 + 1.4);
    // the wander must not die at the horizon or the far crests draw as rules
    float h     = fract(persp * 0.62 + wob * (0.35 + 0.65 * near));

    // A dune is not a sine: the windward side climbs slowly over most of the
    // spacing and the lee face drops away in one steep shadowed step. Wet
    // ground has no such thing, so aridity flattens the lee face out into a
    // gentle swell and what is left reads as pasture rolling away.
    float dune = clamp(land.y * 1.6, 0.0, 1.0);
    float face = mix(smoothstep(0.10, 0.90, h) - 0.30 * smoothstep(0.90, 1.0, h),
                     smoothstep(0.02, 0.68, h) - 0.85 * smoothstep(0.68, 0.88, h),
                     dune);
    // a low sun rakes across them and the relief is everything; overhead it
    // flattens out, which is exactly how a dune field looks at noon
    // Dune relief lives or dies by a raking light; pasture keeps a floor under
    // it, because a field at noon still has form and at 0.30 the near bank drew
    // as one flat green block.
    float rake = (0.34 + 0.58 * (1.0 - smoothstep(0.05, 0.55, sunAlt)))
               * (0.55 + 0.45 * dune);
    // Where the rows compress past a pixel the crest lines alias into a moire
    // of hairlines, so the relief is faded out into the distance instead.
    rake *= smoothstep(0.0, 0.18, near);
    float shade = 1.0 + (face - 0.45) * rake;

    // and a slight bias toward wherever the light actually is, so the field has
    // a direction rather than being lit from nowhere
    float sAd = smoothstep(-0.02, 0.12, sunAlt);
    float mAd = smoothstep(-0.02, 0.12, moonAlt) * (1.0 - day * 0.75);
    vec2  lUV = (sAd >= mAd) ? sunUV : moonUV;
    float toL = clamp((lUV.x - uv.x) * 2.2, -1.0, 1.0);
    shade *= 1.0 + 0.12 * toL * sin(uv.x * 4.1 + 0.7);

    // Sand at noon is bright, but the far sand has to meet the ridge's own
    // ground colour or the old waterline shows as a hard seam across the
    // desert. Distance hazes it toward that tone, which is both the fix and
    // what atmospheric perspective actually does.
    float toward = smoothstep(0.0, 0.45, near);
    vec3 sand  = mix(vec3(0.46, 0.41, 0.30), vec3(0.80, 0.70, 0.51), toward);
    vec3 stony = mix(vec3(0.40, 0.39, 0.36), vec3(0.66, 0.63, 0.57), toward);
    // Grass, for the ground that is dry only in the sense of having no lake.
    // Deepened by lush the same way the ridge is, so the foreground and the
    // slope behind it agree about what grows here.
    vec3 turf  = mix(vec3(0.22, 0.29, 0.18), vec3(0.38, 0.46, 0.27), toward);
    turf = mix(turf, mix(vec3(0.16, 0.30, 0.16), vec3(0.28, 0.48, 0.26), toward),
               land.z);
    sand = mix(turf, sand, dune);
    sand = mix(sand, stony, land.x);
    vec3 nightSand = mix(vec3(0.055, 0.062, 0.095), vec3(0.028, 0.032, 0.052), near);
    col = mix(nightSand, sand, day) * shade;

    // One tap of the sky, doing two jobs: the light the sand is bathed in, and
    // — where it is hot enough — the mirage, which is nothing but a false
    // reflection. The lake spends five taps here; this spends one.
    vec2 muv = vec2(uv.x, WATERLINE - (uv.y - bank) * 3.2);
    muv.x += 0.004 * sin(uv.y * 40.0 + t * 2.6);
    muv.x += screenFld.x * 0.22;
    vec3 sky1 = upperScene(clamp(muv, 0.0, 1.0), t, fieldParams(screenFld, aspect));
    float band = exp(-near * 9.0);                 // hugs the far edge
    float heat = clamp((1.0 - land.x) * land.y, 0.0, 1.0) * day;
    col += sky1 * 0.16 * band;
    col = mix(col, sky1 * 0.92, heat * band * 0.55);

    // Two grains: the fine one is sand, the coarse one is the clumping of
    // grass and scrub, and aridity decides which of them you are looking at.
    float grain = vnoise(vec2(uv.x * 180.0, uv.y * 90.0));
    float clump = vnoise(vec2(uv.x * 22.0, uv.y * 46.0 + 3.1));
    col *= 0.94 + 0.12 * grain;
    col *= mix(0.90 + 0.20 * clump, 1.0, dune);

    // A snowy steppe is a real place, so lying snow still whitens the ground.
    if (wx2.w > 0.0)
      col = mix(col, vec3(0.86, 0.89, 0.95) * (0.14 + 0.86 * lit), wx2.w * 0.85);
  } else {
    col = upperScene(uv, t, fieldParams(screenFld, aspect));
  }

  // Fog sits in the air between you and the scene, so it goes on before the
  // precipitation but after everything else, thickening toward the water.
  if (wx2.z > 0.0) {
    vec3 fogCol = mix(vec3(0.50, 0.53, 0.58), vec3(0.82, 0.86, 0.90), day);
    col = mix(col, fogCol, wx2.z * smoothstep(0.26, 0.86, uv.y) * 0.88);
  }

  // ---- weather, over everything, displaced by the same finger -------------
  vec2 wp = tp - screenFld.xy * 0.7;
  // rain and snow lean with the wind rather than falling on rails
  float lean = clamp(wx2.x * 26.0, -0.85, 0.85);
  if (wx.y > 0.0) {
    float r = rainLayer(wp, t, 1.5, 30.0, 0.22 + lean) * 0.55
            + rainLayer(wp, t, 2.3, 46.0, 0.28 + lean) * 0.32;
    col += vec3(0.56, 0.66, 0.82) * r * wx.y * 0.80;
    // and it dapples the water it lands on
    if (uv.y >= WATERLINE && uv.y < max(shore.x, WATERLINE)) {
      float dp = vnoise(vec2(uv.x * 110.0, uv.y * 260.0 + t * 7.0));
      col += vec3(0.09, 0.12, 0.15) * smoothstep(0.60, 0.96, dp) * wx.y;
    }
  }
  if (wx.z > 0.0) {
    // snow is light enough that the wind carries it sideways
    vec2 swp = vec2(wp.x + wp.y * lean * 1.6, wp.y);
    float sn = snowLayer(swp, t, 0.22, 20.0) * 0.70
             + snowLayer(swp, t, 0.34, 31.0) * 0.45;
    col += vec3(0.92, 0.95, 1.00) * sn * wx.z;
  }
  if (wx.w > 0.0) {
    // gate each strike on a hash of the period so they are not metronomic
    float per   = floor(t * 0.31);
    float ph    = fract(t * 0.31);
    float fire  = step(hash21(vec2(per, 11.0)), wx.w * 0.55);
    float flash = fire * exp(-ph * 26.0) * (0.55 + 0.45 * hash21(vec2(per, 3.0)));
    col += vec3(0.72, 0.78, 1.00) * flash * 0.60;
  }

  fragColor = vec4(clamp(col + dither(uv), 0.0, 1.0), 1.0) * qt_Opacity;
}
