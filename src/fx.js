// Effetti: particelle (fuoco, fumo, scintille, spruzzi), palle di fuoco, tempesta di fuoco, luci dinamiche
import * as THREE from 'three';

function makeTexture(kind) {
  const S = 128;
  const c = document.createElement('canvas');
  c.width = c.height = S;
  const ctx = c.getContext('2d');
  const radial = (x, y, r, stops) => {
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    for (const [o, a] of stops) g.addColorStop(o, `rgba(255,255,255,${a})`);
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
  };
  if (kind === 'fire') {
    radial(S / 2, S / 2, S / 2, [[0, 1], [0.25, 0.75], [0.55, 0.25], [1, 0]]);
    for (let i = 0; i < 10; i++) {
      const a = Math.random() * 6.28, r = Math.random() * S * 0.18;
      radial(S / 2 + Math.cos(a) * r, S / 2 + Math.sin(a) * r, S * (0.12 + Math.random() * 0.12), [[0, 0.35], [1, 0]]);
    }
  } else if (kind === 'spark') {
    radial(S / 2, S / 2, S / 2, [[0, 1], [0.15, 0.9], [0.4, 0.15], [1, 0]]);
  } else {
    radial(S / 2, S / 2, S / 2, [[0, 0.55], [0.5, 0.3], [1, 0]]);
    for (let i = 0; i < 22; i++) {
      const a = Math.random() * 6.28, r = Math.random() * S * 0.26;
      radial(S / 2 + Math.cos(a) * r, S / 2 + Math.sin(a) * r, S * (0.1 + Math.random() * 0.16), [[0, 0.3], [1, 0]]);
    }
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.NoColorSpace;
  return t;
}

const VERT = /* glsl */`
  attribute vec4 aColor;
  attribute float aSize;
  uniform float uScale;
  varying vec4 vColor;
  varying float vRot;
  void main() {
    vColor = aColor;
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    gl_Position = projectionMatrix * mv;
    gl_PointSize = aSize * uScale / max(-mv.z, 0.5);
    vRot = float(gl_VertexID) * 2.399;
    // dissolvenza lontana
    vColor.a *= 1.0 - smoothstep(4000.0, 7000.0, -mv.z);
    if (aSize <= 0.0) gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
  }`;
const FRAG = /* glsl */`
  uniform sampler2D map;
  varying vec4 vColor;
  varying float vRot;
  void main() {
    vec2 uv = gl_PointCoord - 0.5;
    float c = cos(vRot), s = sin(vRot);
    uv = mat2(c, -s, s, c) * uv + 0.5;
    vec4 t = texture2D(map, uv);
    gl_FragColor = vec4(vColor.rgb, vColor.a * t.a);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;

export class ParticleSystem {
  constructor(scene, { max, texture, additive = false, gravity = 0, drag = 0, ramp }) {
    this.max = max;
    this.gravity = gravity;
    this.drag = drag;
    this.ramp = ramp;
    this.head = 0;
    this.alive = 0;
    this.p = new Float32Array(max * 3);
    this.v = new Float32Array(max * 3);
    this.age = new Float32Array(max);
    this.life = new Float32Array(max);
    this.s0 = new Float32Array(max);
    this.s1 = new Float32Array(max);
    this.rampId = new Uint8Array(max);
    this.flags = new Uint8Array(max);
    this.pdrag = new Float32Array(max);
    this.col = new Float32Array(max * 4);
    this.size = new Float32Array(max);
    this.onCollide = null;
    const g = new THREE.BufferGeometry();
    this.posAttr = new THREE.BufferAttribute(this.p, 3).setUsage(THREE.DynamicDrawUsage);
    this.colAttr = new THREE.BufferAttribute(this.col, 4).setUsage(THREE.DynamicDrawUsage);
    this.sizeAttr = new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('position', this.posAttr);
    g.setAttribute('aColor', this.colAttr);
    g.setAttribute('aSize', this.sizeAttr);
    this.material = new THREE.ShaderMaterial({
      uniforms: { map: { value: texture }, uScale: { value: 500 } },
      vertexShader: VERT, fragmentShader: FRAG,
      transparent: true, depthWrite: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    this.points = new THREE.Points(g, this.material);
    this.points.frustumCulled = false;
    this.points.renderOrder = additive ? 3 : 2;
    scene.add(this.points);
  }

  spawn(x, y, z, vx, vy, vz, life, s0, s1, ramp = 0, flags = 0, drag = -1) {
    const i = this.head;
    this.head = (this.head + 1) % this.max;
    const i3 = i * 3;
    this.p[i3] = x; this.p[i3 + 1] = y; this.p[i3 + 2] = z;
    this.v[i3] = vx; this.v[i3 + 1] = vy; this.v[i3 + 2] = vz;
    this.age[i] = 0; this.life[i] = life;
    this.s0[i] = s0; this.s1[i] = s1;
    this.rampId[i] = ramp; this.flags[i] = flags;
    this.pdrag[i] = drag < 0 ? this.drag : drag;
  }

  update(dt) {
    const { p, v, age, life, col, size } = this;
    const out = [0, 0, 0, 0];
    let alive = 0;
    for (let i = 0; i < this.max; i++) {
      if (life[i] <= 0) { if (size[i] !== 0) size[i] = 0; continue; }
      age[i] += dt;
      if (age[i] >= life[i]) { life[i] = 0; size[i] = 0; continue; }
      alive++;
      const i3 = i * 3;
      const k = Math.exp(-this.pdrag[i] * dt);
      v[i3] *= k; v[i3 + 1] = v[i3 + 1] * k + this.gravity * dt; v[i3 + 2] *= k;
      p[i3] += v[i3] * dt; p[i3 + 1] += v[i3 + 1] * dt; p[i3 + 2] += v[i3 + 2] * dt;
      if (this.flags[i] && this.onCollide && this.onCollide(p[i3], p[i3 + 1], p[i3 + 2], i)) {
        life[i] = 0; size[i] = 0; continue;
      }
      const t = age[i] / life[i];
      this.ramp(t, this.rampId[i], out, i);
      const i4 = i * 4;
      col[i4] = out[0]; col[i4 + 1] = out[1]; col[i4 + 2] = out[2]; col[i4 + 3] = out[3];
      size[i] = this.s0[i] + (this.s1[i] - this.s0[i]) * Math.sqrt(t);
    }
    this.alive = alive;
    this.posAttr.needsUpdate = true;
    this.colAttr.needsUpdate = true;
    this.sizeAttr.needsUpdate = true;
  }

  setScale(s) { this.material.uniforms.uScale.value = s; }
}

const sstep = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

function fireRamp(t, id, o) {
  const a = sstep(0, 0.06, t) * (1 - sstep(0.55, 1, t));
  if (id === 0) { // soffio del drago: nucleo bianco-giallo -> arancio -> rosso scuro
    if (t < 0.12) { const k = t / 0.12; o[0] = 3.2; o[1] = 2.6 - 1.0 * k; o[2] = 1.2 - 1.0 * k; }
    else if (t < 0.5) { const k = (t - 0.12) / 0.38; o[0] = 3.2 - 1.2 * k; o[1] = 1.6 - 1.0 * k; o[2] = 0.2 - 0.15 * k; }
    else { const k = (t - 0.5) / 0.5; o[0] = 2.0 - 1.5 * k; o[1] = 0.6 - 0.5 * k; o[2] = 0.05 - 0.04 * k; }
    o[3] = a * (0.35 + 0.5 * Math.min(1, t * 4));
  } else if (id === 1) { // fiamme degli edifici
    o[0] = 4.2 - 2.2 * t; o[1] = 1.9 - 1.5 * t; o[2] = 0.35 - 0.3 * t;
    o[3] = a * 0.8;
  } else { // esplosioni e palle di fuoco
    o[0] = 4 - 2.6 * t; o[1] = 2.3 - 2 * t; o[2] = 0.6 - 0.55 * t;
    o[3] = a * 0.7;
  }
}
function emberRamp(t, id, o, i) {
  const f = 0.6 + 0.4 * Math.sin(i * 1.7 + t * 40);
  o[0] = 9 * f; o[1] = 3.5 * f; o[2] = 0.6 * f;
  o[3] = 1 - sstep(0.6, 1, t);
}
function smokeRamp(t, id, o) {
  if (id === 1) { // vapore / nebbia marina
    o[0] = 0.85; o[1] = 0.88; o[2] = 0.92;
    o[3] = sstep(0, 0.1, t) * (1 - sstep(0.3, 1, t)) * 0.4;
  } else {
    const k = sstep(0, 0.5, t);
    o[0] = 0.09 + 0.16 * k; o[1] = 0.085 + 0.15 * k; o[2] = 0.08 + 0.15 * k;
    o[3] = sstep(0, 0.12, t) * (1 - sstep(0.4, 1, t)) * 0.55;
  }
}
function sprayRamp(t, id, o) {
  o[0] = 0.9; o[1] = 0.94; o[2] = 0.98;
  o[3] = sstep(0, 0.08, t) * (1 - sstep(0.4, 1, t)) * (id === 1 ? 0.75 : 0.5);
}

export class LightPool {
  constructor(scene, n = 6) {
    this.lights = [];
    for (let i = 0; i < n; i++) {
      const l = new THREE.PointLight(0xff7a2a, 0, 220, 1.6);
      scene.add(l);
      this.lights.push(l);
    }
    this.i = 0;
  }
  begin() { this.i = 0; }
  add(pos, intensity, color = 0xff7a2a) {
    if (this.i >= this.lights.length) return;
    const l = this.lights[this.i++];
    l.position.copy(pos);
    l.intensity = intensity;
    l.color.set(color);
  }
  end() { for (let i = this.i; i < this.lights.length; i++) this.lights[i].intensity = 0; }
}

const _v = new THREE.Vector3();

export class FX {
  constructor(scene, world, water, audio) {
    this.scene = scene;
    this.world = world;
    this.water = water;
    this.audio = audio;
    const fireTex = makeTexture('fire'), smokeTex = makeTexture('smoke'), sparkTex = makeTexture('spark');
    this.fire = new ParticleSystem(scene, { max: 9000, texture: fireTex, additive: true, gravity: 7, drag: 1.2, ramp: fireRamp });
    this.embers = new ParticleSystem(scene, { max: 1500, texture: sparkTex, additive: true, gravity: -6, drag: 0.6, ramp: emberRamp });
    this.smoke = new ParticleSystem(scene, { max: 4500, texture: smokeTex, gravity: 1.2, drag: 0.35, ramp: smokeRamp });
    this.spray = new ParticleSystem(scene, { max: 3000, texture: fireTex, gravity: -14, drag: 0.8, ramp: sprayRamp });
    this.systems = [this.fire, this.embers, this.smoke, this.spray];
    this.lights = new LightPool(scene, 6);
    this.fireballs = [];
    this.flashes = [];
    this.shake = 0;
    this.storm = null;
    this.breathAcc = 0;
    this.breathLight = 0;

    const fbGeo = new THREE.SphereGeometry(1, 16, 12);
    this.fbMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(3.5, 1.5, 0.35) });
    this.fbGeo = fbGeo;
    this.fbEnemyMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(2.2, 0.6, 3.2) });

    this.fire.onCollide = (x, y, z, i) => this.particleHit(x, y, z, this.fire.flags[i] === 2 ? 'enemy' : 'player');
    this.stats = { fireballs: 0 };
  }

  setScale(s) { for (const ps of this.systems) ps.setScale(s); }

  // Collisione delle fiamme del soffio con terreno, acqua ed edifici
  particleHit(x, y, z, owner) {
    const w = this.world;
    const g = w.groundHeight(x, z);
    if (y < g + 0.6 || y < 0.4) {
      const r = Math.random();
      if (g < 0.5) {
        if (r < 0.25) this.smoke.spawn(x, 0.6, z, (Math.random() - 0.5) * 4, 4 + Math.random() * 4, (Math.random() - 0.5) * 4, 2.5, 3, 14, 1);
      } else {
        if (r < 0.04) {
          const burnt = w.charTrees(x, z, 9, 3);
          if (burnt.length) this.audio?.crackle?.();
        }
        if (r < 0.12) this.fire.spawn(x, g + 1, z, (Math.random() - 0.5) * 6, 5 + Math.random() * 5, (Math.random() - 0.5) * 6, 0.7, 3, 6, 1);
        else if (r < 0.16) this.smoke.spawn(x, g + 2, z, 0, 5, 0, 4, 4, 18, 0);
      }
      return true;
    }
    const b = w.buildingAt(x, y, z);
    if (b) {
      if (w.ignite(b)) this.onIgnite?.(b, owner);
      return true;
    }
    return false;
  }

  // flag delle particelle: 1 = fuoco del giocatore, 2 = fuoco di un drago nemico
  emitBreath(dt, mouth, dir, dragonVel, intensity = 1, acc = this, flag = 1) {
    acc.breathAcc = (acc.breathAcc || 0) + dt * 560 * intensity;
    const up = Math.abs(dir.y) < 0.95 ? new THREE.Vector3(0, 1, 0) : new THREE.Vector3(1, 0, 0);
    const right = new THREE.Vector3().crossVectors(dir, up).normalize();
    const up2 = new THREE.Vector3().crossVectors(right, dir).normalize();
    while (acc.breathAcc >= 1) {
      acc.breathAcc -= 1;
      const a = Math.random() * Math.PI * 2, s = Math.sqrt(Math.random()) * 0.11;
      const dx = dir.x + (right.x * Math.cos(a) + up2.x * Math.sin(a)) * s;
      const dy = dir.y + (right.y * Math.cos(a) + up2.y * Math.sin(a)) * s;
      const dz = dir.z + (right.z * Math.cos(a) + up2.z * Math.sin(a)) * s;
      const sp = 95 + Math.random() * 35;
      const j = Math.random() * 2.5;
      this.fire.spawn(mouth.x + dir.x * j, mouth.y + dir.y * j, mouth.z + dir.z * j,
        dx * sp + dragonVel.x, dy * sp + dragonVel.y, dz * sp + dragonVel.z,
        0.75 + Math.random() * 0.35, 0.8 + Math.random() * 0.8, 7 + Math.random() * 5, 0, flag, 0.8);
      if (Math.random() < 0.05) {
        this.embers.spawn(mouth.x, mouth.y, mouth.z, dx * sp * 0.8 + dragonVel.x, dy * sp * 0.8 + dragonVel.y, dz * sp * 0.8 + dragonVel.z, 1.2, 0.5, 0.3, 0);
      }
    }
    if (acc === this) this.breathLight = 1;
  }

  // owner: 'player' o 'enemy' (decide chi viene danneggiato)
  launchFireball(pos, vel, size = 2.6, owner = 'player') {
    const mesh = new THREE.Mesh(this.fbGeo, owner === 'enemy' ? this.fbEnemyMat : this.fbMat);
    mesh.scale.setScalar(size);
    mesh.position.copy(pos);
    this.scene.add(mesh);
    this.fireballs.push({ mesh, pos: mesh.position, vel: vel.clone(), t: 0, size, acc: 0, owner });
    if (owner === 'player') this.audio?.whoosh?.(0.8);
  }

  startFirestorm(dragon) {
    this.storm = { t: 0, next: 0.25, n: 0, dragon, acc: 0 };
    this.audio?.roar?.();
    this.shake = Math.max(this.shake, 0.6);
  }

  explode(pos, size = 1, owner = 'player') {
    const w = this.world;
    const g = w.groundHeight(pos.x, pos.z);
    const onWater = g < 0.5 && pos.y < 3;
    const R = 36 * size;
    for (let i = 0; i < 170 * size; i++) {
      _v.set(Math.random() - 0.5, Math.random() * 0.8 - 0.1, Math.random() - 0.5).normalize();
      const sp = 15 + Math.random() * 55;
      this.fire.spawn(pos.x, pos.y + 1, pos.z, _v.x * sp, _v.y * sp, _v.z * sp, 0.6 + Math.random() * 0.9, 4 + Math.random() * 3, 12 + Math.random() * 10, 2, 0, 2.5);
    }
    for (let i = 0; i < 90 * size; i++) {
      _v.set(Math.random() - 0.5, Math.random() * 0.9, Math.random() - 0.5).normalize();
      const sp = 25 + Math.random() * 60;
      this.embers.spawn(pos.x, pos.y + 1, pos.z, _v.x * sp, _v.y * sp, _v.z * sp, 1.5 + Math.random() * 2, 0.7, 0.4, 0);
    }
    for (let i = 0; i < 35 * size; i++) {
      this.smoke.spawn(pos.x + (Math.random() - 0.5) * 20, pos.y + 4, pos.z + (Math.random() - 0.5) * 20,
        (Math.random() - 0.5) * 14, 6 + Math.random() * 10, (Math.random() - 0.5) * 14, 5 + Math.random() * 4, 10, 45, onWater ? 1 : 0);
    }
    if (onWater) {
      this.water.addPulse(pos.x, pos.z, 3.2 * size);
      for (let i = 0; i < 220 * size; i++) {
        const a = Math.random() * Math.PI * 2, r = Math.random() * 10;
        const sp = 10 + Math.random() * 30;
        this.spray.spawn(pos.x + Math.cos(a) * r, 0.5, pos.z + Math.sin(a) * r,
          Math.cos(a) * sp * 0.5, 15 + Math.random() * 40, Math.sin(a) * sp * 0.5, 1.5 + Math.random() * 1.5, 2.5, 9, 1);
      }
    } else if (pos.y - g < R) { // le esplosioni in volo non incendiano il suolo
      w.buildingsNear(pos.x, pos.z, R, (b) => {
        const d = Math.hypot(b.x - pos.x, b.z - pos.z);
        if (d < R + b.size * 0.5 && w.ignite(b, d * 0.012)) this.onIgnite?.(b, owner);
      });
      w.charTrees(pos.x, pos.z, R * 0.85, 40);
    }
    this.flashes.push({ pos: pos.clone().setY(pos.y + 6), t: 0 });
    this.onExplode?.(pos, size, owner);
  }

  update(dt, camPos, mouthPos) {
    // palle di fuoco
    for (let i = this.fireballs.length - 1; i >= 0; i--) {
      const f = this.fireballs[i];
      f.t += dt;
      f.vel.y -= 14 * dt;
      f.pos.addScaledVector(f.vel, dt);
      f.mesh.scale.setScalar(f.size * (0.9 + Math.random() * 0.25));
      f.acc += dt * 90;
      while (f.acc >= 1) {
        f.acc -= 1;
        this.fire.spawn(f.pos.x + (Math.random() - 0.5) * f.size, f.pos.y + (Math.random() - 0.5) * f.size, f.pos.z + (Math.random() - 0.5) * f.size,
          f.vel.x * 0.25 + (Math.random() - 0.5) * 6, f.vel.y * 0.25 + (Math.random() - 0.5) * 6, f.vel.z * 0.25 + (Math.random() - 0.5) * 6,
          0.3 + Math.random() * 0.3, f.size * 1.1, f.size * 2.4, 2);
        if (Math.random() < 0.15) this.smoke.spawn(f.pos.x, f.pos.y, f.pos.z, 0, 2, 0, 2.5, f.size * 2, f.size * 7, 0);
      }
      const g = this.world.groundHeight(f.pos.x, f.pos.z);
      const hit = f.pos.y < Math.max(g, 0.3) + f.size * 0.5 || this.world.buildingAt(f.pos.x, f.pos.y, f.pos.z) || f.t > 7 || this.hitTest?.(f);
      if (hit) {
        this.explode(f.pos, f.size / 2.6, f.owner);
        this.scene.remove(f.mesh);
        this.fireballs.splice(i, 1);
      }
    }

    // tempesta di fuoco
    if (this.storm) {
      const s = this.storm, d = s.dragon;
      s.t += dt;
      const dragonPos = d.position;
      while (s.next <= s.t && s.n < 30) {
        const a = s.n * 2.39996 + Math.random() * 0.3;
        const out = 0.45 + Math.random() * 0.5;
        _v.set(Math.cos(a) * out, -0.35 - Math.random() * 0.5, Math.sin(a) * out).normalize().multiplyScalar(60 + Math.random() * 40);
        _v.addScaledVector(d.velocity, 0.6);
        this.launchFireball(_v.clone().normalize().multiplyScalar(8).add(dragonPos), _v, 2.2 + Math.random() * 1.2);
        s.n++;
        s.next += 0.075;
      }
      // vortice di fiamme attorno al drago
      s.acc += dt * 300;
      while (s.acc >= 1) {
        s.acc -= 1;
        const a = Math.random() * Math.PI * 2;
        const r = 9 + s.t * 5 + Math.random() * 5;
        const tang = 40;
        this.fire.spawn(dragonPos.x + Math.cos(a) * r, dragonPos.y + (Math.random() - 0.6) * 14, dragonPos.z + Math.sin(a) * r,
          -Math.sin(a) * tang + Math.cos(a) * 18 + d.velocity.x, (Math.random() - 0.3) * 10 + d.velocity.y, Math.cos(a) * tang + Math.sin(a) * 18 + d.velocity.z,
          0.4 + Math.random() * 0.4, 2, 6, 0, 0, 2.5);
      }
      if (s.t > 2.6) this.storm = null;
    }

    for (const ps of this.systems) ps.update(dt);

    // luci dinamiche
    const L = this.lights;
    L.begin();
    for (let i = this.flashes.length - 1; i >= 0; i--) {
      const f = this.flashes[i];
      f.t += dt;
      if (f.t > 0.9) { this.flashes.splice(i, 1); continue; }
      L.add(f.pos, 30000 * Math.pow(1 - f.t / 0.9, 2), 0xffa040);
    }
    if (this.breathLight > 0 && mouthPos) {
      L.add(_v.copy(mouthPos).setY(mouthPos.y - 6), 2500 * this.breathLight * (0.8 + Math.random() * 0.4), 0xff8a30);
      this.breathLight = Math.max(0, this.breathLight - dt * 6);
    }
    const fbs = [...this.fireballs].sort((a, b) => a.pos.distanceToSquared(camPos) - b.pos.distanceToSquared(camPos));
    for (const f of fbs.slice(0, 2)) L.add(f.pos, 14000, 0xff9040);
    for (const b of this.world.nearestFires(camPos, 6)) {
      _v.set(b.x, lerpN(b.base, b.top, 0.6) + 4, b.z);
      L.add(_v, 9000 * b.fire * (0.75 + Math.random() * 0.25) * (0.6 + b.size * 0.05), 0xff7020);
    }
    L.end();

    this.shake = Math.max(0, this.shake - dt * 1.5);
  }
}

const lerpN = (a, b, t) => a + (b - a) * t;
