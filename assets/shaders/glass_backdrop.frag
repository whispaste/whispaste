#include <flutter/runtime_effect.glsl>

// Liquid-glass style backdrop for a capsule: edge lensing, light blur, a
// touch of chromatic dispersion at the rim, saturation, and a thin specular
// rim with the light from the top left. Used as an ImageFilter over the
// backdrop, clipped to the pill. Written for WhisPaste; no third-party code.

uniform vec2 uSize;        // set by the engine: size of the filtered area
uniform vec4 uPill;        // capsule as x0, y0, x1, y1 in fractions of uSize
uniform float uBlur;       // blur radius as a fraction of the pill height
uniform float uSaturation; // 1.0 neutral, about 1.3 boosted
uniform float uDark;       // 1.0 dark glass, 0.0 light glass
uniform float uLens;       // edge displacement as a fraction of the radius
uniform sampler2D uBackdrop;

out vec4 fragColor;

float sdRoundBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec2 toUv(vec2 pix) {
  vec2 uv = pix / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

// Disc blur of the backdrop around pix, 32 taps on a golden-angle spiral.
vec3 blurred(vec2 pix, float rad) {
  vec3 acc = vec3(0.0);
  for (int i = 0; i < 32; i++) {
    float a = float(i) * 2.39996323;
    float k = sqrt((float(i) + 0.5) / 32.0);
    acc += texture(uBackdrop, toUv(pix + vec2(cos(a), sin(a)) * k * rad)).rgb;
  }
  return acc / 32.0;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 centre = (uPill.xy + uPill.zw) * 0.5 * uSize;
  vec2 halfSize = (uPill.zw - uPill.xy) * 0.5 * uSize;
  float r = min(halfSize.x, halfSize.y);
  vec2 p = frag - centre;

  float d = sdRoundBox(p, halfSize, r);        // pixels; negative inside
  vec2 e = vec2(1.0, 0.0);
  vec2 g = vec2(
      sdRoundBox(p + e.xy, halfSize, r) - sdRoundBox(p - e.xy, halfSize, r),
      sdRoundBox(p + e.yx, halfSize, r) - sdRoundBox(p - e.yx, halfSize, r));
  vec2 n = normalize(g + vec2(1e-6));          // outward surface normal

  // Lens: the rim (about 20 % of the radius) pulls the backdrop in strongly,
  // the middle hardly moves. w is 1 at the edge and 0 deep inside.
  float rimW = 0.19 * r;                       // about 6 px at r = 32
  float w = pow(1.0 - clamp(-d / rimW, 0.0, 1.0), 2.0);
  vec2 sp = frag - n * (uLens * r * w);

  float bl = uBlur * 2.0 * r;
  // Dispersion only in the outer 2-3 px, at most about a quarter of a pixel.
  float ca = 0.6 * (1.0 - smoothstep(0.0, 3.0, -d));
  vec3 col = vec3(
      blurred(sp - n * ca, bl).r,
      blurred(sp, bl).g,
      blurred(sp + n * ca, bl).b);

  float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
  col = mix(vec3(lum), col, uSaturation);

  // Body: a neutral tint, white on light glass, black on dark glass. Within
  // about 7 px of the edge it is thinner, so the backdrop shows through more.
  // Body: the blurred backdrop almost untinted. Light glass gets at most a
  // slight white lift (6 %), dark glass a thin black tint (8 %). No grey.
  float band = 1.0 - smoothstep(0.0, 7.0, -d);
  vec3 veil = mix(vec3(1.0), vec3(0.0), uDark);
  col = mix(col, veil, mix(0.06, 0.08, uDark) * (1.0 - 0.6 * band));

  // Edge: a thin darker hairline, and a slight brightening only where the
  // edge faces the light (top left). No white rim.
  vec2 toLight = normalize(vec2(-0.6, -0.8));
  float facing = max(dot(n, toLight), 0.0);
  float hairline = 1.0 - smoothstep(0.0, 1.0, -d);
  col *= 1.0 - 0.22 * hairline;
  col += 0.10 * band * pow(facing, 4.0);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
