/**
 * Mono Shader: Scanlines
 * Physical-pixel scanline darkening (every other display row).
 * Params: opacity (0-1)
 */
Mono.shader.register("scanlines", `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform float u_opacity;
void main() {
  vec4 color = texture2D(u_tex, v_uv);
  float scanline = mod(gl_FragCoord.y, 2.0) < 1.0 ? 1.0 : 1.0 - u_opacity;
  color.rgb *= scanline;
  gl_FragColor = color;
}`, { opacity: 0.2 });
