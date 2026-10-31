// Draghi nemici: pattugliano il cielo, inseguono il giocatore, sputano fuoco e palle di fuoco.
// Hanno una barra della vita; quando muoiono precipitano in fiamme ed esplodono.
import * as THREE from 'three';
import { Dragon } from './dragon.js';
import { clamp } from './noise.js';

const TYPES = [
  {
    name: 'Drago di Smeraldo', hp: 100, scale: 0.5, speed: 0.55, fireballEvery: 3.2,
    palette: { back: [0.06, 0.3, 0.1], ridge: [0.02, 0.12, 0.04], belly: [0.75, 0.7, 0.35], skin: 0x0f4a1c, dark: 0x0a2a10, membrane: 0x1f5a22, membraneGlow: 0x041a06, eye: [0.6, 1, 0.2] },
  },
  {
    name: 'Drago di Zaffiro', hp: 120, scale: 0.52, speed: 0.65, fireballEvery: 2.6,
    palette: { back: [0.05, 0.15, 0.45], ridge: [0.02, 0.05, 0.2], belly: [0.7, 0.75, 0.85], skin: 0x123070, dark: 0x0a1840, membrane: 0x1e3a7a, membraneGlow: 0x040a24, eye: [0.3, 0.9, 1] },
  },
  {
    name: "Drago d'Ambra", hp: 140, scale: 0.56, speed: 0.6, fireballEvery: 3.0,
    palette: { back: [0.55, 0.35, 0.05], ridge: [0.3, 0.15, 0.02], belly: [0.9, 0.8, 0.5], skin: 0x6a3e0a, dark: 0x3a2205, membrane: 0x7a4a10, membraneGlow: 0x201004, eye: [1, 0.5, 0.1] },
  },
  {
    name: "Drago d'Ombra", hp: 220, scale: 0.7, speed: 0.75, fireballEvery: 2.0,
    palette: { back: [0.08, 0.07, 0.1], ridge: [0.03, 0.03, 0.04], belly: [0.35, 0.3, 0.4], skin: 0x1a1820, dark: 0x111015, membrane: 0x2a2233, membraneGlow: 0x0a0410, eye: [0.8, 0.2, 1] },
  },
];

const GUARD_RADIUS = 2200; // oltre questa distanza dal villaggio il guardiano smette di inseguire
const CALM_TIME = 25;      // secondi fuori dal territorio prima che si calmi
const BREATH_RANGE = 110;
const _to = new THREE.Vector3(), _m = new THREE.Vector3(), _d = new THREE.Vector3(), _aim = new THREE.Vector3();
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

export class Enemies {
  constructor(scene, world, fx, audio, barsEl) {
    this.scene = scene;
    this.world = world;
    this.fx = fx;
    this.audio = audio;
    this.barsEl = barsEl;
    this.list = [];
    this.kills = 0;
    this.maxGuardians = 5;
    this.spawnTimer = 0;
    this.started = false;
    this.onKill = null;
  }

  // Villaggi senza guardiano (il castello è riservato al drago d'Ombra)
  unguarded() {
    const guarded = new Set(this.list.map(e => e.home));
    return this.world.villages.filter(v => !guarded.has(v));
  }

  // Ogni drago protegge un villaggio: nasce lì e ci vola intorno
  spawn(home, type) {
    const dragon = new Dragon(this.scene, { scale: type.scale, palette: type.palette });
    const ground = Math.max(this.world.groundHeight(home.x, home.z), 0);
    const a = Math.random() * Math.PI * 2, r = home.r + 150 + Math.random() * 120;
    dragon.position.set(home.x + Math.cos(a) * r, ground + 130 + Math.random() * 60, home.z + Math.sin(a) * r);
    dragon.yaw = a + Math.PI / 2;
    dragon.throttle = 0.3;
    const el = document.createElement('div');
    el.className = 'ebar';
    el.innerHTML = `<div class="ename">${type.name}</div><div class="ehome">guardiano di ${home.name}</div><div class="etrack"><div class="efill"></div></div>`;
    this.barsEl.appendChild(el);
    this.list.push({
      dragon, type, home, hp: type.hp, maxHp: type.hp, el, fill: el.querySelector('.efill'),
      patrol: { a, r, alt: ground + 130 + Math.random() * 60 },
      fireCd: 2 + Math.random() * 2, breathT: 0, breathCd: 0, flash: 0,
      hostile: false, calmT: 0, dyingT: 0, acc: {}, smokeAcc: 0,
    });
  }

  spawnInitial(player) {
    const castle = this.world.villages.find(v => v.kind === 'castle');
    if (castle) this.spawn(castle, TYPES[3]);
    const villages = this.world.villages.filter(v => v.kind === 'village')
      .sort((a, b) => Math.hypot(a.x - player.position.x, a.z - player.position.z) - Math.hypot(b.x - player.position.x, b.z - player.position.z));
    // un guardiano ogni due villaggi, partendo dai più vicini
    for (let i = 0; i < villages.length && this.list.length < this.maxGuardians; i += 2) this.spawn(villages[i], TYPES[(this.list.length) % 3]);
  }

  guardianOf(village) {
    return this.list.find(e => e.home === village && !e.dragon.dying);
  }

  provoke(e, reason) {
    if (!e || e.dragon.dying) return;
    e.calmT = 0;
    if (e.hostile) return;
    e.hostile = true;
    e.fireCd = Math.min(e.fireCd, 1.5);
    this.onHostile?.(e, reason);
  }

  // Un edificio di un villaggio è stato incendiato dal giocatore
  villageAttacked(village) {
    if (village) this.provoke(this.guardianOf(village), 'village');
  }

  alive() { return this.list.filter(e => !e.dragon.dying); }

  damage(e, amount) {
    if (e.dragon.dying) return;
    e.hp -= amount;
    e.flash = 1;
    this.provoke(e, 'attack');
    if (e.hp <= 0) {
      e.hp = 0;
      e.dragon.dying = true;
      e.dragon.breathing = false;
      this.audio.roar?.(0.6);
    }
  }

  // Danno ad area (esplosioni del giocatore)
  splash(pos, radius, amount) {
    for (const e of this.list) {
      const d = e.dragon.position.distanceTo(pos);
      if (d < radius) this.damage(e, amount * (1 - d / radius * 0.6));
    }
  }

  // Una palla di fuoco del giocatore ha colpito un drago?
  projectileHit(pos, size) {
    return this.list.some(e => !e.dragon.dying && e.dragon.position.distanceTo(pos) < 9 * e.type.scale / 0.5 + size);
  }

  // Bersaglio per la mira assistita: il nemico più vicino davanti al giocatore
  target(player, maxDist = 320, cone = 0.55) {
    let best = null, bestD = Infinity;
    for (const e of this.list) {
      if (e.dragon.dying) continue;
      _to.subVectors(e.dragon.position, player.position);
      const d = _to.length();
      if (d > maxDist || d < 1) continue;
      if (_to.divideScalar(d).dot(player.forward) < Math.cos(cone)) continue;
      if (d < bestD) { best = e; bestD = d; }
    }
    return best;
  }

  // Cono del soffio: il bersaglio è dentro le fiamme?
  static inBreath(mouth, dir, target, radius, range = BREATH_RANGE) {
    _d.subVectors(target, mouth);
    const d = _d.length();
    if (d > range) return false;
    const ang = _d.divideScalar(Math.max(d, 0.01)).angleTo(dir);
    return ang < Math.atan(radius / Math.max(d, 1)) + 0.12;
  }

  update(dt, player, playerAlive, camera) {
    const events = { playerDamage: 0 };
    const P = player.position;
    if (!this.started) { this.started = true; this.spawnInitial(player); this.spawnTimer = 45; }
    // un nuovo guardiano arriva in un villaggio scoperto, lontano dal giocatore
    if (this.alive().length < this.maxGuardians) {
      this.spawnTimer -= dt;
      if (this.spawnTimer <= 0) {
        const free = this.unguarded().filter(v => v.kind === 'village' && Math.hypot(v.x - P.x, v.z - P.z) > 1200);
        if (free.length) this.spawn(free[Math.floor(Math.random() * free.length)], TYPES[Math.floor(Math.random() * 3)]);
        this.spawnTimer = 45 + Math.random() * 20;
      }
    }

    for (let i = this.list.length - 1; i >= 0; i--) {
      const e = this.list[i], d = e.dragon;
      _to.subVectors(P, d.position);
      const dist = _to.length();
      const ctrl = { steer: 0, climb: 0, throttle: 0, fire: false };

      if (!d.dying) {
        // ostile solo se provocato; insegue finché il giocatore resta nel suo territorio
        const fromHome = Math.hypot(P.x - e.home.x, P.z - e.home.z);
        const engaged = e.hostile && playerAlive && fromHome < GUARD_RADIUS && dist < 2600;
        if (e.hostile && !engaged) {
          e.calmT += dt;
          if (e.calmT > CALM_TIME) { e.hostile = false; e.calmT = 0; this.onCalm?.(e); }
        }
        let tx, ty, tz;
        if (engaged) {
          // insegue con un po' di anticipo, restando leggermente sopra
          tx = P.x + player.velocity.x * 0.6; tz = P.z + player.velocity.z * 0.6; ty = P.y + 12;
          if (dist < 55) { tx = d.position.x - _to.x; tz = d.position.z - _to.z; ty = d.position.y + 30; } // si allontana
        } else {
          // ronda attorno al proprio villaggio
          e.patrol.a += dt * 0.16;
          tx = e.home.x + Math.cos(e.patrol.a) * e.patrol.r;
          tz = e.home.z + Math.sin(e.patrol.a) * e.patrol.r;
          ty = Math.max(e.patrol.alt, this.world.groundHeight(tx, tz) + 60);
        }
        const err = wrap(Math.atan2(tx - d.position.x, tz - d.position.z) - d.yaw);
        ctrl.steer = clamp(-err * 2.2, -1, 1);
        ctrl.climb = clamp((ty - d.position.y) / 60, -1, 1);
        const want = engaged ? (dist > 350 ? e.type.speed + 0.25 : dist < 130 ? e.type.speed - 0.25 : e.type.speed) : 0.3;
        ctrl.throttle = Math.abs(want - d.throttle) < 0.03 ? 0 : Math.sign(want - d.throttle);

        const facing = engaged ? _d.copy(_to).normalize().dot(d.forward) : -1;
        d.aimTarget = engaged && dist < 400 ? P : null;
        // soffio di fuoco a raffiche quando è vicino
        e.breathCd -= dt;
        if (engaged && dist < BREATH_RANGE + 20 && facing > 0.8 && e.breathCd <= 0) { e.breathT = 1.2 + Math.random(); e.breathCd = 3 + Math.random() * 2; }
        e.breathT -= dt;
        d.breathing = e.breathT > 0;
        // palle di fuoco a media distanza
        e.fireCd -= dt;
        if (engaged && dist > 140 && dist < 650 && facing > 0.85 && e.fireCd <= 0) {
          e.fireCd = e.type.fireballEvery * (0.7 + Math.random() * 0.6);
          d.getMouth(_m, _aim);
          const speed = 150;
          _aim.copy(P).addScaledVector(player.velocity, dist / speed * 0.6).sub(_m).normalize();
          this.fx.launchFireball(_m.clone().addScaledVector(_aim, 3), _aim.multiplyScalar(speed).addScaledVector(d.velocity, 0.3), 2.2, 'enemy');
          d.roaring = 0.3;
        }
      } else {
        d.breathing = false;
        d.aimTarget = null;
        e.dyingT += dt;
        // scia di fuoco e fumo durante la caduta
        e.smokeAcc += dt * 40;
        while (e.smokeAcc >= 1) {
          e.smokeAcc -= 1;
          const p = d.position;
          this.fx.fire.spawn(p.x + (Math.random() - 0.5) * 6, p.y, p.z + (Math.random() - 0.5) * 6, (Math.random() - 0.5) * 6, 4, (Math.random() - 0.5) * 6, 0.6, 3, 7, 1);
          if (Math.random() < 0.5) this.fx.smoke.spawn(p.x, p.y, p.z, 0, 3, 0, 4, 4, 18, 0);
        }
      }

      // i draghi lontani non animano corpo e ali (risparmio di calcoli)
      const far = dist > 2500;
      d.root.visible = dist < 7000;
      const ev = d.update(dt, ctrl, this.world, !far);
      if (ev.downstroke && dist < 500) this.audio.flap?.(d.power * (1 - dist / 500) * 0.6);
      if (d.breathing) {
        d.getMouth(_m, _d);
        this.fx.emitBreath(dt, _m, _d, d.velocity, 0.6, e.acc, 2);
        if (playerAlive && Enemies.inBreath(_m, _d, P, 9)) events.playerDamage += 16 * dt;
      }

      // schianto a terra / in mare
      if (d.dying && (d.altitude < 3 || e.dyingT > 8)) {
        this.fx.explode(d.position.clone(), 1.3, 'none');
        d.dispose();
        e.el.remove();
        this.list.splice(i, 1);
        this.kills++;
        this.onKill?.(e);
        continue;
      }

      // lampo quando viene colpito
      e.flash = Math.max(0, e.flash - dt * 4);
      d.mats.body.emissive.setRGB(e.flash * 0.9, e.flash * 0.35, e.flash * 0.1);
      d.mats.skin.emissive.copy(d.mats.body.emissive);
      this.updateBar(e, dist, camera);
    }
    return events;
  }

  updateBar(e, dist, camera) {
    const p = _d.copy(e.dragon.position);
    p.y += 9 * e.type.scale / 0.5;
    p.project(camera);
    const visible = dist < 1600 && p.z < 1 && Math.abs(p.x) < 1.1 && Math.abs(p.y) < 1.1;
    e.el.style.display = visible ? 'block' : 'none';
    if (!visible) return;
    e.el.style.transform = `translate(${(p.x * 0.5 + 0.5) * innerWidth}px, ${(-p.y * 0.5 + 0.5) * innerHeight}px) translate(-50%, -100%)`;
    e.el.style.opacity = dist < 900 ? 1 : 1 - (dist - 900) / 700;
    e.fill.style.width = (e.hp / e.maxHp * 100).toFixed(1) + '%';
    e.el.classList.toggle('dying', e.dragon.dying);
    e.el.classList.toggle('hostile', e.hostile);
  }
}
