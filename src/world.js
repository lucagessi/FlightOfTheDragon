// Mondo: isole, terreno, villaggi medievali, castello, alberi e gestione degli incendi
import * as THREE from 'three';
import { makeNoise2D, mulberry32, fbm, clamp, lerp, smoothstep } from './noise.js';

const nA = makeNoise2D(1337);
const nB = makeNoise2D(4242);
const nC = makeNoise2D(777);
const nD = makeNoise2D(99);

export const ISLANDS = [
  { x: 0, z: 0, r: 1900 },
  { x: 2650, z: -1650, r: 820 },
  { x: -2500, z: 1950, r: 720 },
  { x: -2350, z: -2150, r: 540 },
  { x: 2250, z: 2300, r: 700 },
  { x: 350, z: 3150, r: 420 },
];

export const TERRAIN_SIZE = 7600;
export const TERRAIN_SEGS = 380;
const HALF = TERRAIN_SIZE / 2;
const STEP = TERRAIN_SIZE / TERRAIN_SEGS;
const N = TERRAIN_SEGS + 1;
export const SEABED = -55;

const VILLAGE_NAMES = [
  'Borgo Rosso', 'Valdifiume', 'Montecorvo', 'Rocca Bruna', 'Pietralta', 'Castelmare',
  'Fontebella', 'Querceto', 'Torrevecchia', 'Marinella', 'Acquaviva', 'Spinalunga',
];

function islandMask(x, z) {
  const wx = x + fbm(nB, x * 0.0006, z * 0.0006, 3) * 380;
  const wz = z + fbm(nB, x * 0.0006 + 50, z * 0.0006 - 20, 3) * 380;
  let m = 0;
  for (const is of ISLANDS) {
    const d = Math.hypot(wx - is.x, wz - is.z) / is.r;
    m = Math.max(m, smoothstep(1.0, 0.45, d));
  }
  return m;
}

// Altezza "esatta" del terreno (costosa): usata in generazione
export function heightAt(x, z) {
  const m = islandMask(x, z);
  if (m <= 0) return SEABED;
  // pianure e colline dolci, montagne solo in alcune regioni
  const hills = fbm(nA, x * 0.0007, z * 0.0007, 4) * 0.5 + 0.5;
  const detail = fbm(nA, x * 0.004 + 9.3, z * 0.004, 3) * 2.5;
  const mtnMask = smoothstep(0.55, 0.78, fbm(nC, x * 0.0005 + 3.1, z * 0.0005 - 1.7, 3) * 0.5 + 0.5);
  const ridge = 1 - Math.abs(fbm(nC, x * 0.0016, z * 0.0016, 5));
  const relief = hills * 30 + detail + mtnMask * (35 + Math.pow(ridge, 2.5) * 300);
  return SEABED + m * (-SEABED + 5) + m * m * relief;
}

// Conversione sRGB -> lineare per i colori dei vertici
const L = (r, g, b) => [Math.pow(r, 2.2), Math.pow(g, 2.2), Math.pow(b, 2.2)];

// ---------- Geometrie unitarie (base a y=0) ----------
function makeRoofGeo() {
  const A = [-0.5, 0, 0.5], B = [0.5, 0, 0.5], C = [0, 1, 0.5];
  const D = [-0.5, 0, -0.5], E = [0.5, 0, -0.5], F = [0, 1, -0.5];
  const tris = [A, B, C, E, D, F, D, A, C, D, C, F, B, E, F, B, F, C, A, D, E, A, E, B];
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(tris.flat(), 3));
  g.computeVertexNormals();
  return g;
}

const UNIT = {
  box: new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0).toNonIndexed(),
  cyl: new THREE.CylinderGeometry(1, 1, 1, 14).translate(0, 0.5, 0).toNonIndexed(),
  cone: new THREE.ConeGeometry(1, 1, 14).translate(0, 0.5, 0).toNonIndexed(),
  pyr: new THREE.ConeGeometry(Math.SQRT1_2, 1, 4).rotateY(Math.PI / 4).translate(0, 0.5, 0).toNonIndexed(),
  roof: makeRoofGeo(),
};

// Accumula primitive in un'unica geometria con attributi per l'incendio
class GeoBuilder {
  constructor() { this.pos = []; this.nor = []; this.col = []; this.bld = []; this.glow = []; }
  add(geo, matrix, color, bid, baseY, glow = 0, rng = null) {
    const p = geo.attributes.position, n = geo.attributes.normal;
    const nm = new THREE.Matrix3().getNormalMatrix(matrix);
    const v = new THREE.Vector3(), nn = new THREE.Vector3();
    const j = rng ? 0.9 + rng() * 0.2 : 1;
    for (let i = 0; i < p.count; i++) {
      v.fromBufferAttribute(p, i).applyMatrix4(matrix);
      nn.fromBufferAttribute(n, i).applyMatrix3(nm).normalize();
      // finta occlusione ambientale vicino al suolo
      const ao = baseY > -1e5 ? lerp(0.55, 1, smoothstep(baseY - 1, baseY + 3.5, v.y)) : 1;
      this.pos.push(v.x, v.y, v.z);
      this.nor.push(nn.x, nn.y, nn.z);
      this.col.push(color[0] * j * ao, color[1] * j * ao, color[2] * j * ao);
      this.bld.push(bid, baseY);
      this.glow.push(glow);
    }
  }
  build() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nor, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    g.setAttribute('aBuild', new THREE.Float32BufferAttribute(this.bld, 2));
    g.setAttribute('aGlow', new THREE.Float32BufferAttribute(this.glow, 1));
    g.computeBoundingSphere();
    return g;
  }
}

const COLORS = {
  plaster: [L(0.86, 0.82, 0.72), L(0.8, 0.74, 0.62), L(0.9, 0.88, 0.8), L(0.76, 0.68, 0.55), L(0.84, 0.76, 0.6)],
  stone: L(0.56, 0.54, 0.5),
  stoneDark: L(0.42, 0.41, 0.39),
  timber: L(0.27, 0.17, 0.1),
  door: L(0.22, 0.13, 0.07),
  window: L(0.07, 0.06, 0.05),
  roofs: [L(0.62, 0.25, 0.15), L(0.55, 0.3, 0.18), L(0.6, 0.5, 0.28), L(0.32, 0.33, 0.37), L(0.68, 0.32, 0.18)],
  slate: L(0.28, 0.3, 0.35),
  castleRoof: L(0.5, 0.14, 0.12),
};

const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _v = new THREE.Vector3(), _s = new THREE.Vector3();
const _Y = new THREE.Vector3(0, 1, 0);

export class World {
  constructor(scene) {
    this.scene = scene;
    this.rng = mulberry32(2024);
    this.time = { value: 0 };
    this.buildings = [{ id: 0, inert: true, circles: [], state: 0 }]; // id 0 = elementi non infiammabili
    this.grid = new Map();
    this.burning = [];
    this.treeFires = [];
    this.stats = { total: 0, burning: 0, destroyed: 0 };

    this.buildTerrain();
    this.villages = this.placeVillages();
    this.colorTerrain();
    this.burnTexSize = 1024;
    this.burnData = new Uint8Array(this.burnTexSize * 4);
    this.burnTex = new THREE.DataTexture(this.burnData, this.burnTexSize, 1, THREE.RGBAFormat);
    this.burnTex.magFilter = this.burnTex.minFilter = THREE.NearestFilter;
    this.burnTex.needsUpdate = true;
    this.buildingMaterial = this.makeBuildingMaterial();
    this.buildSettlements();
    this.stats.total = this.buildings.length - 1;
    this.buildTrees();
    this.buildMinimap();
  }

  // ---------------- TERRENO ----------------
  buildTerrain() {
    this.hgrid = new Float32Array(N * N);
    for (let j = 0; j < N; j++)
      for (let i = 0; i < N; i++)
        this.hgrid[j * N + i] = heightAt(-HALF + i * STEP, -HALF + j * STEP);

    const geo = new THREE.PlaneGeometry(TERRAIN_SIZE, TERRAIN_SIZE, TERRAIN_SEGS, TERRAIN_SEGS);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    for (let k = 0; k < pos.count; k++) pos.setY(k, this.hgrid[k]);
    geo.computeVertexNormals();
    this.terrainGeo = geo;

    // Mappa altezze per l'acqua (costa, bassi fondali, schiuma)
    const data = new Uint8Array(N * N);
    for (let k = 0; k < N * N; k++) data[k] = Math.round(clamp((this.hgrid[k] + 30) / 60, 0, 1) * 255);
    this.heightTex = new THREE.DataTexture(data, N, N, THREE.RedFormat, THREE.UnsignedByteType);
    this.heightTex.magFilter = this.heightTex.minFilter = THREE.LinearFilter;
    this.heightTex.needsUpdate = true;
  }

  groundHeight(x, z) {
    const fx = (x + HALF) / STEP, fz = (z + HALF) / STEP;
    if (fx < 0 || fz < 0 || fx >= N - 1 || fz >= N - 1) return SEABED;
    const i = Math.floor(fx), j = Math.floor(fz);
    const tx = fx - i, tz = fz - j;
    const k = j * N + i, h = this.hgrid;
    const a = h[k] + (h[k + 1] - h[k]) * tx;
    const b = h[k + N] + (h[k + N + 1] - h[k + N]) * tx;
    return a + (b - a) * tz;
  }

  flatness(x, z, r) {
    let mn = Infinity, mx = -Infinity;
    for (let a = 0; a < 8; a++) {
      const h = this.groundHeight(x + Math.cos(a * 0.785) * r, z + Math.sin(a * 0.785) * r);
      mn = Math.min(mn, h); mx = Math.max(mx, h);
    }
    const h0 = this.groundHeight(x, z);
    return Math.max(mx, h0) - Math.min(mn, h0);
  }

  placeVillages() {
    const rng = this.rng, villages = [];
    for (let attempt = 0; attempt < 6000 && villages.length < 11; attempt++) {
      const is = attempt % 3 === 0 ? ISLANDS[1 + Math.floor(rng() * (ISLANDS.length - 1))] : ISLANDS[0];
      const a = rng() * Math.PI * 2, r = Math.sqrt(rng()) * is.r * 0.72;
      const x = is.x + Math.cos(a) * r, z = is.z + Math.sin(a) * r;
      const h = this.groundHeight(x, z);
      if (h < 6 || h > 60) continue;
      if (this.flatness(x, z, 60) > 14) continue;
      if (villages.some(v => Math.hypot(v.x - x, v.z - z) < 620)) continue;
      villages.push({ x, z, h, r: 70 + rng() * 40, kind: 'village', name: VILLAGE_NAMES[villages.length], ids: [] });
    }
    // Castello su un'altura
    let best = null;
    for (let attempt = 0; attempt < 6000; attempt++) {
      const a = rng() * Math.PI * 2, r = Math.sqrt(rng()) * 1300;
      const x = Math.cos(a) * r, z = Math.sin(a) * r;
      const h = this.groundHeight(x, z);
      if (h < 25 || h > 170) continue;
      if (villages.some(v => Math.hypot(v.x - x, v.z - z) < 450)) continue;
      const f = this.flatness(x, z, 55);
      if (f > 20) continue;
      const score = h - f * 3;
      if (!best || score > best.score) best = { x, z, h, score };
    }
    if (best) villages.push({ x: best.x, z: best.z, h: best.h, r: 75, kind: 'castle', name: 'Castello di Roccaforte', ids: [] });
    return villages;
  }

  colorTerrain() {
    const geo = this.terrainGeo, pos = geo.attributes.position, nor = geo.attributes.normal;
    const cols = new Float32Array(pos.count * 3);
    const sand = L(0.78, 0.71, 0.52), wetSand = L(0.55, 0.5, 0.38), seabed = L(0.3, 0.33, 0.28);
    const g1 = L(0.24, 0.39, 0.13), g2 = L(0.44, 0.52, 0.2), forest = L(0.16, 0.28, 0.1);
    const rock = L(0.46, 0.43, 0.39), rock2 = L(0.36, 0.33, 0.3), snow = L(0.94, 0.95, 0.98);
    const dirt = L(0.5, 0.41, 0.28);
    const fields = [L(0.78, 0.65, 0.3), L(0.36, 0.52, 0.17), L(0.45, 0.34, 0.21), L(0.55, 0.6, 0.24), L(0.7, 0.58, 0.25)];
    const c = [0, 0, 0];
    const mix = (b, t) => { c[0] = lerp(c[0], b[0], t); c[1] = lerp(c[1], b[1], t); c[2] = lerp(c[2], b[2], t); };
    for (let k = 0; k < pos.count; k++) {
      const x = pos.getX(k), y = pos.getY(k), z = pos.getZ(k), ny = nor.getY(k);
      const n1 = fbm(nD, x * 0.004, z * 0.004, 3) * 0.5 + 0.5;
      if (y < 3.2) {
        c[0] = sand[0]; c[1] = sand[1]; c[2] = sand[2];
        mix(wetSand, smoothstep(1.5, -1.5, y));
        mix(seabed, smoothstep(-3, -25, y));
      } else {
        c[0] = g1[0]; c[1] = g1[1]; c[2] = g1[2];
        mix(g2, n1);
        const forestN = fbm(nD, x * 0.002, z * 0.002, 3);
        mix(forest, smoothstep(0.0, 0.35, forestN) * 0.8);
        mix(sand, smoothstep(6, 3.2, y));
        // campi coltivati e terra battuta intorno ai villaggi
        for (const v of this.villages) {
          const d = Math.hypot(x - v.x, z - v.z);
          if (d > v.r + 200) continue;
          if (v.kind === 'village' && d > v.r * 0.85 && y < 90 && ny > 0.93) {
            const ang = Math.atan2(z - v.z, x - v.x) + 0.3;
            const ux = Math.cos(ang) * d, uz = Math.sin(ang) * d;
            const cell = Math.floor(ux / 40) * 73856093 ^ Math.floor(uz / 28) * 19349663;
            const fc = fields[Math.abs(cell) % fields.length];
            mix(fc, 0.85 * smoothstep(v.r + 200, v.r + 140, d));
          }
          mix(dirt, 0.75 * smoothstep(v.r * 0.9, v.r * 0.3, d));
        }
        mix(rock, smoothstep(110, 175, y + n1 * 30));
        mix(rock2, smoothstep(0.86, 0.66, ny));
        mix(snow, smoothstep(250, 300, y + n1 * 40) * smoothstep(0.6, 0.8, ny));
      }
      const shade = 0.88 + n1 * 0.24;
      cols[k * 3] = c[0] * shade; cols[k * 3 + 1] = c[1] * shade; cols[k * 3 + 2] = c[2] * shade;
    }
    geo.setAttribute('color', new THREE.BufferAttribute(cols, 3));
    const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.96, metalness: 0 });
    this.terrain = new THREE.Mesh(geo, mat);
    this.terrain.receiveShadow = true;
    this.terrain.castShadow = true;
    this.scene.add(this.terrain);
  }

  // ---------------- EDIFICI ----------------
  makeBuildingMaterial() {
    const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.88, metalness: 0 });
    mat.onBeforeCompile = (shader) => {
      shader.uniforms.uBurnTex = { value: this.burnTex };
      shader.uniforms.uBurnSize = { value: this.burnTexSize };
      shader.uniforms.uTime = this.time;
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', `#include <common>
          attribute vec2 aBuild; attribute float aGlow;
          uniform sampler2D uBurnTex; uniform float uBurnSize;
          varying float vChar; varying float vFire; varying float vGlow; varying float vSeed; varying float vHeat;`)
        .replace('#include <begin_vertex>', `#include <begin_vertex>
          vec4 bState = texture2D(uBurnTex, vec2((aBuild.x + 0.5) / uBurnSize, 0.5));
          float rel = transformed.y - aBuild.y;
          transformed.y = aBuild.y + rel * (1.0 - 0.62 * bState.b);
          transformed.x += sin(aBuild.x * 13.0 + transformed.y) * bState.b * 0.6;
          vChar = bState.r; vFire = bState.g; vGlow = aGlow; vSeed = aBuild.x;
          vHeat = clamp(1.0 - rel / 16.0, 0.0, 1.0);`);
      shader.fragmentShader = shader.fragmentShader
        .replace('#include <common>', `#include <common>
          uniform float uTime; varying float vChar; varying float vFire; varying float vGlow; varying float vSeed; varying float vHeat;`)
        .replace('#include <color_fragment>', `#include <color_fragment>
          diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.022, 0.018, 0.016), vChar * 0.93);`)
        .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
          float flick = 0.7 + 0.3 * sin(uTime * 11.0 + vSeed * 3.7) * sin(uTime * 7.3 + vSeed * 1.3);
          float ember = vChar * (0.35 + 0.65 * vHeat) * (0.6 + 0.4 * sin(uTime * 2.3 + vSeed));
          totalEmissiveRadiance += vec3(1.0, 0.36, 0.07) * vFire * flick * (vGlow * 9.0 + ember * 1.6);`);
    };
    return mat;
  }

  newBuilding(circles, base, top, village) {
    const id = this.buildings.length;
    const b = { id, circles, base, top, state: 0, t: 0, fire: 0, char: 0, collapse: 0, emitAcc: 0, smokeAcc: 0, village };
    b.x = circles.reduce((s, c) => s + c.x, 0) / circles.length;
    b.z = circles.reduce((s, c) => s + c.z, 0) / circles.length;
    b.size = Math.max(...circles.map(c => c.r)) * Math.sqrt(circles.length);
    this.buildings.push(b);
    if (village) village.ids.push(id);
    for (const c of circles) {
      const x0 = Math.floor((c.x - c.r) / 32), x1 = Math.floor((c.x + c.r) / 32);
      const z0 = Math.floor((c.z - c.r) / 32), z1 = Math.floor((c.z + c.r) / 32);
      for (let gx = x0; gx <= x1; gx++) for (let gz = z0; gz <= z1; gz++) {
        const key = gx * 100003 + gz;
        let list = this.grid.get(key);
        if (!list) this.grid.set(key, list = []);
        if (!list.includes(b)) list.push(b);
      }
    }
    return b;
  }

  // Frame locale di un edificio: parti posizionate in coordinate locali (y assoluta)
  makePart(B, frame, bid, base) {
    const rng = this.rng;
    return (geo, lx, ly, lz, sx, sy, sz, ry, color, glow = 0) => {
      _q.setFromAxisAngle(_Y, ry);
      _m.compose(_v.set(lx, ly, lz), _q, _s.set(sx, sy, sz)).premultiply(frame);
      B.add(geo, _m, color, bid, base, glow, rng);
    };
  }

  frame(x, z, rot) {
    return new THREE.Matrix4().makeRotationY(rot).setPosition(x, 0, z);
  }

  localToWorld(x, z, rot, lx, lz) {
    const c = Math.cos(rot), s = Math.sin(rot);
    return [x + lx * c + lz * s, z - lx * s + lz * c];
  }

  groundRange(x, z, rot, hw, hd) {
    let mn = Infinity, mx = -Infinity;
    for (const [lx, lz] of [[-hw, -hd], [hw, -hd], [hw, hd], [-hw, hd], [0, 0]]) {
      const [wx, wz] = this.localToWorld(x, z, rot, lx, lz);
      const h = this.groundHeight(wx, wz);
      mn = Math.min(mn, h); mx = Math.max(mx, h);
    }
    return [mn, mx];
  }

  addHouse(B, x, z, rot, village, big = false) {
    const rng = this.rng;
    const w = (big ? 9 : 6) + rng() * 3.5, d = (big ? 7 : 5) + rng() * 2.5;
    const floors = rng() < 0.4 ? 2 : 1;
    const wh = 3.3 * floors + rng() * 1.0;
    const [gmin, gmax] = this.groundRange(x, z, rot, w / 2, d / 2);
    const floorY = gmax + 0.5;
    const wallTop = floorY + wh;
    const rh = 2.4 + rng() * 2.2 + Math.min(w, d) * 0.15;
    const b = this.newBuilding([{ x, z, r: Math.hypot(w, d) / 2 + 0.5 }], gmax, wallTop + rh, village);
    const P = this.makePart(B, this.frame(x, z, rot), b.id, gmax);
    const plaster = COLORS.plaster[Math.floor(rng() * COLORS.plaster.length)];
    const roofCol = COLORS.roofs[Math.floor(rng() * COLORS.roofs.length)];
    const timbered = rng() < 0.6;

    P(UNIT.box, 0, gmin - 2, 0, w + 0.3, floorY - gmin + 2, d + 0.3, 0, COLORS.stoneDark);
    P(UNIT.box, 0, floorY, 0, w, wh, d, 0, timbered ? plaster : (rng() < 0.5 ? COLORS.stone : plaster));
    if (timbered) {
      for (const cx of [-w / 2, w / 2]) for (const cz of [-d / 2, d / 2])
        P(UNIT.box, cx, floorY, cz, 0.45, wh, 0.45, 0, COLORS.timber);
      P(UNIT.box, 0, wallTop - 0.35, 0, w + 0.14, 0.35, d + 0.14, 0, COLORS.timber);
      if (floors === 2) P(UNIT.box, 0, floorY + 3.2, 0, w + 0.14, 0.32, d + 0.14, 0, COLORS.timber);
      P(UNIT.box, 0, floorY + 0.0, 0, w + 0.14, 0.3, d + 0.14, 0, COLORS.timber);
    }
    if (w >= d) P(UNIT.roof, 0, wallTop, 0, d + 1.3, rh, w + 1.0, Math.PI / 2, roofCol);
    else P(UNIT.roof, 0, wallTop, 0, w + 1.3, rh, d + 1.0, 0, roofCol);
    if (rng() < 0.65) P(UNIT.box, (rng() - 0.5) * w * 0.5, wallTop, -d * 0.2, 0.9, rh * 0.95, 0.9, 0, COLORS.stoneDark);
    // porta e finestre (le finestre si illuminano quando la casa brucia)
    P(UNIT.box, (rng() - 0.5) * w * 0.3, floorY - 0.2, d / 2, 1.3, 2.3, 0.3, 0, COLORS.door, 0.5);
    for (let f = 0; f < floors; f++) {
      const y = floorY + 1.2 + f * 3.2;
      for (const sx of [-0.3, 0.3]) {
        P(UNIT.box, sx * w, y, d / 2, 1.0, 1.0, 0.28, 0, COLORS.window, 1);
        P(UNIT.box, sx * w, y, -d / 2, 1.0, 1.0, 0.28, 0, COLORS.window, 1);
      }
      P(UNIT.box, w / 2, y, 0, 0.28, 1.0, 1.0, 0, COLORS.window, 1);
      P(UNIT.box, -w / 2, y, 0, 0.28, 1.0, 1.0, 0, COLORS.window, 1);
    }
    return Math.hypot(w, d) / 2;
  }

  addChurch(B, x, z, rot, village) {
    const w = 10, d = 22, h = 10;
    const [gmin, gmax] = this.groundRange(x, z, rot, w / 2 + 1, d / 2 + 4);
    const [ax, az] = this.localToWorld(x, z, rot, 0, d / 4);
    const [bx, bz] = this.localToWorld(x, z, rot, 0, -d / 4);
    const nave = this.newBuilding([{ x: ax, z: az, r: 7.5 }, { x: bx, z: bz, r: 7.5 }], gmax, gmax + h + 7, village);
    const P = this.makePart(B, this.frame(x, z, rot), nave.id, gmax);
    P(UNIT.box, 0, gmin - 2, 0, w, gmax + h - gmin + 2, d, 0, COLORS.stone);
    P(UNIT.roof, 0, gmax + h, 0, w + 1.4, 7, d + 0.8, 0, COLORS.slate);
    P(UNIT.box, 0, gmax, d / 2, 2.2, 4, 0.4, 0, COLORS.door, 0.6);
    for (let i = -2; i <= 2; i++) {
      P(UNIT.box, w / 2, gmax + 3.5, i * 4, 0.3, 3.2, 1.1, 0, COLORS.window, 1);
      P(UNIT.box, -w / 2, gmax + 3.5, i * 4, 0.3, 3.2, 1.1, 0, COLORS.window, 1);
    }
    P(UNIT.cyl, 0, gmax + 7, d / 2, 1.2, 0.4, 0.5, 0, COLORS.window, 1);
    const [tx, tz] = this.localToWorld(x, z, rot, 0, -d / 2 - 3.2);
    const tower = this.newBuilding([{ x: tx, z: tz, r: 4.5 }], gmax, gmax + 38, village);
    const T = this.makePart(B, this.frame(x, z, rot), tower.id, gmax);
    T(UNIT.box, 0, gmin - 2, -d / 2 - 3.2, 6.4, gmax + 25 - gmin + 2, 6.4, 0, COLORS.stone);
    T(UNIT.box, 0, gmax + 25, -d / 2 - 3.2, 7.2, 0.8, 7.2, 0, COLORS.stoneDark);
    T(UNIT.pyr, 0, gmax + 25.8, -d / 2 - 3.2, 7.0, 13, 7.0, 0, COLORS.slate);
    for (const [sx, sz] of [[0, 3.25], [0, -3.25]]) T(UNIT.box, sx, gmax + 20, -d / 2 - 3.2 + sz, 1.4, 2.6, 0.3, 0, COLORS.window, 1);
    for (const sx of [3.25, -3.25]) T(UNIT.box, sx, gmax + 20, -d / 2 - 3.2, 0.3, 2.6, 1.4, 0, COLORS.window, 1);
  }

  addTower(B, x, z, village, r = 3.6, h = 16, roofCol = COLORS.castleRoof) {
    const g = this.groundHeight(x, z);
    const gmin = Math.min(g, this.groundHeight(x + r, z), this.groundHeight(x - r, z), this.groundHeight(x, z + r), this.groundHeight(x, z - r));
    const b = this.newBuilding([{ x, z, r: r + 0.5 }], g, g + h + r * 2, village);
    const P = this.makePart(B, this.frame(x, z, 0), b.id, g);
    P(UNIT.cyl, 0, gmin - 2, 0, r, g + h - gmin + 2, r, 0, COLORS.stone);
    P(UNIT.cyl, 0, g + h - 0.6, 0, r + 0.6, 0.8, r + 0.6, 0, COLORS.stoneDark);
    P(UNIT.cone, 0, g + h + 0.2, 0, r + 1.2, r * 2.2, r + 1.2, 0, roofCol);
    for (let a = 0; a < 4; a++) {
      P(UNIT.box, Math.cos(a * 1.57 + 0.4) * r, g + h * 0.65, Math.sin(a * 1.57 + 0.4) * r, 0.9, 1.6, 0.9, 0, COLORS.window, 1);
    }
    return b;
  }

  addWall(B, x1, z1, x2, z2, village, h = 12, thick = 3.6) {
    const len = Math.hypot(x2 - x1, z2 - z1);
    const rot = Math.atan2(x2 - x1, z2 - z1);
    const cx = (x1 + x2) / 2, cz = (z1 + z2) / 2;
    let mn = Infinity, mx = -Infinity;
    const circles = [];
    const nC2 = Math.max(2, Math.ceil(len / 7));
    for (let i = 0; i <= nC2; i++) {
      const t = i / nC2, px = lerp(x1, x2, t), pz = lerp(z1, z2, t);
      const g = this.groundHeight(px, pz);
      mn = Math.min(mn, g); mx = Math.max(mx, g);
      if (i < nC2) circles.push({ x: lerp(x1, x2, t + 0.5 / nC2), z: lerp(z1, z2, t + 0.5 / nC2), r: 4 });
    }
    const b = this.newBuilding(circles, mx, mx + h + 2, village);
    const P = this.makePart(B, this.frame(cx, cz, rot), b.id, mx);
    P(UNIT.box, 0, mn - 3, 0, thick, mx + h - mn + 3, len, 0, COLORS.stone);
    for (let s = -len / 2 + 1.2; s < len / 2 - 0.6; s += 3) {
      P(UNIT.box, thick / 2 - 0.5, mx + h, s, 1.0, 1.6, 1.4, 0, COLORS.stone);
      P(UNIT.box, -thick / 2 + 0.5, mx + h, s, 1.0, 1.6, 1.4, 0, COLORS.stone);
    }
  }

  buildVillage(v) {
    const rng = this.rng, B = new GeoBuilder();
    const placed = [];
    const free = (x, z, r) => placed.every(p => Math.hypot(p.x - x, p.z - z) > p.r + r + 2.5);
    // pozzo al centro
    const g0 = this.groundHeight(v.x, v.z);
    const W = this.makePart(B, this.frame(v.x, v.z, 0), 0, g0);
    W(UNIT.cyl, 0, g0 - 1, 0, 1.6, 2.2, 1.6, 0, COLORS.stone);
    W(UNIT.pyr, 0, g0 + 3.2, 0, 3.6, 1.6, 3.6, 0, COLORS.roofs[0]);
    W(UNIT.box, 1.4, g0, 0, 0.3, 3.3, 0.3, 0, COLORS.timber);
    W(UNIT.box, -1.4, g0, 0, 0.3, 3.3, 0.3, 0, COLORS.timber);
    placed.push({ x: v.x, z: v.z, r: 6 });

    // chiesa
    const ca = rng() * Math.PI * 2;
    const cx = v.x + Math.cos(ca) * 24, cz = v.z + Math.sin(ca) * 24;
    this.addChurch(B, cx, cz, Math.atan2(v.x - cx, v.z - cz), v);
    placed.push({ x: cx, z: cz, r: 15 });

    // torre di guardia ai margini
    const ta = rng() * Math.PI * 2;
    const tx = v.x + Math.cos(ta) * (v.r * 0.85), tz = v.z + Math.sin(ta) * (v.r * 0.85);
    if (this.groundHeight(tx, tz) > 3) { this.addTower(B, tx, tz, v, 3.6, 15 + rng() * 6); placed.push({ x: tx, z: tz, r: 5 }); }

    const target = Math.floor(v.r * 0.3 + rng() * 8);
    let count = 0;
    for (let i = 0; i < 600 && count < target; i++) {
      const a = rng() * Math.PI * 2, rr = 13 + Math.sqrt(rng()) * (v.r - 13);
      const x = v.x + Math.cos(a) * rr, z = v.z + Math.sin(a) * rr;
      if (!free(x, z, 6.5)) continue;
      if (this.groundHeight(x, z) < 3 || this.flatness(x, z, 6) > 4) continue;
      const rot = Math.atan2(v.x - x, v.z - z) + (rng() - 0.5) * 0.5;
      const r = this.addHouse(B, x, z, rot, v, rng() < 0.2);
      placed.push({ x, z, r });
      count++;
    }
    // fattorie sparse tra i campi
    for (let i = 0, farms = 0; i < 80 && farms < 5; i++) {
      const a = rng() * Math.PI * 2, rr = v.r + 30 + rng() * 140;
      const x = v.x + Math.cos(a) * rr, z = v.z + Math.sin(a) * rr;
      if (this.groundHeight(x, z) < 4 || this.flatness(x, z, 8) > 5 || !free(x, z, 12)) continue;
      const rot = rng() * Math.PI * 2;
      const r = this.addHouse(B, x, z, rot, v, true);
      placed.push({ x, z, r });
      farms++;
    }
    v.placed = placed;
    this.addMesh(B);
  }

  buildCastle(v) {
    const rng = this.rng, B = new GeoBuilder();
    const rot = rng() * Math.PI;
    const R = 44;
    const corner = (sx, sz) => this.localToWorld(v.x, v.z, rot, sx * R, sz * R);
    const cs = [corner(-1, -1), corner(1, -1), corner(1, 1), corner(-1, 1)];
    for (const [x, z] of cs) this.addTower(B, x, z, v, 6.5, 24, COLORS.castleRoof);
    for (let i = 0; i < 4; i++) {
      const [x1, z1] = cs[i], [x2, z2] = cs[(i + 1) % 4];
      const dx = (x2 - x1) / (2 * R), dz = (z2 - z1) / (2 * R);
      const o = 6;
      if (i === 2) {
        // lato con il portale d'ingresso
        const mx = (x1 + x2) / 2, mz = (z1 + z2) / 2;
        this.addWall(B, x1 + dx * o, z1 + dz * o, mx - dx * 7, mz - dz * 7, v, 13);
        this.addWall(B, mx + dx * 7, mz + dz * 7, x2 - dx * o, z2 - dz * o, v, 13);
        this.addTower(B, mx - dx * 8, mz - dz * 8, v, 4.2, 20, COLORS.castleRoof);
        this.addTower(B, mx + dx * 8, mz + dz * 8, v, 4.2, 20, COLORS.castleRoof);
      } else {
        this.addWall(B, x1 + dx * o, z1 + dz * o, x2 - dx * o, z2 - dz * o, v, 13);
      }
    }
    // mastio
    const g = this.groundHeight(v.x, v.z);
    const [gmin, gmax] = this.groundRange(v.x, v.z, rot, 10, 10);
    const keep = this.newBuilding([{ x: v.x, z: v.z, r: 13 }], gmax, gmax + 42, v);
    const P = this.makePart(B, this.frame(v.x, v.z, rot), keep.id, gmax);
    P(UNIT.box, 0, gmin - 3, 0, 20, gmax + 30 - gmin + 3, 20, 0, COLORS.stone);
    for (let s = -9; s <= 9; s += 3) {
      for (const [a, b] of [[s, 9.6], [s, -9.6], [9.6, s], [-9.6, s]]) P(UNIT.box, a, gmax + 30, b, 1.3, 1.8, 1.3, 0, COLORS.stone);
    }
    for (const [a, b] of [[10, 10], [-10, 10], [10, -10], [-10, -10]]) {
      P(UNIT.cyl, a, gmax + 20, b, 2.6, 16, 2.6, 0, COLORS.stone);
      P(UNIT.cone, a, gmax + 36, b, 3.4, 8, 3.4, 0, COLORS.castleRoof);
    }
    for (let f = 0; f < 3; f++) for (const s of [-5, 0, 5]) {
      const y = gmax + 6 + f * 8;
      P(UNIT.box, s, y, 10, 1.2, 2.2, 0.3, 0, COLORS.window, 1);
      P(UNIT.box, s, y, -10, 1.2, 2.2, 0.3, 0, COLORS.window, 1);
      P(UNIT.box, 10, y, s, 0.3, 2.2, 1.2, 0, COLORS.window, 1);
      P(UNIT.box, -10, y, s, 0.3, 2.2, 1.2, 0, COLORS.window, 1);
    }
    // case nel cortile
    for (const [lx, lz] of [[-28, 22], [26, -26], [28, 18], [-26, -24]]) {
      const [x, z] = this.localToWorld(v.x, v.z, rot, lx, lz);
      this.addHouse(B, x, z, rot + (lx > 0 ? -Math.PI / 2 : Math.PI / 2), v);
    }
    v.placed = [{ x: v.x, z: v.z, r: R + 12 }];
    this.addMesh(B);
  }

  addMesh(B) {
    const mesh = new THREE.Mesh(B.build(), this.buildingMaterial);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    this.scene.add(mesh);
  }

  buildSettlements() {
    for (const v of this.villages) {
      if (v.kind === 'castle') this.buildCastle(v);
      else this.buildVillage(v);
    }
  }

  // ---------------- ALBERI ----------------
  buildTrees() {
    const rng = this.rng;
    const merge = (parts) => {
      const B = new GeoBuilder();
      for (const [geo, m, col] of parts) B.add(geo, m, col, 0, -1e6);
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(B.pos, 3));
      g.setAttribute('normal', new THREE.Float32BufferAttribute(B.nor, 3));
      g.setAttribute('color', new THREE.Float32BufferAttribute(B.col, 3));
      return g;
    };
    const M = (x, y, z, sx, sy, sz) => new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion(), new THREE.Vector3(sx, sy, sz));
    const trunk = L(0.3, 0.2, 0.12), pine = L(0.12, 0.24, 0.11), leaf = L(0.24, 0.38, 0.13), leaf2 = L(0.3, 0.42, 0.15);
    const coneLo = new THREE.ConeGeometry(1, 1, 8).translate(0, 0.5, 0).toNonIndexed();
    const blob = new THREE.IcosahedronGeometry(1, 1);
    const conifer = merge([
      [UNIT.cyl, M(0, -1, 0, 0.35, 3.5, 0.35), trunk],
      [coneLo, M(0, 1.6, 0, 2.6, 4.6, 2.6), pine],
      [coneLo, M(0, 3.9, 0, 2.0, 3.9, 2.0), pine],
      [coneLo, M(0, 6.0, 0, 1.3, 3.2, 1.3), pine],
    ]);
    const broad = merge([
      [UNIT.cyl, M(0, -1, 0, 0.42, 5, 0.42), trunk],
      [blob, M(0, 5.2, 0, 3.0, 2.6, 3.0), leaf],
      [blob, M(1.2, 6.6, 0.5, 2.0, 1.8, 2.0), leaf2],
      [blob, M(-1.0, 6.2, -0.8, 2.0, 1.8, 2.0), leaf],
    ]);
    const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.9, flatShading: true });
    const maxEach = 4200;
    const meshes = [new THREE.InstancedMesh(conifer, mat, maxEach), new THREE.InstancedMesh(broad, mat, maxEach)];
    const counts = [0, 0];
    this.trees = [];
    this.treeGrid = new Map();
    const col = new THREE.Color();
    const exclusion = this.villages.flatMap(v => (v.placed || []).map(p => ({ x: p.x, z: p.z, r: p.r + 4 })));
    for (let i = 0; i < 60000 && counts[0] + counts[1] < maxEach * 2 - 2; i++) {
      const x = (rng() - 0.5) * TERRAIN_SIZE * 0.96, z = (rng() - 0.5) * TERRAIN_SIZE * 0.96;
      const h = this.groundHeight(x, z);
      if (h < 4.5 || h > 210) continue;
      const forest = fbm(nD, x * 0.002, z * 0.002, 3);
      if (forest < 0.05 && rng() > 0.07) continue;
      if (Math.abs(this.groundHeight(x + 5, z) - this.groundHeight(x - 5, z)) + Math.abs(this.groundHeight(x, z + 5) - this.groundHeight(x, z - 5)) > 9) continue;
      if (exclusion.some(e => (x - e.x) ** 2 + (z - e.z) ** 2 < e.r * e.r)) continue;
      if (this.villages.some(v => v.kind === 'village' && Math.hypot(x - v.x, z - v.z) < v.r * 0.7)) continue;
      const type = (h > 85 || forest > 0.28 ? rng() < 0.85 : rng() < 0.25) ? 0 : 1;
      if (counts[type] >= maxEach) continue;
      const s = 0.8 + rng() * 0.8;
      _m.compose(_v.set(x, h, z), _q.setFromAxisAngle(_Y, rng() * 6.28), _s.set(s, s * (0.85 + rng() * 0.35), s));
      const idx = counts[type]++;
      meshes[type].setMatrixAt(idx, _m);
      const tint = 0.8 + rng() * 0.4;
      meshes[type].setColorAt(idx, col.setRGB(tint, tint * (0.95 + rng() * 0.1), tint));
      const tree = { x, z, y: h, s, type, idx, charred: false, tint };
      this.trees.push(tree);
      const key = Math.floor(x / 40) * 100003 + Math.floor(z / 40);
      let list = this.treeGrid.get(key);
      if (!list) this.treeGrid.set(key, list = []);
      list.push(tree);
    }
    for (let t = 0; t < 2; t++) {
      meshes[t].count = counts[t];
      meshes[t].castShadow = true;
      meshes[t].receiveShadow = true;
      meshes[t].instanceColor.needsUpdate = true;
      this.scene.add(meshes[t]);
    }
    this.treeMeshes = meshes;
  }

  charTrees(x, z, r, max = 30) {
    const out = [];
    const gx0 = Math.floor((x - r) / 40), gx1 = Math.floor((x + r) / 40);
    const gz0 = Math.floor((z - r) / 40), gz1 = Math.floor((z + r) / 40);
    const col = new THREE.Color(0.06, 0.05, 0.045);
    for (let gx = gx0; gx <= gx1; gx++) for (let gz = gz0; gz <= gz1; gz++) {
      const list = this.treeGrid.get(gx * 100003 + gz);
      if (!list) continue;
      for (const t of list) {
        if (t.charred || (t.x - x) ** 2 + (t.z - z) ** 2 > r * r) continue;
        t.charred = true;
        this.treeMeshes[t.type].setColorAt(t.idx, col);
        this.treeMeshes[t.type].instanceColor.needsUpdate = true;
        if (this.treeFires.length < 260) this.treeFires.push({ x: t.x, y: t.y + 5 * t.s, z: t.z, t: 0, s: t.s, acc: 0, sacc: 0 });
        out.push(t);
        if (out.length >= max) return out;
      }
    }
    return out;
  }

  // ---------------- INCENDI ----------------
  buildingAt(x, y, z) {
    const list = this.grid.get(Math.floor(x / 32) * 100003 + Math.floor(z / 32));
    if (!list) return null;
    for (const b of list) {
      if (y > b.top + 1 || y < b.base - 3) continue;
      for (const c of b.circles) if ((x - c.x) ** 2 + (z - c.z) ** 2 < c.r * c.r) return b;
    }
    return null;
  }

  buildingsNear(x, z, r, cb) {
    const seen = new Set();
    const x0 = Math.floor((x - r) / 32), x1 = Math.floor((x + r) / 32);
    const z0 = Math.floor((z - r) / 32), z1 = Math.floor((z + r) / 32);
    for (let gx = x0; gx <= x1; gx++) for (let gz = z0; gz <= z1; gz++) {
      const list = this.grid.get(gx * 100003 + gz);
      if (!list) continue;
      for (const b of list) {
        if (seen.has(b)) continue;
        seen.add(b);
        if ((b.x - x) ** 2 + (b.z - z) ** 2 < (r + b.size) ** 2) cb(b);
      }
    }
  }

  ignite(b, delay = 0) {
    if (!b || b.inert || b.state !== 0) return false;
    b.state = 1; b.t = -delay;
    this.burning.push(b);
    return true;
  }

  update(dt, time, fx, camPos) {
    this.time.value = time;
    const rng = Math.random;
    let dirty = false;
    let burningCount = 0;
    for (let i = this.burning.length - 1; i >= 0; i--) {
      const b = this.burning[i];
      b.t += dt;
      if (b.t < 0) continue;
      const t = b.t;
      b.fire = t < 3 ? t / 3 : t < 32 ? 1 : t < 48 ? lerp(1, 0.15, (t - 32) / 16) : t < 95 ? 0.15 * (1 - (t - 48) / 47) : 0;
      b.char = Math.min(1, t / 24);
      b.collapse = smoothstep(16, 30, t);
      if (b.fire > 0.15) burningCount++;
      if (b.state === 1 && t > 22) { b.state = 2; this.stats.destroyed++; }
      if (t > 95) { this.burning.splice(i, 1); b.fire = 0; }
      dirty = true;

      // propagazione alle case vicine
      if (b.fire > 0.6 && rng() < dt * 0.22) {
        this.buildingsNear(b.x, b.z, 18, (n) => { if (n.state === 0 && rng() < 0.5) this.ignite(n); });
      }

      // emissione di fiamme e fumo
      const dx = b.x - camPos.x, dz = b.z - camPos.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      const top = lerp(b.top, b.base + (b.top - b.base) * 0.4, b.collapse);
      if (dist < 2200 && b.fire > 0.02) {
        const lod = dist < 900 ? 1 : 0.35;
        b.emitAcc += dt * b.fire * (10 + b.size * 4.5) * lod;
        while (b.emitAcc >= 1) {
          b.emitAcc -= 1;
          const c = b.circles[Math.floor(rng() * b.circles.length)];
          const a = rng() * 6.283, rr = Math.sqrt(rng()) * c.r * 0.8;
          const y = lerp(b.base + 1, top, 0.35 + rng() * 0.65);
          const s = (3 + rng() * 4) * (0.7 + b.size * 0.06) * (dist < 900 ? 1 : 2);
          fx.fire.spawn(c.x + Math.cos(a) * rr, y, c.z + Math.sin(a) * rr,
            (rng() - 0.5) * 3 + 2, 7 + rng() * 8, (rng() - 0.5) * 3 + 1,
            0.8 + rng() * 0.8, s * 0.8, s * 1.5, 1);
        }
        if (rng() < dt * b.fire * 3 * lod) {
          fx.embers.spawn(b.x + (rng() - 0.5) * b.size, top, b.z + (rng() - 0.5) * b.size,
            (rng() - 0.5) * 8, 10 + rng() * 15, (rng() - 0.5) * 8, 2 + rng() * 2, 0.5, 0.3, 2);
        }
      }
      if (dist < 4500 && t > 0.5) {
        const smokeRate = (b.fire * 3.5 + (b.char > 0.5 ? 0.6 : 0)) * (dist < 1500 ? 1 : 0.4);
        b.smokeAcc += dt * smokeRate;
        while (b.smokeAcc >= 1) {
          b.smokeAcc -= 1;
          const big = dist < 1500 ? 1 : 2.2;
          fx.smoke.spawn(b.x + (rng() - 0.5) * b.size, top + 2, b.z + (rng() - 0.5) * b.size,
            3 + rng() * 2, 9 + rng() * 6, 1.5 + rng() * 2,
            7 + rng() * 4, (6 + b.size * 0.5) * big, (35 + b.size * 2) * big, 0);
        }
      }
    }
    this.stats.burning = burningCount;

    // alberi in fiamme
    for (let i = this.treeFires.length - 1; i >= 0; i--) {
      const f = this.treeFires[i];
      f.t += dt;
      if (f.t > 16) { this.treeFires.splice(i, 1); continue; }
      const dist = Math.hypot(f.x - camPos.x, f.z - camPos.z);
      if (dist > 2000) continue;
      const k = f.t < 1 ? f.t : f.t < 7 ? 1 : Math.max(0, 1 - (f.t - 7) / 4);
      f.acc += dt * 14 * k;
      while (f.acc >= 1) {
        f.acc -= 1;
        fx.fire.spawn(f.x + (rng() - 0.5) * 4 * f.s, f.y - 3 + rng() * 5, f.z + (rng() - 0.5) * 4 * f.s,
          (rng() - 0.5) * 2, 6 + rng() * 6, (rng() - 0.5) * 2, 0.6 + rng() * 0.6, 3 * f.s, 5 * f.s, 1);
      }
      f.sacc += dt * (k * 1.5 + 0.3);
      while (f.sacc >= 1) {
        f.sacc -= 1;
        fx.smoke.spawn(f.x, f.y + 3, f.z, 2 + rng() * 2, 7 + rng() * 4, 1 + rng(), 6, 5, 22, 0);
      }
    }

    if (dirty) {
      const d = this.burnData;
      for (const b of this.burning) {
        const o = b.id * 4;
        d[o] = Math.round(b.char * 255);
        d[o + 1] = Math.round(clamp(b.fire, 0, 1) * 255);
        d[o + 2] = Math.round(b.collapse * 255);
      }
      // gli edifici appena spenti mantengono lo stato carbonizzato
      this.burnTex.needsUpdate = true;
    }
  }

  // Edifici in fiamme più vicini (per le luci dinamiche)
  nearestFires(pos, n) {
    const list = [];
    for (const b of this.burning) {
      if (b.fire < 0.25) continue;
      const d = (b.x - pos.x) ** 2 + (b.z - pos.z) ** 2;
      list.push([d, b]);
    }
    list.sort((a, b) => a[0] - b[0]);
    return list.slice(0, n).map(e => e[1]);
  }

  // ---------------- MINIMAPPA ----------------
  buildMinimap() {
    const S = 200;
    const c = document.createElement('canvas');
    c.width = c.height = S;
    const ctx = c.getContext('2d');
    const img = ctx.createImageData(S, S);
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const wx = -HALF + (x + 0.5) / S * TERRAIN_SIZE, wz = -HALF + (y + 0.5) / S * TERRAIN_SIZE;
      const h = this.groundHeight(wx, wz);
      let r, g, b;
      if (h < 0) { const t = clamp(-h / 50, 0, 1); r = lerp(70, 18, t); g = lerp(150, 50, t); b = lerp(170, 95, t); }
      else if (h < 4) { r = 205; g = 190; b = 140; }
      else if (h < 120) { const t = h / 120; r = lerp(80, 120, t); g = lerp(130, 120, t); b = lerp(60, 80, t); }
      else if (h < 250) { r = 130; g = 122; b = 112; }
      else { r = 235; g = 238; b = 245; }
      const o = (y * S + x) * 4;
      img.data[o] = r; img.data[o + 1] = g; img.data[o + 2] = b; img.data[o + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
    this.minimapBase = c;
    this.minimapScale = S / TERRAIN_SIZE;
    this.minimapHalf = HALF;
  }
}
