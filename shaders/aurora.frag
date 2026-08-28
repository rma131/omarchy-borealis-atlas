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
    // 0 = night as shipped, 1 = full dawn. Driven by dragging up/down.
    float dawn;
};

const float WATERLINE = 0.82;

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

  // sky gradient, warmed toward a dawn horizon as the vault turns
  vec3 col = skyBase.rgb + skyAmp.rgb * (1.0 - uv.y);
  if (dawn > 0.0) {
    vec3 dsky = mix(vec3(0.05, 0.09, 0.24), vec3(0.98, 0.54, 0.26),
                    smoothstep(0.05, 0.82, uv.y));
    col = mix(col, dsky, dawn);
  }
  // stars and meteors wash out as the sky lightens
  float starAmt = 1.0 - smoothstep(0.10, 0.62, dawn);

  // starfield (hash gather; ~14px cells, kept above 0.7 height)
  if (uv.y < 0.7 && starAmt > 0.0) {
    // the celestial vault turns about a pole below the horizon
    vec2 suv = uv;
    if (dawn > 0.0) {
      vec2 piv = vec2(0.5, 1.08);
      vec2 q = (uv - piv) * vec2(aspect, 1.0);
      float a = -dawn * 0.40;
      float ca = cos(a), sa = sin(a);
      q = vec2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);
      suv = piv + vec2(q.x / aspect, q.y);
    }
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

  // crescent moon: pale disc minus offset disc, gentle halo; occludes stars
  float moonAmt = 1.0 - smoothstep(0.30, 0.88, dawn);
  if (moonAmt > 0.0) {
    vec2 mp = (uv - (vec2(0.78, 0.16) + dawn * vec2(0.10, 0.38))) * vec2(aspect, 1.0);
    float r = 0.055;
    float d1 = length(mp);
    float d2 = length(mp - vec2(0.020, -0.009));
    float crescent = clamp(smoothstep(r, r - 0.004, d1)
                         - smoothstep(r * 1.04, r * 1.04 - 0.004, d2), 0.0, 1.0);
    vec3 moonCol = vec3(0.95, 0.93, 0.85);
    col = mix(col, moonCol, crescent * moonAmt);
    col += moonCol * exp(-d1 * 34.0) * 0.10 * moonAmt;
  }

  // a far sun climbing out of the ridge on the other side
  float sunAmt = smoothstep(0.18, 0.62, dawn);
  if (sunAmt > 0.0) {
    vec2 sp = (uv - vec2(0.28, 1.10 - dawn * 0.82)) * vec2(aspect, 1.0);
    float sd = length(sp);
    vec3 sunCol = vec3(1.0, 0.86, 0.60);
    col += sunCol * exp(-sd *  9.0) * 0.30 * sunAmt;   // broad haze
    col += sunCol * exp(-sd * 42.0) * 0.55 * sunAmt;   // tight halo
    col = mix(col, vec3(1.0, 0.97, 0.90), smoothstep(0.030, 0.025, sd) * sunAmt);
  }

  // three curtain layers, aurora.py self.layers
  // sampling at uv - duv moves the light outward, away from the finger
  vec2 cuv = uv - fp.xy;
  // accumulate the three layers, then apply the emission gain once
  vec3 cur = curtain(cuv, t, 0.18, 0.55, 1.00,
                     vec3(1.3, 2.7, 5.1), vec3(0.05, 0.03, 0.015),
                     vec3(0.21, -0.13, 0.31), 23.0, 0.7)
           + curtain(cuv, t, 0.30, 0.42, 0.75,
                     vec3(0.9, 2.1, 4.3), vec3(0.06, 0.035, 0.02),
                     vec3(-0.15, 0.19, -0.27), 17.0, -0.5)
           + curtain(cuv, t, 0.42, 0.32, 0.55,
                     vec3(1.7, 3.3, 6.5), vec3(0.04, 0.025, 0.012),
                     vec3(0.11, -0.23, 0.17), 31.0, 0.9);
  col += cur * fp.z * (1.0 - smoothstep(0.12, 0.72, dawn));

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
    vec3 mtn = mix(vec3(11.0, 14.0, 24.0), vec3(4.0, 5.0, 9.0),
                   clamp(into * 1.7, 0.0, 1.0)) / 255.0;
    mtn += vec3(0.030, 0.045, 0.060) * exp(-into * 50.0);
    col = mix(col, mtn, m);
  }

  return col;
}

void main() {
  vec2 uv = qt_TexCoord0;
  float t = time;
  float aspect = resolution.x / resolution.y;
  vec2 tp = vec2(uv.x * aspect, uv.y);   // aspect-corrected, for touch only
  vec3 col;

  if (uv.y >= WATERLINE) {
    // water: stretched mirror of the upper scene, rippled, gust-blurred,
    // shimmer-broken, darkening with depth
    float depth = (uv.y - WATERLINE) / (1.0 - WATERLINE);
    float K = 3.2;
    vec2 ruv = vec2(uv.x, WATERLINE - (uv.y - WATERLINE) * K);
    ruv.x += (0.0015 + 0.004 * depth)
             * sin(uv.y * 34.0 + t * 1.4)
             * sin(uv.y * 11.0 - t * 0.9);
    ruv.y += 0.004 * depth * sin(uv.x * 18.0 + uv.y * 26.0 + t * 0.8);
    // Surface chop where the finger actually meets the water, on screen.
    vec3 sfld = touchField(tp, t, aspect);
    ruv.x += sfld.x * 0.30;
    ruv.y += sfld.y * 0.22;
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

    col = refl * shimmer * (0.62 - 0.34 * depth) + vec3(0.010, 0.018, 0.038);
    col += vec3(0.05, 0.08, 0.10) * smoothstep(0.015, 0.0, uv.y - WATERLINE);
  } else {
    col = upperScene(uv, t, fieldParams(touchField(tp, t, aspect), aspect));
  }

  fragColor = vec4(clamp(col + dither(uv), 0.0, 1.0), 1.0) * qt_Opacity;
}
