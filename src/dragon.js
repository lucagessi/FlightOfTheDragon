// Il drago: modello procedurale animato (corpo flessibile, ali con membrana, testa con mascella)
// e fisica di volo arcade con manovre speciali
import * as THREE from 'three';
import { clamp, lerp, damp, smoothstep } from './noise.js';

const RINGS = 64, RAD = 16;
const RADIUS_KEYS = [[0, 0.08], [0.1, 0.32], [0.3, 0.95], [0.45, 1.75], [0.58, 2.3], [0.68, 2.2], [0.76, 1.5], [0.85, 1.05], [0.97, 0.95], [1.0, 0.7]];
function radiusAt(t) {
  for (let i = 1; i < RADIUS_KEYS.length; i++) {
    const [t1, r1] = RADIUS_KEYS[i];
    if (t <= t1) {
      const [t0, r0] = RADIUS_KEYS[i - 1];
      const k = (t - t0) / (t1 - t0);
      return lerp(r0, r1, k * k * (3 - 2 * k));
    }
  }
  return 0.7;
}

function scaleTexture() {
  const S = 256;
  const c = document.createElement('canvas');
  c.width = c.height = S;
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#777';
  ctx.fillRect(0, 0, S, S);
  const step = 16;
  for (let r = -1; r < S / step + 1; r++) {
    for (let col = -1; col < S / step + 1; col++) {
      const x = col * step + (r % 2 ? step / 2 : 0), y = r * step * 0.75;
      const g = ctx.createRadialGradient(x, y - 3, 1, x, y, step * 0.62);
      g.addColorStop(0, '#fff');
      g.addColorStop(0.7, '#bbb');
      g.addColorStop(1, '#333');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(x, y, step * 0.6, 0, Math.PI);
      ctx.fill();
    }
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = 4;
  return t;
}

const easeInOut = (p) => p * p * p * (p * (p * 6 - 15) + 10);
const _v = new THREE.Vector3(), _v2 = new THREE.Vector3(), _m = new THREE.Matrix4(), _q = new THREE.Quaternion();
const UP = new THREE.Vector3(0, 1, 0), YAX = new THREE.Vector3(0, 1, 0), ORIGIN = new THREE.Vector3();

export class Dragon {
  constructor(scene) {
    this.root = new THREE.Group();
    this.model = new THREE.Group();
    this.model.scale.setScalar(0.62);
    this.root.add(this.model);
    scene.add(this.root);
    this.position = this.root.position;
    this.velocity = new THREE.Vector3();
    this.forward = new THREE.Vector3(0, 0, 1);
    this.up = new THREE.Vector3(0, 1, 0);

    this.yaw = 0; this.pitch = 0; this.roll = 0;
    this.speed = 55; this.throttle = 0.3;
    this.steer = 0; this.climb = 0;
    this.flapPhase = 0; this.flapFreq = 1; this.flapAmp = 0.8; this.fold = 0; this.power = 0.5;
    this.jaw = 0; this.neckDown = 0; this.time = 0;
    this.maneuver = null;
    this.extraPitch = 0; this.extraRoll = 0;
    this.breathing = false;
    this.roaring = 0;
    this.altitude = 60; this.groundY = 0;
    this.tailTurn = 0; this.tailLift = 0; this.neckTurn = 0;
    this.outOfBounds = false;

    const scaleTex = scaleTexture();
    scaleTex.repeat.set(1, 1);
    this.mats = {
      body: new THREE.MeshStandardMaterial({ vertexColors: true, map: scaleTex, bumpMap: scaleTex, bumpScale: 3, roughness: 0.45, metalness: 0.2 }),
      dark: new THREE.MeshStandardMaterial({ color: 0x3a0806, roughness: 0.5, metalness: 0.2 }),
      membrane: new THREE.MeshStandardMaterial({ color: 0x6a120c, side: THREE.DoubleSide, roughness: 0.7, metalness: 0, emissive: 0x240402 }),
      horn: new THREE.MeshStandardMaterial({ color: 0xd8c8a8, roughness: 0.35, metalness: 0.05 }),
      eye: new THREE.MeshStandardMaterial({ color: 0x000000, emissive: new THREE.Color(1, 0.75, 0.15), emissiveIntensity: 6 }),
      mouth: new THREE.MeshStandardMaterial({ color: 0x200000, emissive: new THREE.Color(1, 0.3, 0.05), emissiveIntensity: 0 }),
    };

    this.buildBody();
    this.buildHead();
    this.wings = [this.buildWing(1), this.buildWing(-1)];
    this.buildLegs();
    this.root.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    this.centers = Array.from({ length: RINGS }, () => new THREE.Vector3());
    this.tangents = Array.from({ length: RINGS }, () => new THREE.Vector3());
    this.inv = new THREE.Matrix4();
    this.updateBody();
  }

  // ---------------- COSTRUZIONE ----------------
  buildBody() {
    const verts = RINGS * (RAD + 1);
    this.bodyPos = new Float32Array(verts * 3);
    const col = new Float32Array(verts * 3), uv = new Float32Array(verts * 2);
    const back = new THREE.Color(0.42, 0.05, 0.035), ridge = new THREE.Color(0.2, 0.02, 0.02), belly = new THREE.Color(0.85, 0.6, 0.28);
    const c = new THREE.Color();
    for (let i = 0; i < RINGS; i++) {
      for (let j = 0; j <= RAD; j++) {
        const k = i * (RAD + 1) + j;
        const s = Math.sin(j / RAD * Math.PI * 2);
        c.copy(back).lerp(ridge, smoothstep(0.75, 1, s)).lerp(belly, smoothstep(-0.25, -0.75, s));
        col[k * 3] = c.r; col[k * 3 + 1] = c.g; col[k * 3 + 2] = c.b;
        uv[k * 2] = j / RAD * 2; uv[k * 2 + 1] = i / (RINGS - 1) * 22;
      }
    }
    const idx = [];
    for (let i = 0; i < RINGS - 1; i++) for (let j = 0; j < RAD; j++) {
      const a = i * (RAD + 1) + j, b = a + RAD + 1;
      idx.push(a, a + 1, b, b, a + 1, b + 1);
    }
    const g = new THREE.BufferGeometry();
    this.bodyAttr = new THREE.BufferAttribute(this.bodyPos, 3).setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('position', this.bodyAttr);
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    g.setIndex(idx);
    this.bodyGeo = g;
    this.body = new THREE.Mesh(g, this.mats.body);
    this.body.frustumCulled = false;
    this.model.add(this.body);

    const spikeGeo = new THREE.ConeGeometry(0.32, 1.6, 6);
    this.nSpikes = 30;
    this.spikes = new THREE.InstancedMesh(spikeGeo, this.mats.horn, this.nSpikes);
    this.spikes.frustumCulled = false;
    this.model.add(this.spikes);
  }

  buildHead() {
    const h = new THREE.Group();
    this.head = h;
    this.model.add(h);
    const skin = new THREE.MeshStandardMaterial({ color: 0x5a0a07, roughness: 0.45, metalness: 0.2, map: this.mats.body.map, bumpMap: this.mats.body.map, bumpScale: 2 });
    const add = (geo, mat, x, y, z, rx = 0, ry = 0, rz = 0, sx = 1, sy = 1, sz = 1, parent = h) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, y, z); m.rotation.set(rx, ry, rz); m.scale.set(sx, sy, sz);
      parent.add(m);
      return m;
    };
    add(new THREE.SphereGeometry(1, 18, 14), skin, 0, 0.25, 0.4, 0, 0, 0, 1.25, 1.05, 1.7);
    add(new THREE.CylinderGeometry(0.5, 0.95, 3.4, 10), skin, 0, 0.2, 2.6, Math.PI / 2, 0, 0, 1.2, 1, 0.75);
    add(new THREE.SphereGeometry(0.55, 10, 8), skin, 0, 0.15, 4.25, 0, 0, 0, 1.15, 0.7, 0.9);
    // creste sopraccigliari
    for (const s of [1, -1]) {
      add(new THREE.BoxGeometry(0.35, 0.3, 2.0), this.mats.dark, s * 0.75, 0.95, 1.2, 0.25, s * 0.15, 0);
      add(new THREE.SphereGeometry(0.22, 10, 8), this.mats.eye, s * 0.82, 0.62, 1.35);
      // corna
      add(new THREE.ConeGeometry(0.38, 3.6, 8), this.mats.horn, s * 0.7, 1.15, -0.6, -1.15, 0, -s * 0.28);
      add(new THREE.ConeGeometry(0.22, 1.8, 6), this.mats.horn, s * 1.1, 0.5, -0.4, -1.3, 0, -s * 0.9);
      // narici
      add(new THREE.SphereGeometry(0.13, 8, 6), this.mats.mouth, s * 0.3, 0.45, 4.6);
    }
    // mascella mobile
    this.jawPivot = new THREE.Group();
    this.jawPivot.position.set(0, -0.35, 0.7);
    h.add(this.jawPivot);
    add(new THREE.CylinderGeometry(0.42, 0.75, 3.3, 10), skin, 0, -0.25, 1.75, Math.PI / 2, 0, 0, 1.1, 1, 0.55, this.jawPivot);
    add(new THREE.BoxGeometry(1.0, 0.1, 2.8), this.mats.mouth, 0, 0.08, 1.8, 0, 0, 0, 1, 1, 1, this.jawPivot);
    const toothGeo = new THREE.ConeGeometry(0.08, 0.35, 5);
    for (let i = 0; i < 5; i++) for (const s of [1, -1]) {
      add(toothGeo, this.mats.horn, s * (0.42 - i * 0.04), 0.2, 0.7 + i * 0.6, 0, 0, 0, 1, 1, 1, this.jawPivot);
      add(toothGeo, this.mats.horn, s * (0.45 - i * 0.04), -0.2, 1.4 + i * 0.6, Math.PI, 0, 0, 1, 1, 1);
    }
    // corona di spine dietro la testa
    for (let i = 0; i < 5; i++) {
      const a = (i - 2) * 0.35;
      add(new THREE.ConeGeometry(0.18, 1.3, 5), this.mats.horn, Math.sin(a) * 1.0, 0.9 + Math.cos(a) * 0.3, -1.1, -1.9, 0, -a);
    }
    this.mouth = new THREE.Object3D();
    this.mouth.position.set(0, -0.15, 4.8);
    h.add(this.mouth);
  }

  bone(parent, len, r0, r1, s) {
    const g = new THREE.CylinderGeometry(r1, r0, len, 7);
    g.rotateZ(-s * Math.PI / 2);
    g.translate(s * len / 2, 0, 0);
    const m = new THREE.Mesh(g, this.mats.dark);
    parent.add(m);
    return m;
  }

  buildWing(s) {
    const w = { s };
    w.shoulder = new THREE.Group();
    w.shoulder.position.set(s * 1.3, 1.5, 1.4);
    this.model.add(w.shoulder);
    w.flap = new THREE.Group();
    w.shoulder.add(w.flap);
    this.bone(w.flap, 5.5, 0.55, 0.4, s);
    const joint = new THREE.SphereGeometry(0.5, 10, 8);
    w.elbow = new THREE.Group();
    w.elbow.position.set(s * 5.5, 0, 0);
    w.flap.add(w.elbow);
    w.elbow.add(new THREE.Mesh(joint, this.mats.dark));
    this.bone(w.elbow, 7.2, 0.42, 0.28, s);
    w.wrist = new THREE.Group();
    w.wrist.position.set(s * 7.2, 0, 0);
    w.elbow.add(w.wrist);
    const wj = new THREE.Mesh(joint, this.mats.dark); wj.scale.setScalar(0.75);
    w.wrist.add(wj);
    // artiglio del pollice
    const claw = new THREE.Mesh(new THREE.ConeGeometry(0.18, 1.2, 6), this.mats.horn);
    claw.position.set(s * 0.2, 0.3, 0.6); claw.rotation.x = Math.PI / 2;
    w.wrist.add(claw);
    w.alphas = [-0.12, 0.42, 0.92, 1.42];
    const lens = [11.5, 13, 11.5, 9];
    w.fingers = []; w.tips = [];
    for (let i = 0; i < 4; i++) {
      const f = new THREE.Group();
      w.wrist.add(f);
      this.bone(f, lens[i], 0.26, 0.07, s);
      const tip = new THREE.Object3D();
      tip.position.set(s * lens[i], 0, 0);
      f.add(tip);
      w.fingers.push(f); w.tips.push(tip);
    }
    w.mS = new THREE.Object3D();
    w.mS.position.set(s * 0.6, 0, 1.3);
    w.flap.add(w.mS);
    w.hip = new THREE.Vector3(s * 1.4, 0.7, -9.5);
    w.mid = new THREE.Vector3(s * 1.6, 1.3, -3.5);
    w.pts = Array.from({ length: 13 }, () => new THREE.Vector3());
    const g = new THREE.BufferGeometry();
    w.posArr = new Float32Array(13 * 3);
    w.posAttr = new THREE.BufferAttribute(w.posArr, 3).setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('position', w.posAttr);
    g.setIndex([2, 3, 9, 2, 9, 4, 2, 4, 10, 2, 10, 5, 2, 5, 11, 2, 11, 6, 2, 6, 1, 1, 6, 12, 1, 12, 7, 1, 7, 8, 1, 8, 0]);
    w.geo = g;
    w.membrane = new THREE.Mesh(g, this.mats.membrane);
    w.membrane.frustumCulled = false;
    this.model.add(w.membrane);
    return w;
  }

  buildLegs() {
    const leg = (x, y, z, scale, tuck) => {
      const g = new THREE.Group();
      g.position.set(x, y, z);
      g.rotation.x = tuck;
      g.scale.setScalar(scale);
      this.model.add(g);
      const thigh = new THREE.Mesh(new THREE.CapsuleGeometry(0.7, 2.2, 4, 8), this.mats.dark);
      thigh.position.set(0, -1.3, 0);
      g.add(thigh);
      const shin = new THREE.Group();
      shin.position.set(0, -2.6, 0);
      shin.rotation.x = -1.2;
      g.add(shin);
      const sm = new THREE.Mesh(new THREE.CapsuleGeometry(0.45, 2.0, 4, 8), this.mats.dark);
      sm.position.set(0, -1.2, 0);
      shin.add(sm);
      for (let i = -1; i <= 1; i++) {
        const c = new THREE.Mesh(new THREE.ConeGeometry(0.15, 0.9, 5), this.mats.horn);
        c.position.set(i * 0.3, -2.6, 0.2);
        c.rotation.x = Math.PI * 0.85;
        shin.add(c);
      }
    };
    for (const s of [1, -1]) {
      leg(s * 1.7, -0.8, -7.5, 1.0, 1.1);
      leg(s * 1.6, -1.2, 1.8, 0.7, 1.3);
    }
  }

  // ---------------- ANIMAZIONE ----------------
  spine(t, out) {
    let x = 0, y = 0;
    const z = -26 + t * 40;
    const time = this.time;
    if (t < 0.5) {
      const k = (0.5 - t) / 0.5, kk = k * k;
      x += Math.sin(time * 1.7 - t * 9) * 0.9 * kk + this.tailTurn * kk * 5;
      y += -k * 1.0 + Math.sin(time * 1.3 - t * 7) * 0.35 * kk + this.tailLift * kk * 3;
    }
    if (t > 0.72) {
      const k = (t - 0.72) / 0.28, kk = k * k;
      y += Math.pow(k, 1.4) * 2.6 - this.neckDown * kk * 3.2;
      x += this.neckTurn * kk * 3.5;
    }
    return out.set(x, y, z);
  }

  updateBody() {
    const C = this.centers, T = this.tangents;
    for (let i = 0; i < RINGS; i++) this.spine(i / (RINGS - 1), C[i]);
    for (let i = 0; i < RINGS; i++) {
      const a = C[Math.max(0, i - 1)], b = C[Math.min(RINGS - 1, i + 1)];
      T[i].subVectors(b, a).normalize();
    }
    const P = this.bodyPos, S = _v, U = _v2;
    for (let i = 0; i < RINGS; i++) {
      const t = i / (RINGS - 1);
      const r = radiusAt(t), hr = t > 0.4 && t < 0.72 ? 1.12 : 1.0;
      S.crossVectors(UP, T[i]).normalize();
      U.crossVectors(T[i], S);
      for (let j = 0; j <= RAD; j++) {
        const a = j / RAD * Math.PI * 2;
        const ca = Math.cos(a) * r, sa = Math.sin(a) * r * hr;
        const k = (i * (RAD + 1) + j) * 3;
        P[k] = C[i].x + S.x * ca + U.x * sa;
        P[k + 1] = C[i].y + S.y * ca + U.y * sa;
        P[k + 2] = C[i].z + S.z * ca + U.z * sa;
      }
      // spine dorsali
      const si = Math.round((i - 6) / (RINGS - 12) * (this.nSpikes - 1));
      if (i >= 6 && i <= RINGS - 6 && (i - 6) % 2 === 0 && si < this.nSpikes) {
        const dir = new THREE.Vector3().copy(U).multiplyScalar(0.7).addScaledVector(T[i], -0.7).normalize();
        const sc = 0.45 + r * 0.45;
        const pos = new THREE.Vector3().copy(C[i]).addScaledVector(U, r * hr * 0.9).addScaledVector(dir, 0.8 * sc);
        _q.setFromUnitVectors(YAX, dir);
        _m.compose(pos, _q, new THREE.Vector3(sc, sc, sc));
        this.spikes.setMatrixAt((i - 6) / 2, _m);
      }
    }
    this.spikes.count = Math.floor((RINGS - 6 - 6) / 2) + 1;
    this.spikes.instanceMatrix.needsUpdate = true;
    this.bodyAttr.needsUpdate = true;
    this.bodyGeo.computeVertexNormals();

    // testa all'estremità del collo
    const n = RINGS - 1;
    this.head.position.copy(C[n]).addScaledVector(T[n], 0.2);
    // la testa guarda un po' in basso, e ancora di più quando sputa fuoco
    _v.copy(T[n]);
    _v.y -= 0.12 + this.neckDown * 0.3;
    _m.lookAt(_v.normalize(), ORIGIN, UP);
    this.head.quaternion.setFromRotationMatrix(_m);
    this.jawPivot.rotation.x = this.jaw;
  }

  updateWings() {
    const ph = this.flapPhase;
    const sn = Math.sin(ph), cs = Math.cos(ph);
    const fold = this.fold;
    const amp = this.flapAmp * (1 - fold);
    for (const w of this.wings) {
      const s = w.s;
      w.flap.rotation.z = s * (0.15 + amp * 0.85 * sn - fold * 0.2);
      w.flap.rotation.x = amp * 0.18 * cs;
      w.elbow.rotation.y = s * (0.28 + fold * 0.9 + 0.35 * Math.max(0, cs) * amp);
      w.wrist.rotation.y = -s * (0.08 + fold * 0.95 + 0.25 * Math.max(0, cs) * amp);
      w.wrist.rotation.z = s * 0.3 * amp * Math.sin(ph - 1.0);
      for (let i = 0; i < 4; i++) w.fingers[i].rotation.y = s * w.alphas[i] * (1 - fold * 0.7 - Math.max(0, cs) * 0.15 * amp);
    }
  }

  updateMembranes() {
    this.root.updateMatrixWorld(true);
    this.inv.copy(this.model.matrixWorld).invert();
    const get = (o, out) => out.setFromMatrixPosition(o.matrixWorld).applyMatrix4(this.inv);
    for (const w of this.wings) {
      const p = w.pts;
      get(w.mS, p[0]); get(w.elbow, p[1]); get(w.wrist, p[2]);
      for (let i = 0; i < 4; i++) get(w.tips[i], p[3 + i]);
      p[7].copy(w.hip); p[8].copy(w.mid);
      for (let i = 0; i < 3; i++) {
        p[9 + i].lerpVectors(p[3 + i], p[4 + i], 0.5);
        p[9 + i].lerp(p[2], 0.2);
      }
      p[12].lerpVectors(p[6], p[7], 0.5).lerp(p[1], 0.22);
      for (let i = 0; i < 13; i++) { w.posArr[i * 3] = p[i].x; w.posArr[i * 3 + 1] = p[i].y; w.posArr[i * 3 + 2] = p[i].z; }
      w.posAttr.needsUpdate = true;
      w.geo.computeVertexNormals();
    }
  }

  startRoll(dir) {
    if (this.maneuver) return false;
    this.maneuver = { type: 'roll', t: 0, dur: 0.85, dir };
    return true;
  }
  startLoop() {
    if (this.maneuver) return false;
    this.maneuver = { type: 'loop', t: 0, dur: 2.6 };
    return true;
  }

  getMouth(outPos, outDir) {
    this.mouth.getWorldPosition(outPos);
    outDir.set(0, -0.05, 1).normalize().transformDirection(this.head.matrixWorld);
  }

  // ---------------- VOLO ----------------
  update(dt, ctrl, world) {
    this.time += dt;
    const events = { downstroke: false };
    this.throttle = clamp(this.throttle + ctrl.throttle * 0.5 * dt, 0, 1);
    this.steer = damp(this.steer, ctrl.steer, 4, dt);
    this.climb = damp(this.climb, ctrl.climb, 3, dt);

    // confine del mondo: oltre una certa distanza il drago vira verso il centro
    const distC = Math.hypot(this.position.x, this.position.z);
    let autoSteer = 0;
    if (distC > 5200) {
      const desired = Math.atan2(-this.position.x, -this.position.z);
      let d = desired - this.yaw;
      d = Math.atan2(Math.sin(d), Math.cos(d));
      autoSteer = -clamp(d * 2, -1, 1) * smoothstep(5200, 5800, distC);
    }
    this.outOfBounds = distC > 5200;
    const steer = clamp(this.steer + autoSteer, -1, 1);

    this.pitch = damp(this.pitch, this.climb * 0.62, 2.5, dt);
    const base = 26 + this.throttle * 124;
    this.speed = damp(this.speed, base - Math.sin(this.pitch) * 50, 0.9, dt);
    this.yaw -= steer * (1.15 - this.throttle * 0.45) * dt;
    this.roll = damp(this.roll, steer * 0.85, 4, dt);

    let lateral = 0;
    this.extraPitch = 0; this.extraRoll = 0;
    const m = this.maneuver;
    if (m) {
      m.t += dt;
      const p = clamp(m.t / m.dur, 0, 1), e = easeInOut(p);
      if (m.type === 'roll') {
        this.extraRoll = m.dir * Math.PI * 2 * e;
        lateral = m.dir * Math.sin(Math.PI * p) * 45;
      } else {
        this.extraPitch = Math.PI * 2 * e;
      }
      if (p >= 1) this.maneuver = null;
    }
    const pt = this.pitch + this.extraPitch;
    const cy = Math.cos(this.yaw), sy = Math.sin(this.yaw);
    this.forward.set(sy * Math.cos(pt), Math.sin(pt), cy * Math.cos(pt));
    this.up.set(-sy * Math.sin(pt), Math.cos(pt), -cy * Math.sin(pt));
    const rightX = -cy, rightZ = sy;
    const loopBoost = m && m.type === 'loop' ? 1.15 : 1;
    this.velocity.copy(this.forward).multiplyScalar(this.speed * loopBoost);
    this.velocity.x += rightX * lateral;
    this.velocity.z += rightZ * lateral;
    this.position.addScaledVector(this.velocity, dt);

    // niente atterraggio: quota minima sopra terra/mare
    const g = Math.max(world.groundHeight(this.position.x, this.position.z), 0);
    const ahead = Math.max(world.groundHeight(this.position.x + this.forward.x * 60, this.position.z + this.forward.z * 60), 0);
    const minY = g + 8;
    if (this.position.y < ahead + 14 && this.pitch < 0.35 && !m) this.pitch = damp(this.pitch, 0.4, 2, dt);
    if (this.position.y < minY) {
      this.position.y = minY;
      if (this.pitch < 0) this.pitch *= Math.exp(-8 * dt);
      this.velocity.y = Math.max(0, this.velocity.y);
    }
    if (this.position.y > 1500) { this.position.y = 1500; this.pitch = Math.min(this.pitch, 0); }
    this.altitude = this.position.y - g;
    this.groundY = g;

    this.root.rotation.set(-pt, this.yaw, this.roll + this.extraRoll, 'YXZ');

    // battito d'ali: frequenza e potenza dipendono da velocità e salita
    const climbing = Math.max(0, Math.sin(pt));
    const diving = Math.max(0, -Math.sin(this.pitch));
    const glide = diving > 0.25 && ctrl.throttle <= 0 && !m;
    this.fold = damp(this.fold, glide ? 0.8 : 0, 2.5, dt);
    const accel = ctrl.throttle > 0 ? 0.5 : 0;
    this.power = clamp(0.25 + this.throttle * 0.75 + climbing * 0.6 + accel * 0.3 + (m && m.type === 'loop' ? 0.4 : 0), 0.2, 1.4);
    this.flapFreq = damp(this.flapFreq, 0.6 + this.throttle * 2.0 + climbing * 1.0 + accel, 2, dt);
    this.flapAmp = damp(this.flapAmp, 0.5 + this.power * 0.42, 2, dt);
    const prevCos = Math.cos(this.flapPhase);
    this.flapPhase += dt * this.flapFreq * Math.PI * 2 * (1 - this.fold * 0.92);
    if (prevCos > 0 && Math.cos(this.flapPhase) <= 0 && this.fold < 0.5) events.downstroke = true;
    this.model.position.y = -Math.sin(this.flapPhase - 0.6) * 0.35 * this.flapAmp * (1 - this.fold);

    // collo e coda
    this.tailTurn = this.steer * 1.0;
    this.tailLift = -this.climb * 0.5 + diving * 0.4;
    this.neckTurn = -this.steer * 0.9;
    this.neckDown = damp(this.neckDown, this.breathing ? 0.75 : 0.1, 4, dt);
    this.jaw = damp(this.jaw, this.breathing ? 0.55 : this.roaring > 0 ? 0.7 : 0.04, 10, dt);
    this.roaring = Math.max(0, this.roaring - dt);
    this.mats.mouth.emissiveIntensity = damp(this.mats.mouth.emissiveIntensity, this.breathing ? 8 : 0.3, 8, dt);

    this.updateBody();
    this.updateWings();
    this.updateMembranes();
    return events;
  }
}
