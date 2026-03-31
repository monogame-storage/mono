/**
 * Mono Shader: LCD Grid
 * Flat pixel grid overlay.
 * Params: opacity (0-1), thickness (0-0.5), grid_color ([r,g,b] 0-1)
 */
Mono.shader.register("lcd", `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform vec2 u_resolution;
uniform float u_opacity;
uniform float u_thickness;
uniform vec3 u_grid_color;
void main() {
  vec4 color = texture2D(u_tex, v_uv);
  vec2 pixel = v_uv * u_resolution;
  vec2 edge = fract(pixel);
  if (edge.x < u_thickness || edge.y < u_thickness) {
    color.rgb = mix(color.rgb, u_grid_color, u_opacity);
  }
  gl_FragColor = color;
}`, { opacity: 1.0, thickness: 0.20, grid_color: [0, 0, 0] });
