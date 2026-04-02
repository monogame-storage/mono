/**
 * Mono Shader: LCD 3D
 * Background + isolated pixels with bevel/emboss depth.
 * Params: thickness (0-0.5), depth (0-1), pixel_size (0.5+, default 1),
 *         bg_color/bg_color2 ([r,g,b] 0-1), bg_dir (0-1, angle)
 */
Mono.shader.register("lcd3d", `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform vec2 u_resolution;
uniform float u_thickness;
uniform float u_pixel_size;
uniform float u_depth;
uniform vec3 u_bg_color;
uniform vec3 u_bg_color2;
uniform float u_bg_dir;
void main() {
  vec4 color = texture2D(u_tex, v_uv);
  vec2 pixel = v_uv * u_resolution / u_pixel_size;
  vec2 edge = fract(pixel);
  float half_t = u_thickness * 0.5;
  bool inPixel = edge.x >= half_t && edge.x <= (1.0 - half_t)
              && edge.y >= half_t && edge.y <= (1.0 - half_t);
  if (!inPixel) {
    float angle = u_bg_dir * 6.28318;
    float t = dot(v_uv - 0.5, vec2(sin(angle), cos(angle))) + 0.5;
    vec3 bg = mix(u_bg_color, u_bg_color2, clamp(t, 0.0, 1.0));
    gl_FragColor = vec4(bg, 1.0);
  } else {
    float bw = u_thickness;
    bool nearLeft = edge.x < half_t + bw;
    bool nearTop  = edge.y < half_t + bw;
    bool nearRight  = edge.x > 1.0 - half_t - bw;
    bool nearBottom = edge.y > 1.0 - half_t - bw;
    if (nearLeft || nearTop) {
      color.rgb += u_depth * 0.15;
    }
    if (nearRight || nearBottom) {
      color.rgb -= u_depth * 0.15;
    }
    gl_FragColor = color;
  }
}`, { thickness: 0.20, pixel_size: 1.0, depth: 1.0, bg_color: [0, 0, 0], bg_color2: [0, 0, 0], bg_dir: 0.0 });
