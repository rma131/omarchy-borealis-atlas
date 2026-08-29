// Borealis — GPU-procedural aurora over water, ported from play/aurora.py
// via lookdev/index.html (the browser page holds the tuning history).
// Composition: curtains + stars + meteors + crescent moon + water + forested
// ridge. Five palettes baked as constants, selected by the paletteIndex
// uniform (single config surface, switches live).
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
    // Time of day as a fraction of 24 h: 0.00 midnight, 0.25 sunrise,
    // 0.50 noon, 0.75 sunset. Seeded from the real clock, dragged left to right.
    float tod;
    // Real sky data, resolved in QML so the shader needs no arrays or lookups.
    vec4 wx;      // x cloud cover, y rain, z snow, w thunder
    vec4 astro;   // x lunar phase (0 new .5 full), y aurora probability,
                  // z inspect reveal, w special-moon emphasis
    vec4 wx2;     // x wind (uv/s, signed), y wind gust, z fog, w lying snow
    vec4 ice;     // x frozen lake, y verglas, zw spare
};

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
  float dayPhase  = (td - 0.25) * 2.0;
  float sunAlt    = sin(dayPhase * 3.14159265);
  vec2  sunUV     = vec2(mix(0.10, 0.90, dayPhase), HORIZON - sunAlt * SUN_ARC);

  // The moon's offset from the sun IS its phase: new rides with the sun, full
  // opposes it, first quarter transits at 18:00. The old fract(td + 0.5)
  // silently assumed a full moon every night.
  float lunar     = astro.x;
  float moonDay   = (fract(td - lunar) - 0.25) * 2.0;
  float moonAlt   = sin(moonDay * 3.14159265);
  vec2  moonUV    = vec2(mix(0.10, 0.90, moonDay), HORIZON - moonAlt * SUN_ARC);

  float day   = smoothstep(-0.04, 0.32, sunAlt);        // 1 in full daylight
  // Snow and ice are bright under a moon, so winter is lit by whatever light is
  // actually up. Keying it to `day` alone made winter disappear at night.
  float moonLit = smoothstep(-0.05, 0.15, sin(((fract(td - astro.x)) - 0.25) * 2.0 * 3.14159265))
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

  // starfield (hash gather; ~14px cells, kept above 0.7 height)
  if (uv.y < 0.7 && starAmt > 0.0) {
    // the vault turns through the night rather than snapping between states
    vec2 piv = vec2(0.5, 1.08);
    vec2 q = (uv - piv) * vec2(aspect, 1.0);
    float a = -tod * 1.10;
    float ca = cos(a), sa = sin(a);
    q = vec2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);
    vec2 suv = piv + vec2(q.x / aspect, q.y);

    vec2 g = suv * resolution / 14.0;
    vec2 cell = floor(g);
    float h = hash21(cell);
    if (h > 0.55) {
      vec2 pos = vec2(hash21(cell + 7.3), hash21(cell + 3.1));
      float d = length((fract(g) - pos) * 14.0);
      float mag = 0.3 + 0.7 * hash21(cell + 11.7);
      float twk = 0.55 + 0.45 * sin(t * (1.5 + 2.5 * hash21(cell + 5.2))
                                    + 6.28318 * hash21(cell + 9.4));
      col += smoothstep(1.2, 0.0, d) * mag * twk * 0.78 * vec3(0.85, 0.9, 1.0)
              * (1.0 + fp.w * 1.6) * starAmt;
    }
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
    // The moon is tidally locked, so its markings are fixed in its own frame.
    // Two octaves of maria plus limb darkening: enough that it reads as a lit
    // sphere with a face rather than a white sticker, low-contrast enough that
    // it never becomes a texture map.
    float mar = vnoise(q * 2.3 + vec2(3.7, 1.9)) * 0.62
              + vnoise(q * 5.7 + vec2(8.1, 4.4)) * 0.38;
    float face = (1.0 - 0.17 * smoothstep(0.44, 0.86, mar))
               * (1.0 - 0.28 * smoothstep(0.52, 1.03, length(q)));

    float ashen = 0.04 + 0.11 * night;
    col = mix(col, moonCol * face, disc * moonAmt * (ashen + (1.0 - ashen) * sunlit));
    col += moonCol * exp(-d1 * 34.0) * 0.10 * moonAmt * (0.25 + 0.75 * illum)
           * (1.0 + astro.w * 0.8);
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
  float ridge = 0.5
    + 0.30 * sin(fx * 3.1 + 0.6)
    + 0.12 * sin(fx * 7.7 + 2.0)
    + 0.06 * sin(fx * 15.3 + 4.1);
  ridge /= 0.98;
  float ridgeTop = WATERLINE - ridge * 0.20;

  float tw = 170.0;
  float cell = floor(fx * tw);
  float hcell = hash21(vec2(cell, 3.7));
  float th = (hcell < 0.12) ? 0.0 : 0.005 + 0.011 * hcell;
  float spike = 1.0 - abs(fract(fx * tw) * 2.0 - 1.0);
  float silTop = ridgeTop - th * spike;

  float px = 1.5 / resolution.y;
  float m = smoothstep(silTop - px, silTop + px, uv.y);
  if (m > 0.0) {
    float into = clamp((uv.y - ridgeTop) / max(1.0 - ridgeTop, 0.001), 0.0, 1.0);
    vec3 mtn = mix(mix(vec3(11.0, 14.0, 24.0), vec3(4.0, 5.0, 9.0),
                       clamp(into * 1.7, 0.0, 1.0)),
                   mix(vec3(52.0, 66.0, 50.0), vec3(24.0, 34.0, 26.0),
                       clamp(into * 1.7, 0.0, 1.0)), day) / 255.0;
    mtn += vec3(0.030, 0.045, 0.060) * exp(-into * 50.0);
    mtn += auroraCol * 0.30;   // the land is bathed in it, not lit past it

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
  float dayPhase = (td - 0.25) * 2.0;
  float sunAlt   = sin(dayPhase * 3.14159265);
  vec2  sunUV    = vec2(mix(0.10, 0.90, dayPhase), HORIZON - sunAlt * SUN_ARC);
  float moonDay  = (fract(td - astro.x) - 0.25) * 2.0;
  float moonAlt  = sin(moonDay * 3.14159265);
  vec2  moonUV   = vec2(mix(0.10, 0.90, moonDay), HORIZON - moonAlt * SUN_ARC);
  float day      = smoothstep(-0.04, 0.32, sunAlt);
  float moonLit  = smoothstep(-0.05, 0.15, moonAlt)
                 * (0.15 + 0.85 * ((1.0 - cos(6.28318 * astro.x)) * 0.5));
  float lit      = max(day, moonLit * 0.60);

  vec3 col;

  if (uv.y >= WATERLINE) {
    // water: stretched mirror of the upper scene, rippled, gust-blurred,
    // shimmer-broken, darkening with depth
    float depth = (uv.y - WATERLINE) / (1.0 - WATERLINE);
    float K = 3.2;
    vec2 ruv = vec2(uv.x, WATERLINE - (uv.y - WATERLINE) * K);
    // A frozen lake has no ripple, no chop, and gives nothing back to a
    // finger pushed across it — which is most of what makes ice read as ice.
    float liquid = 1.0 - ice.x;
    ruv.x += (0.0015 + 0.004 * depth)
             * sin(uv.y * 34.0 + t * 1.4)
             * sin(uv.y * 11.0 - t * 0.9) * liquid;
    ruv.y += 0.004 * depth * sin(uv.x * 18.0 + uv.y * 26.0 + t * 0.8) * liquid;
    // Surface chop where the finger actually meets the water, on screen.
    ruv.x += screenFld.x * 0.30 * liquid;
    ruv.y += screenFld.y * 0.22 * liquid;
    ruv = clamp(ruv, 0.0, 1.0);

    // 5 taps at tight spacing (sparse wide taps ghost thin features);
    // gusts scale the spacing mildly
    float gust = vnoise(vec2(uv.x * 6.0 - t * 0.18, uv.y * 3.0 + t * 0.06));
    float s = (0.003 + 0.005 * depth) * (0.7 + 0.6 * gust);
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

    shimmer = mix(shimmer, 1.0, ice.x);      // ice does not shimmer
    col = refl * shimmer * (0.62 - 0.34 * depth) + vec3(0.010, 0.018, 0.038);
    col += vec3(0.05, 0.08, 0.10) * smoothstep(0.015, 0.0, uv.y - WATERLINE);

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
    if (uv.y >= WATERLINE) {
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
