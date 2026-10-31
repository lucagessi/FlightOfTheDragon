// Input da tastiera, mouse e joystick (Gamepad API) con riconoscimento delle combo
const DOUBLE_TAP = 0.3;
const SEQ_WINDOW = 0.9;

export class Input {
  constructor(dom) {
    this.keys = new Set();
    this.actions = [];
    this.history = [];
    this.time = 0;
    this.invertY = false;
    this.mouseFire = false;
    this.look = { x: 0, y: 0 };
    this.zoom = 0;
    this.dragging = false;
    this.padPrev = [];
    this.padAxesPrev = { left: false, right: false, up: false, down: false };
    this.padConnected = false;
    this.anyPress = false;

    const logical = (code) => ({
      Space: 'fire',
      KeyA: 'left', ArrowLeft: 'left',
      KeyD: 'right', ArrowRight: 'right',
      KeyW: 'up', ArrowUp: 'up',
      KeyS: 'down', ArrowDown: 'down',
    })[code];

    addEventListener('keydown', (e) => {
      if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Tab'].includes(e.code)) e.preventDefault();
      this.anyPress = true;
      if (e.repeat) return;
      this.keys.add(e.code);
      const l = logical(e.code);
      if (l) this.press(this.adjust(l));
      if (e.code === 'KeyH' || e.code === 'F1') this.actions.push('help');
      if (e.code === 'KeyP' || e.code === 'Escape') this.actions.push('pause');
      if (e.code === 'KeyM') this.actions.push('mute');
      if (e.code === 'KeyI') { this.invertY = !this.invertY; this.actions.push('invert'); }
      if (e.code === 'KeyC') this.actions.push('camera');
    });
    addEventListener('keyup', (e) => this.keys.delete(e.code));
    addEventListener('blur', () => this.keys.clear());

    dom.addEventListener('contextmenu', (e) => e.preventDefault());
    dom.addEventListener('mousedown', (e) => {
      this.anyPress = true;
      if (e.button === 0) { this.mouseFire = true; this.press('fire'); }
      if (e.button === 2) this.dragging = true;
    });
    addEventListener('mouseup', (e) => {
      if (e.button === 0) this.mouseFire = false;
      if (e.button === 2) this.dragging = false;
    });
    addEventListener('mousemove', (e) => {
      if (!this.dragging) return;
      this.look.x = Math.max(-1, Math.min(1, this.look.x - e.movementX * 0.004));
      this.look.y = Math.max(-0.6, Math.min(0.8, this.look.y + e.movementY * 0.003));
    });
    dom.addEventListener('wheel', (e) => { this.zoom += Math.sign(e.deltaY); }, { passive: true });
    addEventListener('gamepadconnected', () => { this.padConnected = true; this.actions.push('pad'); });
    addEventListener('gamepaddisconnected', () => { this.padConnected = false; });
  }

  adjust(l) {
    if (this.invertY && (l === 'up' || l === 'down')) return l === 'up' ? 'down' : 'up';
    return l;
  }

  // Registra una pressione e controlla le combinazioni speciali
  press(l) {
    const t = this.time;
    const h = this.history;
    const last = h.length ? h[h.length - 1] : null;
    if (l === 'fire') {
      // ↓ ↑ + Fuoco  =>  Tempesta di fuoco
      const n = h.length;
      if (n >= 2 && h[n - 1].l === 'up' && h[n - 2].l === 'down' && t - h[n - 2].t < SEQ_WINDOW) {
        this.actions.push('firestorm');
        this.history = [];
        return;
      }
      if (last && last.l === 'fire' && t - last.t < DOUBLE_TAP) { this.actions.push('fireball'); this.history = []; return; }
    }
    if (l === 'left' && last && last.l === 'left' && t - last.t < DOUBLE_TAP) { this.actions.push('rollLeft'); this.history = []; return; }
    if (l === 'right' && last && last.l === 'right' && t - last.t < DOUBLE_TAP) { this.actions.push('rollRight'); this.history = []; return; }
    if (l === 'up' && last && last.l === 'up' && t - last.t < DOUBLE_TAP) { this.actions.push('loop'); this.history = []; return; }
    h.push({ l, t });
    if (h.length > 6) h.shift();
  }

  pollPad() {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    let pad = null;
    for (const p of pads) if (p && p.connected) { pad = p; break; }
    if (!pad) return null;
    const btn = (i) => !!(pad.buttons[i] && (pad.buttons[i].pressed || pad.buttons[i].value > 0.5));
    const val = (i) => (pad.buttons[i] ? pad.buttons[i].value : 0);
    const dz = (v) => (Math.abs(v) < 0.15 ? 0 : (v - Math.sign(v) * 0.15) / 0.85);
    const state = {
      lx: dz(pad.axes[0] || 0), ly: dz(pad.axes[1] || 0),
      rx: dz(pad.axes[2] || 0), ry: dz(pad.axes[3] || 0),
      a: btn(0), b: btn(1), x: btn(2), y: btn(3), lb: btn(4), rb: btn(5),
      lt: val(6), rt: val(7), back: btn(8), start: btn(9),
      dl: btn(14), dr: btn(15), du: btn(12), dd: btn(13),
    };
    const prev = this.padPrev;
    const edge = (k) => state[k] && !prev[k];
    if (Object.keys(state).some(k => typeof state[k] === 'boolean' && edge(k)) || state.rt > 0.5) this.anyPress = true;
    // grilletto destro = fuoco (doppio tocco = palla di fuoco)
    const rtDown = state.rt > 0.5, rtPrev = prev.rt > 0.5;
    if (rtDown && !rtPrev) {
      if (state.lt > 0.5) this.actions.push('firestorm');
      else this.press('fire');
    }
    if (edge('x')) this.actions.push('fireball');
    if (edge('y')) this.actions.push('loop');
    if (edge('lb')) this.actions.push('rollLeft');
    if (edge('rb')) this.actions.push('rollRight');
    if (edge('start')) this.actions.push('pause');
    if (edge('back')) this.actions.push('help');
    // levetta: anche i "colpetti" contano per le combo (doppio colpetto = piroetta)
    const ax = this.padAxesPrev;
    const dirs = { left: state.lx < -0.75 || state.dl, right: state.lx > 0.75 || state.dr, up: state.ly < -0.75 || state.du, down: state.ly > 0.75 || state.dd };
    for (const k of ['left', 'right', 'up', 'down']) {
      if (dirs[k] && !ax[k]) this.press(this.adjust(k));
      ax[k] = dirs[k];
    }
    this.padPrev = state;
    return state;
  }

  update(dt) {
    this.time += dt;
    const k = this.keys;
    const has = (...c) => c.some(x => k.has(x));
    let steer = (has('KeyD', 'ArrowRight') ? 1 : 0) - (has('KeyA', 'ArrowLeft') ? 1 : 0);
    let climb = (has('KeyW', 'ArrowUp') ? 1 : 0) - (has('KeyS', 'ArrowDown') ? 1 : 0);
    if (this.invertY) climb = -climb;
    // (niente Ctrl: Ctrl+W chiuderebbe la scheda del browser)
    let throttle = (has('ShiftLeft', 'ShiftRight', 'KeyE') ? 1 : 0) - (has('KeyQ', 'KeyZ') ? 1 : 0);
    let fire = has('Space') || this.mouseFire;
    let lookX = 0, lookY = 0;

    const pad = this.pollPad();
    if (pad) {
      if (Math.abs(pad.lx) > 0) steer = pad.lx;
      if (Math.abs(pad.ly) > 0) climb = this.invertY ? pad.ly : -pad.ly;
      if (pad.dl) steer = -1; if (pad.dr) steer = 1;
      if (pad.du) climb = this.invertY ? -1 : 1; if (pad.dd) climb = this.invertY ? 1 : -1;
      if (pad.a) throttle = 1;
      if (pad.b) throttle = -1;
      if (pad.rt > 0.3) fire = true;
      lookX = -pad.rx; lookY = pad.ry;
    }
    if (!this.dragging) {
      this.look.x *= Math.exp(-dt * 1.5);
      this.look.y *= Math.exp(-dt * 1.5);
    }
    const actions = this.actions;
    this.actions = [];
    return {
      steer: Math.max(-1, Math.min(1, steer)),
      climb: Math.max(-1, Math.min(1, climb)),
      throttle, fire,
      lookX: this.look.x + lookX, lookY: this.look.y + lookY * 0.6,
      zoom: this.zoom,
      actions,
    };
  }
}
