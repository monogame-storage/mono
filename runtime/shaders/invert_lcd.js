/**
 * Mono Shader: Invert LCD
 * Retro LCD — bright background, dark pixel dots with radial vignette.
 * (Game Boy, Casio, Tiger Electronics, etc.)
 *
 * Params: gap, bg_color, dot_color, vignette
 *
 * API:
 *   Mono.shader.enable("invert_lcd")
 *   Mono.shader.enable("invert_lcd", { dot_color: [0.2, 0.1, 0] })
 */
Mono.shader.register("invert_lcd", `
#extension GL_OES_standard_derivatives : enable
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform vec2 u_resolution;
uniform float u_colors;
uniform float u_gap;
uniform vec3 u_bg_color;
uniform vec3 u_dot_color;
uniform float u_vignette;
void main() {
  vec4 color = texture2D(u_tex, v_uv);
  vec2 pixel = v_uv * u_resolution;
  vec2 edge = fract(pixel);

  // Grid — gap=1 → 1 screen pixel gap between dots
  vec2 fw = fwidth(pixel);
  float pxPerTexel = 1.0 / max(fw.x, fw.y);
  float eff_gap = u_gap / max(pxPerTexel, 1.0);
  float half_g = eff_gap * 0.5;
  float dotR = (1.0 - eff_gap) * 0.5;
  vec2 aa = min(fw, vec2(dotR * 0.5));
  float maskX = smoothstep(half_g, half_g + aa.x, edge.x)
              * smoothstep(half_g, half_g + aa.x, 1.0 - edge.x);
  float maskY = smoothstep(half_g, half_g + aa.y, edge.y)
              * smoothstep(half_g, half_g + aa.y, 1.0 - edge.y);
  float mask = u_gap < 0.01 ? 1.0 : min(maskX, maskY);

  // Radial vignette: darken edges
  float dist = length((v_uv - 0.5) * vec2(1.0, u_resolution.y / u_resolution.x));
  float vig = 1.0 - smoothstep(0.0, 0.65, dist) * u_vignette * 0.6;
  vec3 bg = u_bg_color * vig;

  // Dot intensity from luminance
  float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
  float maxLum = dot(vec3(1.0), vec3(0.299, 0.587, 0.114));
  float nlum = clamp(lum / maxLum, 0.0, 1.0);
  float steps = max(u_colors - 1.0, 1.0);
  float q = floor(nlum * steps + 0.5) / steps;

  // Background first, then dot on top only where mask > 0
  vec3 dot = mix(bg, u_dot_color, q);
  gl_FragColor = vec4(mix(bg, dot, mask), 1.0);
}`, { gap: 0.20, bg_color: [0.72, 0.74, 0.42], dot_color: [0, 0, 0], vignette: 1.0 });
