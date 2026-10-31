// Mare: onde lunghe, increspature, riflessi del cielo, scintillio del sole,
// schiuma sulla costa e deformazione dovuta allo spostamento d'aria del drago
import * as THREE from 'three';
import { TERRAIN_SIZE } from './world.js';

const NP = 24;

const COMMON = /* glsl */`
  #define NP ${NP}
  uniform float uTime;
  uniform vec4 uDown;
  uniform vec4 uPulses[NP];
  uniform sampler2D uHeight;
  uniform vec4 uTerr;

  float terrainH(vec2 p) {
    vec2 uv = (p - uTerr.xy) / uTerr.z;
    if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) return -55.0;
    return texture2D(uHeight, uv).r * 60.0 - 30.0;
  }

  // onde lunghe (Gerstner): altezza, gradiente e spostamento orizzontale che appuntisce le creste
  #define WAVES \
    WAVE(1.0, 0.3, 170.0, 1.5, 11.0) \
    WAVE(0.6, 1.0, 104.0, 0.95, 9.0) \
    WAVE(-0.4, 0.9, 63.0, 0.55, 7.0) \
    WAVE(0.9, -0.6, 37.0, 0.3, 5.2) \
    WAVE(-0.8, -0.3, 21.0, 0.14, 3.9) \
    WAVE(0.2, -1.0, 13.0, 0.07, 3.1)
  float swell(vec2 p, out vec2 g) {
    float h = 0.0; g = vec2(0.0);
    vec2 d; float k, ph;
    #define WAVE(dx, dy, len, amp, spd) d = normalize(vec2(dx, dy)); k = 6.2831853 / len; ph = dot(d, p) * k + uTime * spd * k; h += amp * sin(ph); g += amp * k * cos(ph) * d;
    WAVES
    #undef WAVE
    return h;
  }
  vec2 swellShift(vec2 p) {
    vec2 s = vec2(0.0), d; float k, ph;
    #define WAVE(dx, dy, len, amp, spd) d = normalize(vec2(dx, dy)); k = 6.2831853 / len; ph = dot(d, p) * k + uTime * spd * k; s -= 0.75 * amp * cos(ph) * d;
    WAVES
    #undef WAVE
    return s;
  }

  float localH(vec2 p) {
    float h = 0.0;
    vec2 dd = p - uDown.xy;
    float r2 = dot(dd, dd);
    float s = uDown.z;
    if (s > 0.001 && r2 < 40000.0) {
      float r = sqrt(r2);
      h -= s * 2.8 * exp(-r2 / 420.0);
      h += s * 0.75 * exp(-r2 / 2600.0) * sin(r * 0.55 - uTime * 10.0);
    }
    for (int i = 0; i < NP; i++) {
      vec4 P = uPulses[i];
      float age = uTime - P.z;
      if (P.w <= 0.0 || age < 0.0 || age > 7.0) continue;
      float d = length(p - P.xy);
      float x = d - (3.0 + age * 17.0);
      float w = 3.0 + age * 2.5;
      if (abs(x) > w * 3.0) continue;
      h += P.w * exp(-x * x / (w * w)) * sin(x * 0.75) * exp(-age * 0.55) / (1.0 + d * 0.025);
    }
    return h;
  }
`;

const VERT = /* glsl */`
  ${COMMON}
  varying vec3 vWorld;
  varying float vSwell;
  void main() {
    vec4 wp = modelMatrix * vec4(position, 1.0);
    vec2 g;
    float depth = max(0.0, -terrainH(wp.xz));
    float amp = 0.25 + 0.75 * smoothstep(0.0, 14.0, depth);
    float hs = swell(wp.xz, g) * amp;
    vec2 sh = swellShift(wp.xz) * amp * smoothstep(9000.0, 2000.0, length(wp.xz - cameraPosition.xz));
    wp.y += hs + localH(wp.xz);
    wp.xz += sh;
    vSwell = hs;
    vWorld = wp.xyz;
    gl_Position = projectionMatrix * viewMatrix * wp;
  }`;

const FRAG = /* glsl */`
  ${COMMON}
  uniform samplerCube uEnv;
  uniform vec3 uSunDir;
  uniform vec3 uSunColor;
  uniform vec3 uFogColor;
  uniform float uFogDensity;
  varying vec3 vWorld;
  varying float vSwell;

  float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
  float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
  }
  float detail(vec2 p) {
    float t = uTime;
    return vnoise(p * 0.32 + vec2(t * 0.55, t * 0.3)) * 0.5
         + vnoise(p * 0.85 - vec2(t * 0.45, -t * 0.8)) * 0.25
         + vnoise(p * 2.2 + vec2(t * 1.1, t * 0.7)) * 0.12;
  }

  void main() {
    vec2 p = vWorld.xz;
    float dist = length(cameraPosition - vWorld);
    float depth = max(0.0, -terrainH(p));
    float amp = 0.25 + 0.75 * smoothstep(0.0, 14.0, depth);

    vec2 gs; float hs = swell(p, gs);
    gs *= amp;
    float e = 0.7;
    float hl = localH(p);
    vec2 gl = vec2(localH(p + vec2(e, 0.0)) - hl, localH(p + vec2(0.0, e)) - hl) / e;
    float dfade = 1.0 / (1.0 + dist * 0.02);
    float d0 = detail(p);
    vec2 gd = vec2(detail(p + vec2(0.35, 0.0)) - d0, detail(p + vec2(0.0, 0.35)) - d0) / 0.35;
    // l'aria spinta dal drago increspa la superficie
    vec2 dd = p - uDown.xy;
    float down = uDown.z * exp(-dot(dd, dd) / 1800.0);
    vec2 grad = gs + gl + gd * (0.55 + down * 2.5) * dfade;
    vec3 N = normalize(vec3(-grad.x, 1.0, -grad.y));

    vec3 V = normalize(cameraPosition - vWorld);
    float NdV = max(dot(N, V), 0.0);
    float fres = 0.02 + 0.98 * pow(1.0 - NdV, 5.0);
    vec3 R = reflect(-V, N);
    R.y = abs(R.y);
    vec3 refl = textureCube(uEnv, R).rgb;

    vec3 deep = vec3(0.003, 0.025, 0.05);
    vec3 mid = vec3(0.008, 0.07, 0.1);
    vec3 shallow = vec3(0.04, 0.26, 0.27);
    vec3 body = mix(deep, mid, smoothstep(30.0, 10.0, depth));
    body = mix(body, shallow, smoothstep(12.0, 0.0, depth));
    float sunUp = max(dot(N, uSunDir), 0.0);
    body *= 0.6 + 0.8 * sunUp;
    // luce che attraversa le creste
    float sss = pow(max(dot(-V, uSunDir) * 0.5 + 0.5, 0.0), 3.0) * max(hs + hl, 0.0) * 0.12;
    body += vec3(0.05, 0.25, 0.22) * sss;

    vec3 col = mix(body, refl, fres);
    float sd = max(dot(R, uSunDir), 0.0);
    col += uSunColor * (pow(sd, 900.0) * 60.0 + pow(sd, 90.0) * 0.8 + pow(sd, 12.0) * 0.05);

    // schiuma: riva, creste, spostamento d'aria, anelli d'onda
    float foam = smoothstep(1.8, 0.0, depth) * (0.55 + 0.45 * sin(depth * 4.0 - uTime * 1.8 + d0 * 6.0));
    // creste che si rompono in schiuma (cavalloni)
    float crest = smoothstep(1.7, 2.9, hs * amp) * smoothstep(0.35, 0.75, detail(p * 0.6 + vec2(uTime * 0.3, 0.0)));
    foam += crest * 0.75 + smoothstep(1.2, 2.2, hs * amp) * 0.18 * d0;
    foam += down * smoothstep(0.3, 0.65, detail(p * 2.3 + uTime));
    foam += clamp(abs(hl) * 0.35, 0.0, 0.6) * smoothstep(0.35, 0.6, d0);
    foam = clamp(foam, 0.0, 1.0);
    vec3 foamCol = vec3(0.82, 0.88, 0.92) * (0.35 + 0.65 * sunUp) * 1.1;
    col = mix(col, foamCol, foam * 0.85);

    float fogF = 1.0 - exp(-pow(uFogDensity * dist, 2.0));
    col = mix(col, uFogColor, fogF);
    gl_FragColor = vec4(col, 1.0);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;

function makeRadialGeometry(rings = 140, segs = 200) {
  const pos = [0, 0, 0];
  const radii = [];
  for (let n = 1; n <= rings; n++) radii.push(2 * (Math.pow(1.045, n) - 1) / 0.045);
  for (const r of radii) {
    for (let s = 0; s < segs; s++) {
      const a = s / segs * Math.PI * 2;
      pos.push(Math.cos(a) * r, 0, Math.sin(a) * r);
    }
  }
  const idx = [];
  for (let s = 0; s < segs; s++) idx.push(0, 1 + (s + 1) % segs, 1 + s);
  for (let n = 0; n < rings - 1; n++) {
    const a0 = 1 + n * segs, b0 = 1 + (n + 1) * segs;
    for (let s = 0; s < segs; s++) {
      const s1 = (s + 1) % segs;
      idx.push(a0 + s, a0 + s1, b0 + s);
      idx.push(a0 + s1, b0 + s1, b0 + s);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  return g;
}

export class Water {
  constructor(scene, { envMap, heightTex, sunDir, sunColor, fogColor, fogDensity }) {
    this.pulses = [];
    for (let i = 0; i < NP; i++) this.pulses.push(new THREE.Vector4(0, 0, -100, 0));
    this.pulseIdx = 0;
    this.uniforms = {
      uTime: { value: 0 },
      uDown: { value: new THREE.Vector4(0, 0, 0, 0) },
      uPulses: { value: this.pulses },
      uHeight: { value: heightTex },
      uTerr: { value: new THREE.Vector4(-TERRAIN_SIZE / 2, -TERRAIN_SIZE / 2, TERRAIN_SIZE, 0) },
      uEnv: { value: envMap },
      uSunDir: { value: sunDir.clone() },
      uSunColor: { value: sunColor.clone() },
      uFogColor: { value: fogColor.clone() },
      uFogDensity: { value: fogDensity },
    };
    this.material = new THREE.ShaderMaterial({ uniforms: this.uniforms, vertexShader: VERT, fragmentShader: FRAG });
    this.mesh = new THREE.Mesh(makeRadialGeometry(), this.material);
    this.mesh.frustumCulled = false;
    scene.add(this.mesh);
    this.time = 0;
  }

  addPulse(x, z, amp) {
    const p = this.pulses[this.pulseIdx];
    p.set(x, z, this.time, amp);
    this.pulseIdx = (this.pulseIdx + 1) % NP;
  }

  // Altezza approssimata della superficie (onde lunghe) per spruzzi e camera
  heightAt(x, z) {
    const t = this.time;
    const W = (dx, dy, len, amp, spd) => {
      const l = Math.hypot(dx, dy), k = 6.2831853 / len;
      return amp * Math.sin((dx / l * x + dy / l * z) * k + t * spd * k);
    };
    return W(1, 0.3, 170, 1.5, 11) + W(0.6, 1, 104, 0.95, 9) + W(-0.4, 0.9, 63, 0.55, 7);
  }

  update(dt, camPos, downX, downZ, downStrength) {
    this.time += dt;
    this.uniforms.uTime.value = this.time;
    this.uniforms.uDown.value.set(downX, downZ, downStrength, 0);
    this.mesh.position.set(camPos.x, 0, camPos.z);
  }
}
