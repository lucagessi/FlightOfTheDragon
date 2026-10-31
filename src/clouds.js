// Nuvole volumetriche finte: sbuffi billboard istanziati, ordinati per distanza,
// con illuminazione dal sole e nebbia quando ci si passa attraverso
import * as THREE from 'three';
import { mulberry32 } from './noise.js';

function cloudTexture() {
  const S = 256;
  const c = document.createElement('canvas');
  c.width = c.height = S;
  const ctx = c.getContext('2d');
  const rnd = mulberry32(7);
  const blob = (x, y, r, a) => {
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, `rgba(255,255,255,${a})`);
    g.addColorStop(0.6, `rgba(255,255,255,${a * 0.5})`);
    g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
  };
  blob(S / 2, S / 2, S * 0.45, 0.5);
  for (let i = 0; i < 40; i++) {
    const a = rnd() * Math.PI * 2, r = Math.pow(rnd(), 0.7) * S * 0.28;
    blob(S / 2 + Math.cos(a) * r, S / 2 + Math.sin(a) * r * 0.8, S * (0.06 + rnd() * 0.14), 0.25 + rnd() * 0.25);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.NoColorSpace;
  return t;
}

const VERT = /* glsl */`
  attribute vec3 iPos;
  attribute vec4 iData; // scala, rotazione, ombreggiatura verticale, opacità
  varying vec2 vUv;
  varying float vShade;
  varying float vAlpha;
  varying vec2 vOff;
  varying float vDist;
  void main() {
    vec4 mv = viewMatrix * vec4(iPos, 1.0);
    float c = cos(iData.y), s = sin(iData.y);
    vec2 off = position.xy;
    mv.xy += mat2(c, -s, s, c) * off * iData.x;
    vOff = off;
    vUv = uv;
    vShade = iData.z;
    float d = -mv.z;
    vDist = length(mv.xyz);
    // dissolvenza vicino alla camera (si attraversa la nuvola) e lontano
    vAlpha = iData.w * smoothstep(iData.x * 0.08, iData.x * 0.55, d) * (1.0 - smoothstep(9000.0, 14000.0, vDist));
    gl_Position = projectionMatrix * mv;
  }`;

const FRAG = /* glsl */`
  uniform sampler2D map;
  uniform vec3 uSunColor;
  uniform vec3 uShadowColor;
  uniform vec2 uSunView;
  uniform vec3 uFogColor;
  uniform float uFogDensity;
  varying vec2 vUv;
  varying float vShade;
  varying float vAlpha;
  varying vec2 vOff;
  varying float vDist;
  void main() {
    vec4 t = texture2D(map, vUv);
    float a = t.a * vAlpha;
    if (a < 0.004) discard;
    float light = clamp(vShade * 0.7 + (vOff.y + 0.5) * 0.35, 0.0, 1.0);
    // bordo argentato verso il sole
    float rim = max(dot(normalize(vOff + 1e-4), uSunView), 0.0) * (1.0 - t.a) * 1.6;
    vec3 col = mix(uShadowColor, uSunColor, light) + uSunColor * rim * 0.5;
    float fogF = 1.0 - exp(-pow(uFogDensity * vDist * 0.6, 2.0));
    col = mix(col, uFogColor, fogF);
    gl_FragColor = vec4(col, a);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;

export class Clouds {
  constructor(scene, { sunDir, fogColor, fogDensity }) {
    const rnd = mulberry32(31337);
    this.puffs = [];
    this.clouds = [];
    const nClouds = 70;
    for (let c = 0; c < nClouds; c++) {
      const cx = (rnd() - 0.5) * 15000, cz = (rnd() - 0.5) * 15000;
      const cy = 330 + rnd() * 420;
      const size = 160 + rnd() * 300;
      const n = Math.floor(10 + size / 18);
      const cloud = { x: cx, y: cy, z: cz, size };
      this.clouds.push(cloud);
      for (let i = 0; i < n; i++) {
        const a = rnd() * Math.PI * 2, r = Math.sqrt(rnd());
        const px = cx + Math.cos(a) * r * size;
        const pz = cz + Math.sin(a) * r * size * 0.7;
        const hy = Math.pow(rnd(), 1.4) * size * 0.35 * (1 - r * 0.6);
        const scale = (70 + rnd() * 120) * (1.1 - r * 0.4) * (size / 300 + 0.5);
        this.puffs.push({ x: px, y: cy + hy, z: pz, scale, rot: rnd() * 6.28, shade: Math.min(1, hy / (size * 0.3) + 0.15), alpha: 0.55 + rnd() * 0.35, d: 0 });
      }
    }
    const count = this.puffs.length;
    const geo = new THREE.InstancedBufferGeometry();
    const plane = new THREE.PlaneGeometry(1, 1);
    geo.index = plane.index;
    geo.setAttribute('position', plane.attributes.position);
    geo.setAttribute('uv', plane.attributes.uv);
    this.iPos = new THREE.InstancedBufferAttribute(new Float32Array(count * 3), 3).setUsage(THREE.DynamicDrawUsage);
    this.iData = new THREE.InstancedBufferAttribute(new Float32Array(count * 4), 4).setUsage(THREE.DynamicDrawUsage);
    geo.setAttribute('iPos', this.iPos);
    geo.setAttribute('iData', this.iData);
    geo.instanceCount = count;
    this.sunDir = sunDir.clone();
    this.material = new THREE.ShaderMaterial({
      uniforms: {
        map: { value: cloudTexture() },
        uSunColor: { value: new THREE.Color(1.45, 1.38, 1.28) },
        uShadowColor: { value: new THREE.Color(0.52, 0.58, 0.68) },
        uSunView: { value: new THREE.Vector2(1, 0) },
        uFogColor: { value: fogColor.clone() },
        uFogDensity: { value: fogDensity },
      },
      vertexShader: VERT, fragmentShader: FRAG,
      transparent: true, depthWrite: false,
    });
    this.mesh = new THREE.Mesh(geo, this.material);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 1;
    scene.add(this.mesh);
    this.frame = 0;
    this.inside = 0;
    this.sort(new THREE.Vector3());
  }

  sort(camPos) {
    for (const p of this.puffs) p.d = (p.x - camPos.x) ** 2 + (p.y - camPos.y) ** 2 + (p.z - camPos.z) ** 2;
    this.puffs.sort((a, b) => b.d - a.d);
    const P = this.iPos.array, D = this.iData.array;
    this.puffs.forEach((p, i) => {
      P[i * 3] = p.x; P[i * 3 + 1] = p.y; P[i * 3 + 2] = p.z;
      D[i * 4] = p.scale; D[i * 4 + 1] = p.rot; D[i * 4 + 2] = p.shade; D[i * 4 + 3] = p.alpha;
    });
    this.iPos.needsUpdate = true;
    this.iData.needsUpdate = true;
  }

  // Quanto le nuvole coprono il sole lungo il raggio dalla camera
  occlusion(from, dir) {
    let occ = 0;
    for (let i = 1; i <= 14; i++) {
      const d = i * i * 22;
      const x = from.x + dir.x * d, y = from.y + dir.y * d, z = from.z + dir.z * d;
      if (y > 1300) break;
      for (const p of this.puffs) {
        const r = p.scale * 0.45;
        const dx = p.x - x, dy = p.y - y, dz = p.z - z;
        const d2 = dx * dx + dy * dy + dz * dz;
        if (d2 < r * r) occ += (1 - Math.sqrt(d2) / r) * 1.5;
      }
      if (occ >= 1) return 1;
    }
    return Math.min(1, occ);
  }

  update(dt, camera) {
    // le nuvole derivano lentamente col vento
    const wind = 4 * dt;
    for (const p of this.puffs) { p.x += wind; p.z += wind * 0.4; }
    for (const c of this.clouds) { c.x += wind; c.z += wind * 0.4; }
    if (++this.frame % 4 === 0) this.sort(camera.position);
    else {
      const P = this.iPos.array;
      this.puffs.forEach((p, i) => { P[i * 3] = p.x; P[i * 3 + 2] = p.z; });
      this.iPos.needsUpdate = true;
    }
    // direzione del sole proiettata nello spazio vista (per il bordo argentato)
    const v = this.sunDir.clone().transformDirection(camera.matrixWorldInverse);
    this.material.uniforms.uSunView.value.set(v.x, v.y).normalize();

    // densità della nuvola attorno alla camera
    const cp = camera.position;
    let dens = 0;
    for (const p of this.puffs) {
      const r = p.scale * 0.42;
      const dx = p.x - cp.x, dy = p.y - cp.y, dz = p.z - cp.z;
      const d2 = dx * dx + dy * dy + dz * dz;
      if (d2 < r * r) dens = Math.max(dens, 1 - Math.sqrt(d2) / r);
    }
    this.inside += (Math.min(1, dens * 2.2) - this.inside) * Math.min(1, dt * 5);
    return this.inside;
  }
}
