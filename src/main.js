// Il Volo del Drago — ciclo di gioco, camera in terza persona, HUD
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { World } from './world.js';
import { Water } from './water.js';
import { SkySystem } from './sky.js';
import { Clouds } from './clouds.js';
import { Dragon } from './dragon.js';
import { FX } from './fx.js';
import { Input } from './input.js';
import { AudioEngine } from './audio.js';
import { ScreenFlare } from './flare.js';
import { Enemies } from './enemies.js';
import { clamp, damp } from './noise.js';

const $ = (id) => document.getElementById(id);

// ---------- Renderer ----------
const renderer = new THREE.WebGLRenderer({ powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.5;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
$('app').appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(62, innerWidth / innerHeight, 1.5, 60000);

const rt = new THREE.WebGLRenderTarget(innerWidth, innerHeight, { type: THREE.HalfFloatType, samples: 4 });
const composer = new EffectComposer(renderer, rt);
composer.addPass(new RenderPass(scene, camera));
const bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), 0.35, 0.5, 1.4);
composer.addPass(bloom);
composer.addPass(new OutputPass());

const audio = new AudioEngine();
const input = new Input(renderer.domElement);

let world, water, sky, clouds, dragon, fx, enemies;
let ready = false, started = false, paused = false;

function particleScale() {
  const h = renderer.getDrawingBufferSize(new THREE.Vector2()).y;
  return h / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2));
}

function onResize() {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
  composer.setSize(innerWidth, innerHeight);
  if (fx) fx.setScale(particleScale());
}
addEventListener('resize', onResize);

// ---------- Inizializzazione (dopo un frame, per mostrare il caricamento) ----------
// (solo setTimeout: requestAnimationFrame non scatta nelle schede in background)
setTimeout(init, 60);

function init() {
  sky = new SkySystem(scene, renderer);
  world = new World(scene);
  water = new Water(scene, {
    envMap: sky.cubeRT.texture, heightTex: world.heightTex,
    sunDir: sky.sunDir, sunColor: new THREE.Vector3(3.2, 2.95, 2.6),
    fogColor: sky.fogColor, fogDensity: sky.fogDensity,
  });
  clouds = new Clouds(scene, { sunDir: sky.sunDir, fogColor: sky.fogColor, fogDensity: sky.fogDensity });
  dragon = new Dragon(scene);
  dragon.position.set(-300, 70, -2750);
  dragon.yaw = 0.15;
  fx = new FX(scene, world, water, audio);
  fx.setScale(particleScale());
  fx.onExplode = (pos, size, owner) => {
    const d = pos.distanceTo(camera.position);
    audio.explosion(d);
    fx.shake = Math.max(fx.shake, clamp(1.2 - d / 400, 0, 1) * size);
    if (owner === 'player') enemies.splash(pos, 45 * size, 45);
    if (owner === 'enemy' && playerAlive) {
      const pd = pos.distanceTo(dragon.position);
      if (pd < 30) damagePlayer(20 * (1 - pd / 30) + 4);
    }
  };
  // le palle di fuoco esplodono quando raggiungono un drago avversario
  fx.hitTest = (f) => f.owner === 'player' ? enemies.projectileHit(f.pos, f.size)
    : f.owner === 'enemy' && playerAlive && f.pos.distanceTo(dragon.position) < 8 + f.size;
  enemies = new Enemies(scene, world, fx, audio, $('enemyBars'));
  enemies.onKill = (e) => { showMsg(`${e.type.name} abbattuto!`); $('kills').textContent = enemies.kills; };
  enemies.onHostile = (e, reason) => {
    showMsg(reason === 'village' ? `${e.type.name} difende ${e.home.name}!` : `Hai provocato il ${e.type.name}!`, 'bad');
    const d = e.dragon.position.distanceTo(camera.position);
    audio.roar?.(Math.max(0.25, 1 - d / 2500));
    e.dragon.roaring = 1.5;
  };
  enemies.onCalm = (e) => showMsg(`${e.type.name} torna a sorvegliare ${e.home.name}`, 'small');
  // il guardiano di un villaggio si arrabbia solo se è il giocatore ad appiccare il fuoco
  fx.onIgnite = (b, owner) => { if (owner === 'player') enemies.villageAttacked(b.village); };
  $('total').textContent = world.stats.total;
  window.__game = { scene, camera, renderer, composer, bloom, world, water, sky, clouds, dragon, fx, input, audio, enemies, damagePlayer };
  camOffset.set(0, 10, -35);
  ready = true;
  $('loading').classList.add('hidden');
  $('play').classList.remove('hidden');
  $('play').addEventListener('click', startGame);
}

function startGame() {
  if (started || !ready) return;
  started = true;
  audio.start();
  $('start').classList.add('hidden');
  $('hud').classList.remove('hidden');
  dragon.throttle = 0.35;
  showMsg('Spicca il volo!', '');
  setTimeout(() => showMsg('Premi H per comandi e combinazioni', 'small'), 1400);
}

// ---------- Messaggi ----------
function showMsg(text, cls = '') {
  const el = document.createElement('div');
  el.className = 'msg ' + cls;
  el.textContent = text;
  $('msgs').appendChild(el);
  setTimeout(() => el.remove(), 1900);
}
let bannerTimer = 0;
function showBanner(title, sub) {
  const b = $('banner');
  b.innerHTML = `<small>${sub}</small>${title}`;
  b.classList.add('show');
  clearTimeout(bannerTimer);
  bannerTimer = setTimeout(() => b.classList.remove('show'), 2600);
}

// ---------- Camera in terza persona ----------
const camOffset = new THREE.Vector3();
const camUp = new THREE.Vector3(0, 1, 0);
const _o = new THREE.Vector3(), _t = new THREE.Vector3(), _r = new THREE.Vector3(), _q = new THREE.Quaternion();
const _h = new THREE.Vector3(), _g = new THREE.Vector3(), _up = new THREE.Vector3();
let camFov = 62, camDist = 34;

function updateCamera(dt, c) {
  const F = dragon.forward, U = dragon.up;
  const sf = clamp((dragon.speed - 30) / 130, 0, 1);
  camDist = damp(camDist, clamp(34 * Math.pow(1.1, c.zoom), 16, 110), 6, dt);
  const dist = camDist * (1 + sf * 0.12);
  _o.copy(F).multiplyScalar(-dist).addScaledVector(U, dist * 0.27);
  // orbita libera (mouse destro / levetta destra)
  _r.crossVectors(F, U).normalize();
  _q.setFromAxisAngle(U, c.lookX * Math.PI);
  _o.applyQuaternion(_q);
  _q.setFromAxisAngle(_r, c.lookY * 0.9);
  _o.applyQuaternion(_q);
  // a terra: camera che ruota attorno alla testa lungo la mira (stile terza persona),
  // così il drago resta inquadrato anche guardando in alto o in basso
  const gb = dragon.groundBlend;
  if (gb > 0.001) {
    dragon.head.getWorldPosition(_h);
    const A = dragon.aimDir;
    const k = camDist / 34;
    _g.copy(_h).addScaledVector(A, -34 * k).add(_up.set(0, 9 * k, 0)).sub(dragon.position);
    _o.lerp(_g, gb);
  }
  camOffset.lerp(_o, 1 - Math.exp(-dt * (4.5 + gb * 3)));
  camera.position.copy(dragon.position).add(camOffset);
  const g = Math.max(world.groundHeight(camera.position.x, camera.position.z), water.heightAt(camera.position.x, camera.position.z) + 1);
  if (camera.position.y < g + 3) camera.position.y = g + 3;
  camUp.lerp(gb > 0.5 ? _up.set(0, 1, 0) : U, 1 - Math.exp(-dt * 3)).normalize();
  camera.up.copy(camUp);
  _t.copy(dragon.position).addScaledVector(F, 10).addScaledVector(U, 2.5);
  if (gb > 0.001) _t.lerp(_g.copy(_h).addScaledVector(dragon.aimDir, 90), gb);
  if (fx.shake > 0) {
    const s = fx.shake * 1.6;
    camera.position.x += (Math.random() - 0.5) * s;
    camera.position.y += (Math.random() - 0.5) * s;
    camera.position.z += (Math.random() - 0.5) * s;
  }
  camera.lookAt(_t);
  const fov = 60 + sf * 16;
  if (Math.abs(fov - camFov) > 0.05) {
    camFov = damp(camFov, fov, 3, dt);
    camera.fov = camFov;
    camera.updateProjectionMatrix();
    fx.setScale(particleScale());
  }
}

// ---------- Stato di gioco ----------
const clock = new THREE.Clock();
let time = 0;
let energy = 100, stormCd = 0, fireballCd = 0, wakeT = 0, flapShake = 0;
let playerHp = 100, playerAlive = true, deadT = 0, lastHitT = -10, invuln = 0, crashed = false, hurt = 0;
const DEAD_CTRL = { steer: 0, climb: 0, throttle: 0, fire: false, lookX: 0, lookY: 0.15, zoom: 0, actions: [] };

function damagePlayer(amount) {
  if (!playerAlive || invuln > 0 || !started) return;
  playerHp -= amount;
  lastHitT = time;
  hurt = Math.min(1, hurt + amount / 25);
  fx.shake = Math.max(fx.shake, Math.min(0.8, amount / 30));
  if (playerHp <= 0) {
    playerHp = 0;
    playerAlive = false;
    deadT = 0; crashed = false;
    dragon.dying = true;
    dragon.breathing = false;
    audio.roar?.(0.8);
    showMsg('Sei stato abbattuto!', 'bad');
  }
}

// Polvere sollevata dalle ali vicino al suolo
function dust(pos, n, radius) {
  const g = Math.max(world.groundHeight(pos.x, pos.z), 0);
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, r = 4 + Math.random() * radius * 0.5, sp = 10 + Math.random() * radius;
    fx.smoke.spawn(pos.x + Math.cos(a) * r, g + 1, pos.z + Math.sin(a) * r,
      Math.cos(a) * sp, 2 + Math.random() * 4, Math.sin(a) * sp, 1.5 + Math.random() * 1.5, 4, 14, 0, 0, 1.5);
  }
}

function respawn() {
  playerAlive = true;
  playerHp = 100;
  invuln = 3;
  dragon.dying = false;
  dragon.mode = 'air';
  dragon.pitch = 0.3;
  dragon.position.y = Math.max(dragon.groundY, 0) + 180;
  energy = 100;
  showMsg('Di nuovo in volo!', 'small');
}
let currentVillage = null;
const mouth = new THREE.Vector3(), mouthDir = new THREE.Vector3();
const announced = new Set();
const hudEls = {};
for (const id of ['speed', 'alt', 'throttleBar', 'energyBar', 'stormBar', 'hpBar', 'hurt', 'crosshair', 'groundHint', 'destroyed', 'burning', 'warn', 'cloudFog']) hudEls[id] = $(id);
const mm = $('minimap').getContext('2d');

const flare = new ScreenFlare();

// Il sole è visibile? (montagne, nuvole, nebbia della nuvola in cui si vola)
function sunVisibility(inCloud) {
  const p = camera.position, s = sky.sunDir;
  for (let i = 1; i <= 30; i++) {
    const d = i * i * 6;
    const x = p.x + s.x * d, y = p.y + s.y * d, z = p.z + s.z * d;
    if (y < world.groundHeight(x, z)) return 0;
  }
  return Math.max(0, 1 - inCloud * 1.3) * (1 - clouds.occlusion(p, s));
}

function autopilot() {
  const t = time;
  return {
    steer: Math.sin(t * 0.13) * 0.35,
    climb: clamp((75 - dragon.altitude) / 60, -0.5, 0.5),
    throttle: 0, fire: false, lookX: Math.sin(t * 0.07) * 0.35, lookY: 0.05, zoom: 0, actions: [],
  };
}

function handleActions(actions) {
  for (const a of actions) {
    if (a === 'help') { $('help').classList.toggle('hidden'); continue; }
    if (a === 'mute') { audio.setMuted(!audio.muted); showMsg(audio.muted ? 'Audio disattivato' : 'Audio attivato', 'small'); continue; }
    if (a === 'invert') { showMsg(input.invertY ? 'Asse verticale invertito' : 'Asse verticale normale', 'small'); continue; }
    if (a === 'pad') { showMsg('Joystick collegato', 'small'); continue; }
    if (!started) continue;
    if (a === 'pause') { paused = !paused; $('pause').classList.toggle('hidden', !paused); continue; }
    if (paused || !playerAlive) continue;
    if (a === 'land') {
      if (dragon.mode === 'ground') { if (dragon.takeOff()) { audio.whoosh(1.2); showMsg('Decollo!', 'small'); } }
      else if (dragon.mode === 'air') {
        const r = dragon.land(world);
        if (r === 'ok') showMsg('Atterraggio…', 'small');
        else if (r === 'water') showMsg("Non puoi atterrare sull'acqua", 'bad');
        else if (r === 'high') showMsg('Scendi più in basso per atterrare', 'bad');
      }
      continue;
    }
    if (a === 'fireball') {
      if (energy >= 18 && fireballCd <= 0) {
        energy -= 18; fireballCd = 0.35;
        dragon.getMouth(mouth, mouthDir);
        if (dragon.mode === 'ground') mouthDir.copy(dragon.aimDir);
        // con un drago nemico nel mirino, la palla di fuoco punta dove si troverà
        const tgt = dragon.mode === 'air' ? enemies.target(dragon, 700, 0.45) : null;
        if (tgt) {
          const t = tgt.dragon.position.distanceTo(mouth) / 170;
          mouthDir.copy(tgt.dragon.position).addScaledVector(tgt.dragon.velocity, t).sub(mouth).normalize();
        }
        const v = mouthDir.clone().multiplyScalar(tgt ? 170 : 150).add(tgt ? dragon.velocity.clone().multiplyScalar(0.2) : dragon.velocity);
        fx.launchFireball(mouth.clone().addScaledVector(mouthDir, 3), v, 3);
        dragon.roaring = 0.3;
        showMsg('Palla di fuoco!');
      } else showMsg('Fuoco esaurito', 'bad');
    } else if (a === 'firestorm') {
      if (stormCd > 0) showMsg(`Tempesta pronta tra ${Math.ceil(stormCd)}s`, 'bad');
      else if (energy < 50) showMsg('Serve più fuoco', 'bad');
      else {
        energy -= 50; stormCd = 12;
        fx.startFirestorm(dragon);
        dragon.roaring = 2.4;
        showMsg('TEMPESTA DI FUOCO!');
      }
    } else if (a === 'rollLeft' || a === 'rollRight') {
      if (dragon.startRoll(a === 'rollLeft' ? -1 : 1)) { audio.whoosh(1); showMsg('Piroetta!', 'small'); }
    } else if (a === 'loop') {
      if (dragon.startLoop()) { audio.whoosh(1.3); showMsg('Giro della morte!', 'small'); }
    }
  }
}

function frame() {
  requestAnimationFrame(frame);
  const dt = Math.min(clock.getDelta(), 1 / 20);
  const ctrlIn = input.update(dt);
  if (!ready) return;
  if (!started && input.anyPress && ctrlIn.actions.length === 0 && (input.keys.has('Enter') || input.padPrev.a)) startGame();
  handleActions(ctrlIn.actions);
  if (paused) { composer.render(); return; }
  time += dt;
  let c = !started ? autopilot() : playerAlive ? ctrlIn : DEAD_CTRL;
  // a terra: W/S cammina, A/D gira, frecce/mouse destro/levetta destra muovono la testa
  const grounded = dragon.mode !== 'air';
  input.setPointerLock(started && playerAlive && dragon.mode === 'ground');
  if (grounded && c === ctrlIn) {
    c = { ...ctrlIn, steer: ctrlIn.walkSteer, climb: ctrlIn.walk, lookX: 0, lookY: 0 };
  }

  // mira assistita sul drago nemico più vicino davanti (solo in volo)
  const aim = started && playerAlive && !grounded ? enemies.target(dragon) : null;
  dragon.aimTarget = aim ? aim.dragon.position : null;
  hudEls.crosshair.classList.toggle('neutral', !!aim && !aim.hostile);

  // soffio di fuoco
  const breathing = started && playerAlive && c.fire && energy > 1;
  dragon.breathing = breathing;
  const ev = dragon.update(dt, c, world);
  if (ev.touchdown) {
    audio.flap(1.6);
    fx.shake = Math.max(fx.shake, 0.5);
    dust(dragon.position, 70, 26);
    showMsg('A terra', 'small');
  }
  if (ev.downstroke && grounded) dust(dragon.position, 25, 18);
  if (breathing) {
    energy = Math.max(0, energy - dt * 22);
    dragon.getMouth(mouth, mouthDir);
    if (dragon.mode === 'ground') mouthDir.copy(dragon.aimDir); // a terra il fuoco va esattamente dove guarda la testa
    fx.emitBreath(dt, mouth, mouthDir, dragon.velocity);
    for (const e of enemies.list) {
      if (!e.dragon.dying && Enemies.inBreath(mouth, mouthDir, e.dragon.position, 8 * e.type.scale / 0.5)) enemies.damage(e, 34 * dt);
    }
  } else {
    energy = Math.min(100, energy + dt * (c.fire ? 0 : 14));
  }
  stormCd = Math.max(0, stormCd - dt);
  fireballCd = Math.max(0, fireballCd - dt);

  // spostamento d'aria sul mare
  const px = dragon.position.x, pz = dragon.position.z;
  const overWater = world.groundHeight(px, pz) < 0.5;
  const h = dragon.position.y;
  const down = overWater ? clamp(1 - (h - 8) / 55, 0, 1) * (0.45 + 0.55 * Math.min(1, dragon.power)) * (1 - dragon.fold * 0.6) : 0;
  const dx = px - dragon.forward.x * 5, dz = pz - dragon.forward.z * 5;
  if (ev.downstroke) {
    audio.flap(Math.min(1.2, dragon.power) * (started ? 1 : 0.5));
    flapShake = 0.12 * dragon.power;
    if (down > 0.08) {
      water.addPulse(dx, dz, 0.9 * down);
      for (let i = 0; i < 70 * down; i++) {
        const a = Math.random() * Math.PI * 2, r = 4 + Math.random() * 10, sp = 20 + Math.random() * 25;
        fx.spray.spawn(dx + Math.cos(a) * r, 0.5, dz + Math.sin(a) * r, Math.cos(a) * sp, 6 + Math.random() * 12, Math.sin(a) * sp, 1 + Math.random(), 1.2, 4.5, 1);
      }
    }
  }
  if (down > 0.15) {
    wakeT += dt;
    if (wakeT > 0.25) { wakeT = 0; water.addPulse(dx, dz, 0.45 * down); }
    const n = Math.floor(dt * 220 * down + Math.random());
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2, r = 5 + Math.random() * 16, sp = 14 + Math.random() * 22;
      fx.spray.spawn(dx + Math.cos(a) * r, 0.4, dz + Math.sin(a) * r,
        Math.cos(a) * sp + dragon.velocity.x * 0.3, 3 + Math.random() * 7, Math.sin(a) * sp + dragon.velocity.z * 0.3,
        0.8 + Math.random() * 1.2, 0.8, 3.2, 0);
      if (Math.random() < 0.15) fx.smoke.spawn(dx + Math.cos(a) * r, 1.5, dz + Math.sin(a) * r, Math.cos(a) * sp * 0.4, 2, Math.sin(a) * sp * 0.4, 2.5, 6, 20, 1);
    }
  }
  // combattimento con i draghi nemici
  if (started) {
    if (fx.storm) {
      for (const e of enemies.list) if (e.dragon.position.distanceTo(dragon.position) < 55) enemies.damage(e, 45 * dt);
    }
    const ev2 = enemies.update(dt, dragon, playerAlive, camera);
    if (ev2.playerDamage > 0) damagePlayer(ev2.playerDamage);
    invuln = Math.max(0, invuln - dt);
    hurt = Math.max(0, hurt - dt * 1.5);
    if (playerAlive && time - lastHitT > 5) playerHp = Math.min(100, playerHp + dt * 4);
    if (!playerAlive) {
      deadT += dt;
      if (Math.random() < dt * 40) {
        const p = dragon.position;
        fx.fire.spawn(p.x, p.y, p.z, (Math.random() - 0.5) * 6, 4, (Math.random() - 0.5) * 6, 0.6, 3, 8, 1);
        fx.smoke.spawn(p.x, p.y, p.z, 0, 3, 0, 4, 5, 20, 0);
      }
      if (!crashed && dragon.altitude < 3) { crashed = true; fx.explode(dragon.position.clone(), 1, 'none'); }
      if (deadT > 4) respawn();
    }
  }
  water.update(dt, camera.position, dx, dz, down);
  world.update(dt, time, fx, camera.position);
  world.scorch.update(dt, renderer);
  fx.update(dt, camera.position, breathing ? mouth : null);
  fx.shake = Math.max(fx.shake, flapShake);
  flapShake = Math.max(0, flapShake - dt * 0.8);

  updateCamera(dt, c);
  const inCloud = clouds.update(dt, camera);
  sky.update(camera, dragon.position);
  flare.update(dt, camera, sky.sunDir, sunVisibility(inCloud));

  // audio
  let burnNear = 0;
  for (const b of world.nearestFires(camera.position, 4)) {
    const d = Math.hypot(b.x - camera.position.x, b.z - camera.position.z);
    burnNear += b.fire / (1 + d / 120);
  }
  audio.update({ speed: dragon.speed, breathing, water: overWater ? clamp(1 - dragon.altitude / 120, 0, 1) : 0, burn: burnNear, inCloud });

  hudEls.cloudFog.style.opacity = (inCloud * 0.9).toFixed(3);
  if (started) updateHUD();
  composer.render();
}

function updateHUD() {
  hudEls.speed.textContent = Math.round(dragon.speed * 3.6);
  hudEls.alt.textContent = dragon.mode === 'ground' ? 'a terra' : Math.round(dragon.altitude);
  hudEls.alt.nextElementSibling.style.visibility = dragon.mode === 'ground' ? 'hidden' : 'visible';
  hudEls.throttleBar.style.width = (dragon.throttle * 100).toFixed(1) + '%';
  hudEls.energyBar.style.width = energy.toFixed(1) + '%';
  hudEls.stormBar.style.width = ((1 - stormCd / 12) * 100).toFixed(1) + '%';
  hudEls.stormBar.classList.toggle('ready', stormCd <= 0 && energy >= 50);
  hudEls.hpBar.style.width = playerHp.toFixed(1) + '%';
  hudEls.hpBar.classList.toggle('low', playerHp < 30);
  hudEls.hurt.style.opacity = Math.min(1, hurt * 0.9 + (playerHp < 30 ? 0.25 + 0.15 * Math.sin(time * 6) : 0)).toFixed(3);
  // mirino sul drago nemico agganciato
  // a terra il mirino mostra dove andrà il fuoco
  const onGround = dragon.mode === 'ground';
  const locked = onGround || (dragon.aimTarget && dragon.aimOk);
  hudEls.crosshair.classList.toggle('hidden', !locked);
  hudEls.crosshair.classList.toggle('ground', onGround);
  hudEls.groundHint.classList.toggle('hidden', !onGround);
  hudEls.groundHint.textContent = input.pointerLocked
    ? 'Mouse: mira · Esc: libera il mouse · L: decolla'
    : 'Clic: mira col mouse · Frecce/levetta destra: testa · L: decolla';
  if (locked) {
    if (onGround) {
      dragon.getMouth(_t, _g);
      _t.addScaledVector(dragon.aimDir, 90);
    } else _t.copy(dragon.aimTarget);
    const p = _t.project(camera);
    hudEls.crosshair.style.left = ((p.x * 0.5 + 0.5) * 100).toFixed(2) + '%';
    hudEls.crosshair.style.top = ((-p.y * 0.5 + 0.5) * 100).toFixed(2) + '%';
  }
  hudEls.destroyed.textContent = world.stats.destroyed;
  hudEls.burning.textContent = world.stats.burning;
  hudEls.warn.classList.toggle('hidden', !dragon.outOfBounds);

  // villaggio sorvolato
  let near = null;
  for (const v of world.villages) if (Math.hypot(v.x - dragon.position.x, v.z - dragon.position.z) < v.r + 160) near = v;
  if (near && near !== currentVillage) {
    const g = enemies.guardianOf(near);
    showBanner(near.name, (near.kind === 'castle' ? 'Fortezza' : 'Villaggio') + (g ? ` · protetto dal ${g.type.name}` : ''));
  }
  currentVillage = near;
  for (const v of world.villages) {
    if (announced.has(v)) continue;
    const done = v.ids.filter(id => world.buildings[id].state === 2).length;
    if (v.ids.length && done / v.ids.length > 0.85) { announced.add(v); showMsg(`${v.name} è in rovina!`); }
  }
  drawMinimap();
}

function drawMinimap() {
  const S = 200, sc = world.minimapScale, H = world.minimapHalf;
  const toMap = (x, z) => [(x + H) * sc, (z + H) * sc];
  mm.save();
  mm.clearRect(0, 0, S, S);
  mm.beginPath(); mm.arc(S / 2, S / 2, S / 2, 0, Math.PI * 2); mm.clip();
  mm.drawImage(world.minimapBase, 0, 0);
  for (const v of world.villages) {
    const [x, y] = toMap(v.x, v.z);
    const burnt = v.ids.filter(id => world.buildings[id].state > 0).length / Math.max(1, v.ids.length);
    mm.fillStyle = burnt > 0.85 ? '#222' : burnt > 0 ? '#ff5a1f' : '#ffe2a8';
    mm.strokeStyle = '#000';
    mm.lineWidth = 1;
    if (v.kind === 'castle') { mm.fillRect(x - 4, y - 4, 8, 8); mm.strokeRect(x - 4, y - 4, 8, 8); }
    else { mm.beginPath(); mm.arc(x, y, 3.5, 0, Math.PI * 2); mm.fill(); mm.stroke(); }
  }
  mm.fillStyle = `rgba(255,${80 + Math.random() * 60},20,0.9)`;
  for (const b of world.burning) {
    if (b.fire < 0.2) continue;
    const [x, y] = toMap(b.x, b.z);
    mm.fillRect(x - 1, y - 1, 2, 2);
  }
  for (const e of enemies.list) {
    const [x, y] = toMap(e.dragon.position.x, e.dragon.position.z);
    mm.fillStyle = e.dragon.dying ? '#555' : e.hostile ? '#ff2a2a' : '#ffc23a';
    mm.strokeStyle = '#000';
    mm.lineWidth = 1;
    mm.beginPath(); mm.moveTo(x, y - 5); mm.lineTo(x + 4, y + 3); mm.lineTo(x - 4, y + 3); mm.closePath();
    mm.fill(); mm.stroke();
  }
  const [dx, dy] = toMap(dragon.position.x, dragon.position.z);
  mm.translate(dx, dy);
  mm.rotate(Math.atan2(-Math.sin(dragon.yaw), Math.cos(dragon.yaw)));
  mm.fillStyle = '#fff';
  mm.strokeStyle = '#a00';
  mm.lineWidth = 1.5;
  mm.beginPath(); mm.moveTo(0, 8); mm.lineTo(-5, -5); mm.lineTo(0, -2); mm.lineTo(5, -5); mm.closePath();
  mm.fill(); mm.stroke();
  mm.restore();
}

frame();
