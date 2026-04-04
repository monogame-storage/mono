/**
 * Mono Shader: LCD Grid
 * Background + isolated pixel rectangles.
 * Params: thickness (0-0.5), pixel_size (0.5+, default 1),
 *         bg_color/bg_color2 ([r,g,b] 0-1), bg_dir (0-1, angle)
 */
Mono.shader.register("lcd", `
#extension GL_OES_standard_derivatives : enable
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform vec2 u_resolution;
uniform float u_thickness;
uniform float u_pixel_size;
uniform vec3 u_bg_color;
uniform vec3 u_bg_color2;
uniform float u_bg_dir;
void main() {
  vec4 color = texture2D(u_tex, v_uv);
  vec2 pixel = v_uv * u_resolution / u_pixel_size;
  vec2 edge = fract(pixel);
  float half_t = u_thickness * 0.5;

  // Anti-aliased grid using fwidth for smooth edges at any scale
  vec2 fw = fwidth(pixel);
  float maskX = smoothstep(half_t - fw.x, half_t + fw.x, edge.x)
              * smoothstep(half_t - fw.x, half_t + fw.x, 1.0 - edge.x);
  float maskY = smoothstep(half_t - fw.y, half_t + fw.y, edge.y)
              * smoothstep(half_t - fw.y, half_t + fw.y, 1.0 - edge.y);
  float mask = maskX * maskY;

  float angle = u_bg_dir * 6.28318;
  float t = dot(v_uv - 0.5, vec2(sin(angle), cos(angle))) + 0.5;
  vec3 bg = mix(u_bg_color, u_bg_color2, clamp(t, 0.0, 1.0));

  float lum = color.r + color.g + color.b;
  float pixVis = mask * step(0.001, lum);
  gl_FragColor = vec4(mix(bg, color.rgb, pixVis), 1.0);
}`, { thickness: 0.20, pixel_size: 1.0, bg_color: [0, 0, 0], bg_color2: [0.19, 0.19, 0.19], bg_dir: 0.0});
