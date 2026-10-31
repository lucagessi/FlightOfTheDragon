// Mappa delle bruciature sul terreno: chiazze nere permanenti + braci che si spengono col tempo.
// Disegnata su canvas e caricata sulla GPU solo nella zona modificata.
import * as THREE from 'three';

export class ScorchMap {
  constructor(extent, size = 2048, heatSize = 512) {
    this.extent = extent;
    this.half = extent / 2;
    this.size = size;
    this.heatSize = heatSize;

    this.canvas = document.createElement('canvas');
    this.canvas.width = this.canvas.height = size;
    this.ctx = this.canvas.getContext('2d', { willReadFrequently: false });
    this.ctx.fillStyle = '#000';
    this.ctx.fillRect(0, 0, size, size);
    this.texture = new THREE.CanvasTexture(this.canvas);
    this.texture.flipY = false;
    this.texture.colorSpace = THREE.NoColorSpace;
    this.texture.generateMipmaps = false;
    this.texture.minFilter = THREE.LinearFilter;

    this.heatCanvas = document.createElement('canvas');
    this.heatCanvas.width = this.heatCanvas.height = heatSize;
    this.heatCtx = this.heatCanvas.getContext('2d');
    this.heatCtx.fillStyle = '#000';
    this.heatCtx.fillRect(0, 0, heatSize, heatSize);
    this.heatTexture = new THREE.CanvasTexture(this.heatCanvas);
    this.heatTexture.flipY = false;
    this.heatTexture.colorSpace = THREE.NoColorSpace;
    this.heatTexture.generateMipmaps = false;
    this.heatTexture.minFilter = THREE.LinearFilter;

    this.dirty = null;       // rettangolo modificato (pixel)
    this.heatDirty = false;
    this.timer = 0;
    this.fadeTimer = 0;
    this.uploaded = false;
    this.patch = document.createElement('canvas');
    this.patchTex = new THREE.CanvasTexture(this.patch);
    this.patchTex.flipY = false;
    this.patchTex.colorSpace = THREE.NoColorSpace;
    this.patchTex.generateMipmaps = false;
    this._pos = new THREE.Vector2();
  }

  // Aggiunge una bruciatura nel punto (x, z) del mondo
  add(x, z, radius, strength = 0.5, heat = 0.8) {
    const k = this.size / this.extent;
    const px = (x + this.half) * k, py = (z + this.half) * k, pr = Math.max(1.5, radius * k);
    if (px < -pr || py < -pr || px > this.size + pr || py > this.size + pr) return;
    const c = this.ctx;
    // forma irregolare: qualche macchia sovrapposta
    for (let i = 0; i < 3; i++) {
      const ox = (Math.random() - 0.5) * pr * 0.6, oy = (Math.random() - 0.5) * pr * 0.6, r = pr * (0.6 + Math.random() * 0.5);
      const g = c.createRadialGradient(px + ox, py + oy, 0, px + ox, py + oy, r);
      g.addColorStop(0, `rgba(255,255,255,${strength})`);
      g.addColorStop(0.6, `rgba(255,255,255,${strength * 0.5})`);
      g.addColorStop(1, 'rgba(255,255,255,0)');
      c.fillStyle = g;
      c.fillRect(px + ox - r, py + oy - r, r * 2, r * 2);
    }
    const x0 = Math.max(0, Math.floor(px - pr * 1.4)), y0 = Math.max(0, Math.floor(py - pr * 1.4));
    const x1 = Math.min(this.size, Math.ceil(px + pr * 1.4)), y1 = Math.min(this.size, Math.ceil(py + pr * 1.4));
    if (!this.dirty) this.dirty = { x0, y0, x1, y1 };
    else {
      const d = this.dirty;
      d.x0 = Math.min(d.x0, x0); d.y0 = Math.min(d.y0, y0); d.x1 = Math.max(d.x1, x1); d.y1 = Math.max(d.y1, y1);
    }
    if (heat > 0) {
      const hk = this.heatSize / this.extent;
      const hx = (x + this.half) * hk, hy = (z + this.half) * hk, hr = Math.max(1.2, radius * hk * 0.8);
      const hc = this.heatCtx;
      const g = hc.createRadialGradient(hx, hy, 0, hx, hy, hr);
      g.addColorStop(0, `rgba(255,255,255,${heat})`);
      g.addColorStop(1, 'rgba(255,255,255,0)');
      hc.fillStyle = g;
      hc.fillRect(hx - hr, hy - hr, hr * 2, hr * 2);
      this.heatDirty = true;
    }
  }

  update(dt, renderer) {
    if (!this.uploaded) { this.texture.needsUpdate = true; this.uploaded = true; this.dirty = null; return; }
    this.timer += dt;
    this.fadeTimer += dt;
    // le braci si spengono lentamente
    if (this.fadeTimer > 0.5) {
      this.fadeTimer = 0;
      this.heatCtx.fillStyle = 'rgba(0,0,0,0.06)';
      this.heatCtx.fillRect(0, 0, this.heatSize, this.heatSize);
      this.heatTexture.needsUpdate = true;
    } else if (this.heatDirty && this.timer > 0.15) {
      this.heatTexture.needsUpdate = true;
      this.heatDirty = false;
    }
    if (!this.dirty || this.timer < 0.15) return;
    this.timer = 0;
    const d = this.dirty;
    this.dirty = null;
    const w = d.x1 - d.x0, h = d.y1 - d.y0;
    if (w <= 0 || h <= 0) return;
    if (w * h > 600 * 600) { this.texture.needsUpdate = true; return; }
    // carica solo la zona cambiata
    this.patch.width = w; this.patch.height = h;
    this.patch.getContext('2d').drawImage(this.canvas, d.x0, d.y0, w, h, 0, 0, w, h);
    this.patchTex.dispose();
    this.patchTex.image = this.patch;
    this.patchTex.needsUpdate = true;
    renderer.copyTextureToTexture(this._pos.set(d.x0, d.y0), this.patchTex, this.texture);
  }
}
