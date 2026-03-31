/**
 * Mono Shader Plugin
 * Post-processing via WebGL. Requires engine.js loaded first.
 * Shader is a host/display concern — invisible to Lua game code.
 *
 * JS API:
 *   Mono.shader.use("scanlines")
 *   Mono.shader.use("lcd")
 *   Mono.shader.off()
 *   Mono.shader.param("opacity", 0.6)
 *   Mono.shader.register("custom", glslSource, { key: defaultVal })
 */
(() => {
  "use strict";

  if (typeof Mono === "undefined") throw new Error("shader.js requires engine.js");

  // --- Vertex shader (fullscreen quad, flip Y for Canvas2D → WebGL) ---
  const VERT = `
attribute vec2 a_pos;
varying vec2 v_uv;
void main() {
  v_uv = vec2(a_pos.x * 0.5 + 0.5, 1.0 - (a_pos.y * 0.5 + 0.5));
  gl_Position = vec4(a_pos, 0.0, 1.0);
}`;

  // --- Fragment shaders ---
  const FRAG_PASS = `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
void main() {
  gl_FragColor = texture2D(u_tex, v_uv);
}`;

  const FRAG_SCANLINES = `
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
}`;

  const FRAG_LCD = `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform vec2 u_resolution;
uniform float u_opacity;
uniform float u_thickness;
void main() {
  vec4 color = texture2D(u_tex, v_uv);
  vec2 pixel = v_uv * u_resolution;
  vec2 edge = fract(pixel);
  float grid = 1.0;
  if (edge.x < u_thickness || edge.y < u_thickness) {
    grid = 1.0 - u_opacity;
  }
  color.rgb *= grid;
  gl_FragColor = color;
}`;

  // --- Preset registry ---
  const PRESETS = {
    passthrough: { frag: FRAG_PASS, defaults: {} },
    scanlines:   { frag: FRAG_SCANLINES, defaults: { opacity: 0.4, count: 144.0 } },
    lcd:         { frag: FRAG_LCD, defaults: { opacity: 0.5, thickness: 0.08 } },
  };

  // --- State ---
  let gl = null;
  let glCanvas = null;
  let tex = null;
  let quadBuf = null;
  let programs = {};       // name → { program, uniforms }
  let activePreset = null; // null = passthrough
  let params = {};
  let initialized = false;

  function getInternal() {
    const i = Mono._internal;
    if (!i) throw new Error("shader: engine not booted yet");
    return i;
  }

  // --- WebGL helpers ---
  function compileShader(type, src) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      const err = gl.getShaderInfoLog(s);
      gl.deleteShader(s);
      throw new Error("Shader compile: " + err);
    }
    return s;
  }

  function buildProgram(name, fragSrc) {
    if (programs[name]) return programs[name];
    const vs = compileShader(gl.VERTEX_SHADER, VERT);
    const fs = compileShader(gl.FRAGMENT_SHADER, fragSrc);
    const prog = gl.createProgram();
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.bindAttribLocation(prog, 0, "a_pos");
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      throw new Error("Shader link: " + gl.getProgramInfoLog(prog));
    }
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    const uniforms = {};
    const count = gl.getProgramParameter(prog, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < count; i++) {
      const info = gl.getActiveUniform(prog, i);
      uniforms[info.name] = gl.getUniformLocation(prog, info.name);
    }
    programs[name] = { program: prog, uniforms };
    return programs[name];
  }

  // --- Init WebGL (lazy, once) ---
  function initGL() {
    if (initialized) return;
    const { canvas, W, H } = getInternal();

    // WebGL canvas replaces the original on screen
    // Use display size (not native) so shaders have sub-pixel resolution
    glCanvas = document.createElement("canvas");
    glCanvas.style.cssText = canvas.style.cssText;
    canvas.parentNode.insertBefore(glCanvas, canvas.nextSibling);
    canvas.style.display = "none";

    // Size GL canvas to match CSS display size
    function syncSize() {
      const dw = parseInt(canvas.style.width) || W;
      const dh = parseInt(canvas.style.height) || H;
      const dpr = window.devicePixelRatio || 1;
      const rw = Math.round(dw * dpr);
      const rh = Math.round(dh * dpr);
      if (glCanvas.width !== rw || glCanvas.height !== rh) {
        glCanvas.width = rw;
        glCanvas.height = rh;
        if (gl) gl.viewport(0, 0, rw, rh);
      }
      glCanvas.style.width = dw + "px";
      glCanvas.style.height = dh + "px";
    }
    syncSize();
    new MutationObserver(syncSize).observe(canvas, { attributes: true, attributeFilter: ["style"] });
    window.addEventListener("resize", syncSize);

    gl = glCanvas.getContext("webgl", { alpha: false, antialias: false });
    if (!gl) throw new Error("WebGL not available");

    // Fullscreen quad
    quadBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, 1,1]), gl.STATIC_DRAW);

    // Texture for 2D canvas
    tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

    syncSize();
    buildProgram("passthrough", FRAG_PASS);

    // Replace engine flush: always go through WebGL
    Mono._setFlush(shaderFlush);
    initialized = true;
  }

  // --- Render ---
  function renderGL() {
    const { canvas: src, W, H } = getInternal();
    const name = activePreset || "passthrough";
    const prog = programs[name];
    if (!prog) return;

    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, src);
    gl.useProgram(prog.program);

    const u = prog.uniforms;
    if (u.u_tex != null) gl.uniform1i(u.u_tex, 0);
    if (u.u_resolution != null) gl.uniform2f(u.u_resolution, W, H);
    if (u.u_time != null) gl.uniform1f(u.u_time, Mono._getFrame() / 30.0);
    for (const [key, val] of Object.entries(params)) {
      const loc = u["u_" + key];
      if (loc != null) gl.uniform1f(loc, val);
    }

    gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  function shaderFlush() {
    const { imgData, ctx, buf32 } = getInternal();
    // buf32 → offscreen 2D canvas (hidden)
    imgData.data.set(new Uint8Array(buf32.buffer));
    ctx.putImageData(imgData, 0, 0);
    // 2D canvas → WebGL texture → shader → screen
    renderGL();
  }

  // --- Public API ---
  const shader = {};

  shader.use = function (name, userParams) {
    const preset = PRESETS[name];
    if (!preset) throw new Error("Unknown shader: " + name);
    initGL();
    buildProgram(name, preset.frag);
    activePreset = name;
    params = Object.assign({}, preset.defaults);
    if (userParams) {
      for (const [k, v] of Object.entries(userParams)) params[k] = v;
    }
  };

  shader.off = function () {
    // Switch to passthrough — no canvas toggling needed
    activePreset = null;
    params = {};
  };

  shader.param = function (key, value) {
    params[key] = value;
  };

  shader.register = function (name, fragSrc, defaults) {
    PRESETS[name] = { frag: fragSrc, defaults: defaults || {} };
  };

  /** List available preset names */
  shader.list = function () {
    return Object.keys(PRESETS).filter(n => n !== "passthrough");
  };

  /** Get current state */
  shader.current = function () {
    return { preset: activePreset, params: Object.assign({}, params) };
  };

  Mono.shader = shader;
})();
