/**
 * Mono Shader: CRT
 * Barrel distortion + vignette only. Use scanlines shader separately.
 * Params: curvature (0-1), vignette (0-1)
 */
Mono.shader.register("crt", `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform float u_curvature;
uniform float u_vignette;
void main() {
  vec2 uv = v_uv * 2.0 - 1.0;
  float r2 = dot(uv, uv);
  uv *= 1.0 + u_curvature * r2;
  uv = uv * 0.5 + 0.5;

  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }

  vec4 color = texture2D(u_tex, uv);

  vec2 vig = uv * (1.0 - uv);
  float v = pow(vig.x * vig.y * 16.0, u_vignette * 0.5);
  color.rgb *= v;

  gl_FragColor = color;
}`, { curvature: 0.02, vignette: 0.1 });
