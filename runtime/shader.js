/**
 * Mono Shader Plugin — Core
 * 2-pass WebGL post-processing pipeline.
 *   Pass 1: preset shader (lcd3d, scanlines, etc.)
 *   Pass 2: post-effects (tint, etc.) — composable on top of any preset
 *
 * JS API:
 *   Mono.shader.use("lcd3d")
 *   Mono.shader.off()
 *   Mono.shader.param("opacity", 0.6)
 *   Mono.shader.tint([0.2, 0.9, 0.3])   // green tint
 *   Mono.shader.tint(null)               // remove tint
 *   Mono.shader.register(name, glslFragment, defaults)
 *   Mono.shader.list()
 *   Mono.shader.current()
 *
 * Preset files (runtime/shaders/*.js) call register() to add themselves.
 */
(() => {
  "use strict";

  if (typeof Mono === "undefined") throw new Error("shader.js requires engine.js");

  // --- Shaders ---
  const VERT = `
attribute vec2 a_pos;
varying vec2 v_uv;
void main() {
  v_uv = vec2(a_pos.x * 0.5 + 0.5, 1.0 - (a_pos.y * 0.5 + 0.5));
  gl_Position = vec4(a_pos, 0.0, 1.0);
}`;

  // Pass-through (no Y flip — used for pass2 which reads from FBO)
  const VERT_PASS2 = `
attribute vec2 a_pos;
varying vec2 v_uv;
void main() {
  v_uv = a_pos * 0.5 + 0.5;
  gl_Position = vec4(a_pos, 0.0, 1.0);
}`;

  const FRAG_PASS = `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
void main() {
  gl_FragColor = texture2D(u_tex, v_uv);
}`;

  const FRAG_TINT = `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform vec3 u_tint;
void main() {
  vec4 color = texture2D(u_tex, v_uv);
  float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
  color.rgb = vec3(lum) * u_tint;
  gl_FragColor = color;
}`;

  // --- Preset registry ---
  const PRESETS = {
    passthrough: { frag: FRAG_PASS, defaults: {} },
  };

  // --- State ---
  let gl = null;
  let glCanvas = null;
  let srcTex = null;     // texture from 2D canvas
  let fbo = null;        // framebuffer for pass1 output
  let fboTex = null;     // texture attached to FBO
  let quadBuf = null;
  let programs = {};     // pass1 programs (keyed by preset name)
  let pass2Programs = {};// pass2 programs
  let activePreset = null;
  let params = {};
  let tintColor = null;  // [r,g,b] or null
  let initialized = false;

  function getInternal() {
    const i = Mono._internal;
    if (!i) throw new Error("shader: engine not booted yet");
    return i;
  }

  // --- WebGL helpers ---
  function compile(type, src) {
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

  function link(vertSrc, fragSrc) {
    const vs = compile(gl.VERTEX_SHADER, vertSrc);
    const fs = compile(gl.FRAGMENT_SHADER, fragSrc);
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
    return { program: prog, uniforms };
  }

  function buildProgram(name, fragSrc) {
    if (programs[name]) return programs[name];
    programs[name] = link(VERT, fragSrc);
    return programs[name];
  }

  function buildPass2(name, fragSrc) {
    if (pass2Programs[name]) return pass2Programs[name];
    pass2Programs[name] = link(VERT_PASS2, fragSrc);
    return pass2Programs[name];
  }

  function createTexture() {
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    return t;
  }

  // --- Init WebGL ---
  let lastRW = 0, lastRH = 0;

  function initGL() {
    if (initialized) return;
    const { canvas, W, H } = getInternal();

    glCanvas = document.createElement("canvas");
    glCanvas.style.cssText = canvas.style.cssText;
    canvas.parentNode.insertBefore(glCanvas, canvas.nextSibling);
    canvas.style.display = "none";

    function syncSize() {
      const dw = parseInt(canvas.style.width) || W;
      const dh = parseInt(canvas.style.height) || H;
      const dpr = window.devicePixelRatio || 1;
      const rw = Math.round(dw * dpr);
      const rh = Math.round(dh * dpr);
      if (glCanvas.width !== rw || glCanvas.height !== rh) {
        glCanvas.width = rw;
        glCanvas.height = rh;
        lastRW = rw;
        lastRH = rh;
        if (gl) {
          gl.viewport(0, 0, rw, rh);
          // Resize FBO texture to match
          if (fboTex) {
            gl.bindTexture(gl.TEXTURE_2D, fboTex);
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, rw, rh, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
          }
        }
      }
      glCanvas.style.width = dw + "px";
      glCanvas.style.height = dh + "px";
    }
    syncSize();
    new MutationObserver(syncSize).observe(canvas, { attributes: true, attributeFilter: ["style"] });
    window.addEventListener("resize", syncSize);

    gl = glCanvas.getContext("webgl", { alpha: false, antialias: false });
    if (!gl) throw new Error("WebGL not available");

    // Quad
    quadBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, 1,1]), gl.STATIC_DRAW);

    // Source texture (from 2D canvas)
    srcTex = createTexture();

    // FBO for pass1 output
    fboTex = createTexture();
    const rw = glCanvas.width, rh = glCanvas.height;
    lastRW = rw; lastRH = rh;
    gl.bindTexture(gl.TEXTURE_2D, fboTex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, rw, rh, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);

    fbo = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, fboTex, 0);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);

    syncSize();
    buildProgram("passthrough", FRAG_PASS);
    buildPass2("passthrough", FRAG_PASS);
    buildPass2("tint", FRAG_TINT);

    Mono._setFlush(shaderFlush);
    initialized = true;
  }

  function drawQuad() {
    gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  // --- Render pipeline ---
  function renderGL() {
    const { canvas: src, W, H } = getInternal();
    const needPass2 = tintColor != null;

    // Upload source
    gl.bindTexture(gl.TEXTURE_2D, srcTex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, src);

    // --- Pass 1: preset shader ---
    const presetName = activePreset || "passthrough";
    const p1 = programs[presetName];
    if (!p1) return;

    if (needPass2) {
      // Render to FBO
      gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
      gl.viewport(0, 0, lastRW, lastRH);
    }

    gl.useProgram(p1.program);
    const u1 = p1.uniforms;
    if (u1.u_tex != null) gl.uniform1i(u1.u_tex, 0);
    if (u1.u_resolution != null) gl.uniform2f(u1.u_resolution, W, H);
    if (u1.u_time != null) gl.uniform1f(u1.u_time, Mono._getFrame() / 30.0);
    for (const [key, val] of Object.entries(params)) {
      const loc = u1["u_" + key];
      if (loc == null) continue;
      if (Array.isArray(val) && val.length === 3) {
        gl.uniform3f(loc, val[0], val[1], val[2]);
      } else {
        gl.uniform1f(loc, val);
      }
    }
    drawQuad();

    if (!needPass2) return;

    // --- Pass 2: tint ---
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, lastRW, lastRH);

    gl.bindTexture(gl.TEXTURE_2D, fboTex);
    const p2 = pass2Programs["tint"];
    gl.useProgram(p2.program);
    if (p2.uniforms.u_tex != null) gl.uniform1i(p2.uniforms.u_tex, 0);
    if (p2.uniforms.u_tint != null) gl.uniform3f(p2.uniforms.u_tint, tintColor[0], tintColor[1], tintColor[2]);
    drawQuad();
  }

  function shaderFlush() {
    const { imgData, ctx, buf32 } = getInternal();
    imgData.data.set(new Uint8Array(buf32.buffer));
    ctx.putImageData(imgData, 0, 0);
    renderGL();
  }

  // --- Public API ---
  const shader = {};

  shader.use = function (name, userParams) {
    const preset = PRESETS[name];
    if (!preset) throw new Error("Unknown shader: " + name + ". Available: " + shader.list().join(", "));
    initGL();
    buildProgram(name, preset.frag);
    activePreset = name;
    params = Object.assign({}, preset.defaults);
    if (userParams) {
      for (const [k, v] of Object.entries(userParams)) params[k] = v;
    }
  };

  shader.off = function () {
    activePreset = null;
    params = {};
  };

  shader.param = function (key, value) {
    params[key] = value;
  };

  shader.tint = function (color) {
    if (color == null) {
      tintColor = null;
      return;
    }
    initGL();
    tintColor = color;
  };

  shader.register = function (name, fragSrc, defaults) {
    PRESETS[name] = { frag: fragSrc, defaults: defaults || {} };
  };

  shader.list = function () {
    return Object.keys(PRESETS).filter(n => n !== "passthrough");
  };

  shader.current = function () {
    return { preset: activePreset, params: Object.assign({}, params), tint: tintColor };
  };

  Mono.shader = shader;
})();
