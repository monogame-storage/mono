/**
 * Mono Shader: LCD 3D
 * Pixel grid with bevel/emboss effect for depth.
 * Params: opacity (0-1), thickness (0-0.5), depth (0-1), grid_color ([r,g,b] 0-1)
 */
Mono.shader.register("lcd3d", `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform vec2 u_resolution;
uniform float u_opacity;
uniform float u_thickness;
uniform float u_depth;
uniform vec3 u_grid_color;
void main() {
  vec4 color = texture2D(u_tex, v_uv);
  vec2 pixel = v_uv * u_resolution;
  vec2 edge = fract(pixel);
  float t = u_thickness;
  bool onGrid = edge.x < t || edge.y < t;
  bool highlightX = edge.x >= t && edge.x < t + t;
  bool highlightY = edge.y >= t && edge.y < t + t;
  bool shadowX = edge.x >= 1.0 - t;
  bool shadowY = edge.y >= 1.0 - t;
  if (onGrid) {
    color.rgb = mix(color.rgb, u_grid_color, u_opacity);
  } else {
    if (highlightX || highlightY) {
      color.rgb += u_depth * 0.15;
    }
    if (shadowX || shadowY) {
      color.rgb -= u_depth * 0.15;
    }
  }
  gl_FragColor = color;
}`, { opacity: 1.0, thickness: 0.20, depth: 1.0, grid_color: [0, 0, 0] });
