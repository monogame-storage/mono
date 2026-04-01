/**
 * Mono Shader Plugin — Core
 * N-pass WebGL post-processing chain.
 * Chain order: tint → lcd3d → crt (configurable)
 *
 * JS API:
 *   Mono.shader.enable("lcd3d", { opacity: 1.0 })
 *   Mono.shader.disable("lcd3d")
 *   Mono.shader.param("lcd3d", "opacity", 0.5)
 *   Mono.shader.tint([0.6, 0.9, 0.3])   // shortcut: enable tint
 *   Mono.shader.tint(null)               // shortcut: disable tint
 *   Mono.shader.order(["tint","lcd3d","crt"])  // set chain order
 *   Mono.shader.register(name, glsl, defaults)
 *   Mono.shader.list()
 *   Mono.shader.current()
 */
(() => {
  "use strict";

  if (typeof Mono === "undefined") throw new Error("shader.js requires engine.js");

  // --- Vertex shaders ---
  const VERT_FLIP = `
attribute vec2 a_pos;
varying vec2 v_uv;
void main() {
  v_uv = vec2(a_pos.x * 0.5 + 0.5, 1.0 - (a_pos.y * 0.5 + 0.5));
  gl_Position = vec4(a_pos, 0.0, 1.0);
}`;

  const VERT_NOOP = `
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

  // --- Registry ---
  const REGISTRY = {};  // name → { frag, defaults }

  // --- Chain state ---
  let chain = [];          // ordered shader names, e.g. ["tint","lcd3d","crt"]
  let active = {};         // name → true (enabled shaders)
  let chainParams = {};    // name → { key: val }

  // --- WebGL state ---
  let gl = null;
  let glCanvas = null;
  let srcTex = null;
  let fbos = [null, null];
  let fboTexs = [null, null];
  let quadBuf = null;
  let progsFlip = {};      // first pass (Y-flip)
  let progsNoFlip = {};    // subsequent passes
  let initialized = false;
  let lastRW = 0, lastRH = 0;

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

  function getProgram(name, flip) {
    const cache = flip ? progsFlip : progsNoFlip;
    if (cache[name]) return cache[name];
    const entry = REGISTRY[name];
    if (!entry) return null;
    cache[name] = link(flip ? VERT_FLIP : VERT_NOOP, entry.frag);
    return cache[name];
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

  function resizeFboTextures(rw, rh) {
    for (let i = 0; i < 2; i++) {
      gl.bindTexture(gl.TEXTURE_2D, fboTexs[i]);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, rw, rh, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    }
  }

  // --- Init WebGL ---
  function initGL() {
    if (initialized) return;
    const { canvas, W, H } = getInternal();

    glCanvas = document.createElement("canvas");
    glCanvas.style.cssText = canvas.style.cssText;
    glCanvas.className = canvas.className;
    canvas.parentNode.insertBefore(glCanvas, canvas.nextSibling);
    canvas.style.display = "none";

    function syncSize() {
      const hasInlineSize = canvas.style.width && canvas.style.height;
      const dw = hasInlineSize ? parseInt(canvas.style.width) : (glCanvas.offsetWidth || W);
      const dh = hasInlineSize ? parseInt(canvas.style.height) : (glCanvas.offsetHeight || H);
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
          resizeFboTextures(rw, rh);
        }
      }
      if (hasInlineSize) {
        glCanvas.style.width = dw + "px";
        glCanvas.style.height = dh + "px";
      }
    }
    syncSize();
    new MutationObserver(syncSize).observe(canvas, { attributes: true, attributeFilter: ["style"] });
    window.addEventListener("resize", syncSize);

    gl = glCanvas.getContext("webgl", { alpha: false, antialias: false });
    if (!gl) throw new Error("WebGL not available");

    quadBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, 1,1]), gl.STATIC_DRAW);

    srcTex = createTexture();

    // Ping-pong FBOs
    const rw = glCanvas.width, rh = glCanvas.height;
    lastRW = rw; lastRH = rh;
    for (let i = 0; i < 2; i++) {
      fboTexs[i] = createTexture();
      gl.bindTexture(gl.TEXTURE_2D, fboTexs[i]);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, rw, rh, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
      fbos[i] = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, fbos[i]);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, fboTexs[i], 0);
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);

    syncSize();
    Mono._setFlush(shaderFlush);
    initialized = true;
  }

  function drawQuad() {
    gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  function setUniforms(prog, params, W, H) {
    const u = prog.uniforms;
    if (u.u_tex != null) gl.uniform1i(u.u_tex, 0);
    if (u.u_resolution != null) gl.uniform2f(u.u_resolution, W, H);
    if (u.u_time != null) gl.uniform1f(u.u_time, Mono._getFrame() / 30.0);
    for (const [key, val] of Object.entries(params)) {
      const loc = u["u_" + key];
      if (loc == null) continue;
      if (Array.isArray(val) && val.length === 3) {
        gl.uniform3f(loc, val[0], val[1], val[2]);
      } else {
        gl.uniform1f(loc, val);
      }
    }
  }

  // --- Render pipeline ---
  function renderGL() {
    const { canvas: src, W, H } = getInternal();

    // Upload source texture
    gl.bindTexture(gl.TEXTURE_2D, srcTex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, src);

    // Build active chain
    const passes = chain.filter(n => active[n] && REGISTRY[n]);
    if (passes.length === 0) {
      // Passthrough: just copy srcTex to screen
      const p = getProgram("_pass", true);
      if (!p) {
        REGISTRY["_pass"] = { frag: FRAG_PASS, defaults: {} };
        getProgram("_pass", true);
      }
      const prog = progsFlip["_pass"];
      gl.useProgram(prog.program);
      setUniforms(prog, {}, W, H);
      drawQuad();
      return;
    }

    let inputTex = srcTex;
    for (let i = 0; i < passes.length; i++) {
      const name = passes[i];
      const isFirst = (i === 0);
      const isLast = (i === passes.length - 1);
      const prog = getProgram(name, isFirst);
      if (!prog) continue;

      // Output: screen (last) or FBO (intermediate)
      if (isLast) {
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      } else {
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbos[i % 2]);
      }
      gl.viewport(0, 0, lastRW, lastRH);

      gl.bindTexture(gl.TEXTURE_2D, inputTex);
      gl.useProgram(prog.program);
      setUniforms(prog, chainParams[name] || REGISTRY[name].defaults, W, H);
      drawQuad();

      if (!isLast) {
        inputTex = fboTexs[i % 2];
      }
    }
  }

  function shaderFlush() {
    const { imgData, ctx, buf32 } = getInternal();
    imgData.data.set(new Uint8Array(buf32.buffer));
    ctx.putImageData(imgData, 0, 0);
    renderGL();
  }

  // --- Public API ---
  const shader = {};

  shader.register = function (name, fragSrc, defaults) {
    REGISTRY[name] = { frag: fragSrc, defaults: defaults || {} };
    // Auto-add to chain order if not present
    if (chain.indexOf(name) === -1) chain.push(name);
  };

  // Keep for backwards compat
  shader.registerEffect = shader.register;

  shader.enable = function (name, userParams) {
    if (!REGISTRY[name]) throw new Error("Unknown shader: " + name);
    initGL();
    active[name] = true;
    if (userParams) {
      chainParams[name] = Object.assign({}, REGISTRY[name].defaults, userParams);
    } else if (!chainParams[name]) {
      chainParams[name] = Object.assign({}, REGISTRY[name].defaults);
    }
  };

  shader.disable = function (name) {
    active[name] = false;
  };

  /** Set param for a specific shader in the chain */
  shader.param = function (name, key, value) {
    if (!chainParams[name]) chainParams[name] = Object.assign({}, REGISTRY[name]?.defaults || {});
    chainParams[name][key] = value;
  };

  /** Convenience: enable/disable tint */
  shader.tint = function (color) {
    if (color == null) {
      shader.disable("tint");
      return;
    }
    initGL();
    shader.enable("tint", { tint: color });
  };

  /** Convenience: enable a preset (backwards compat with old shader.use) */
  shader.use = function (name, userParams) {
    shader.enable(name, userParams);
  };

  /** Disable all */
  shader.off = function () {
    for (const name in active) active[name] = false;
    chainParams = {};
  };

  /** Set chain order */
  shader.order = function (names) {
    chain = names.slice();
  };

  shader.list = function () {
    return Object.keys(REGISTRY).filter(n => n !== "_pass");
  };

  shader.defaults = function (name) {
    return REGISTRY[name] ? Object.assign({}, REGISTRY[name].defaults) : null;
  };

  shader.chainOrder = function () {
    return chain.slice();
  };

  shader.current = function () {
    return {
      chain: chain.filter(n => active[n]),
      params: Object.assign({}, chainParams),
    };
  };

  Mono.shader = shader;
})();
