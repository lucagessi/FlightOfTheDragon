// Bagliori del sole sulla lente, disegnati come livello sopra il canvas.
// (Il Lensflare di three.js non funziona con il render target multicampionato del compositore.)
import * as THREE from 'three';

const ELEMENTS = [
  { pos: 0, size: 340, cls: 'glow', a: 0.55 },
  { pos: 0, size: 140, cls: 'core', a: 1 },
  { pos: 0, size: 760, cls: 'streak', a: 0.5 },
  { pos: 0.35, size: 60, cls: 'hex blue', a: 0.35 },
  { pos: 0.55, size: 110, cls: 'hex violet', a: 0.25 },
  { pos: 0.72, size: 40, cls: 'hex green', a: 0.35 },
  { pos: 0.9, size: 230, cls: 'ring', a: 0.25 },
  { pos: 1.15, size: 80, cls: 'hex gold', a: 0.3 },
  { pos: 1.4, size: 150, cls: 'hex blue', a: 0.2 },
];

export class ScreenFlare {
  constructor() {
    this.root = document.createElement('div');
    this.root.id = 'flare';
    document.body.insertBefore(this.root, document.getElementById('cloudFog'));
    this.els = ELEMENTS.map(e => {
      const d = document.createElement('div');
      d.className = 'fl ' + e.cls;
      d.style.width = d.style.height = e.size + 'px';
      this.root.appendChild(d);
      return d;
    });
    this.vis = 0;
    this.v = new THREE.Vector3();
  }

  update(dt, camera, sunDir, visibility) {
    const v = this.v.copy(camera.position).addScaledVector(sunDir, 5000).project(camera);
    const camDir = camera.getWorldDirection(new THREE.Vector3());
    const front = camDir.dot(sunDir) > 0 && v.z < 1;
    const edge = front ? Math.max(0, 1 - Math.max(Math.abs(v.x), Math.abs(v.y)) * 0.85) : 0;
    const target = visibility * Math.min(1, edge * 2.5);
    this.vis += (target - this.vis) * Math.min(1, dt * 8);
    if (this.vis < 0.01) { this.root.style.display = 'none'; return; }
    this.root.style.display = 'block';
    const W = innerWidth, H = innerHeight;
    const sx = (v.x * 0.5 + 0.5) * W, sy = (-v.y * 0.5 + 0.5) * H;
    const cx = W / 2, cy = H / 2;
    const scale = Math.min(W, H) / 900;
    ELEMENTS.forEach((e, i) => {
      const x = sx + (cx - sx) * e.pos * 2, y = sy + (cy - sy) * e.pos * 2;
      const el = this.els[i];
      el.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%) scale(${scale})`;
      el.style.opacity = (e.a * this.vis).toFixed(3);
    });
  }
}
