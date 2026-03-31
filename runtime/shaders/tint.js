/**
 * Mono Effect: Tint
 * Colorize grayscale output with a tint color.
 * Composable on top of any preset shader (pass 2).
 *
 * API:
 *   Mono.shader.tint([0.6, 0.9, 0.3])  // green
 *   Mono.shader.tint(null)              // remove
 */
Mono.shader.register("tint", `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform vec3 u_tint;
void main() {
  vec4 color = texture2D(u_tex, v_uv);
  float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
  color.rgb = vec3(lum) * u_tint;
  gl_FragColor = color;
}`, { tint: [0.6, 0.9, 0.3] });
