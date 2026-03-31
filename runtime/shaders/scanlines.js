/**
 * Mono Shader: Scanlines
 * Horizontal scanline darkening effect.
 * Params: opacity (0-1), count (number of lines, default=144)
 */
Mono.shader.register("scanlines", `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform vec2 u_resolution;
uniform float u_opacity;
uniform float u_count;
void main() {
  vec4 color = texture2D(u_tex, v_uv);
  float y = v_uv.y * u_count;
  float scanline = smoothstep(0.4, 0.5, abs(fract(y) - 0.5));
  color.rgb *= mix(1.0, scanline, u_opacity);
  gl_FragColor = color;
}`, { opacity: 0.4, count: 144.0 });
