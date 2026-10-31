// Audio procedurale con Web Audio: vento, battito d'ali, fiamme, mare, esplosioni e ruggito
export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.muted = false;
  }

  start() {
    if (this.ctx) { this.ctx.resume(); return; }
    const ctx = this.ctx = new (window.AudioContext || window.webkitAudioContext)();
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -14; comp.ratio.value = 4;
    comp.connect(ctx.destination);
    this.master = ctx.createGain();
    this.master.gain.value = this.muted ? 0 : 0.85;
    this.master.connect(comp);

    const white = ctx.createBuffer(1, ctx.sampleRate * 3, ctx.sampleRate);
    const wd = white.getChannelData(0);
    for (let i = 0; i < wd.length; i++) wd[i] = Math.random() * 2 - 1;
    const brown = ctx.createBuffer(1, ctx.sampleRate * 4, ctx.sampleRate);
    const bd = brown.getChannelData(0);
    let last = 0;
    for (let i = 0; i < bd.length; i++) { last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02; bd[i] = last * 3.5; }
    this.white = white; this.brown = brown;

    this.wind = this.loop(brown, 'lowpass', 400, 0.7);
    this.wind2 = this.loop(white, 'bandpass', 1200, 0.6);
    this.fire = this.loop(white, 'bandpass', 900, 0.7);
    this.fireLow = this.loop(brown, 'lowpass', 350, 0.7);
    this.sea = this.loop(brown, 'lowpass', 700, 0.5);
    this.blaze = this.loop(white, 'bandpass', 2200, 0.8);
  }

  loop(buffer, type, freq, Q) {
    const ctx = this.ctx;
    const src = ctx.createBufferSource();
    src.buffer = buffer; src.loop = true;
    src.playbackRate.value = 0.9 + Math.random() * 0.2;
    const filter = ctx.createBiquadFilter();
    filter.type = type; filter.frequency.value = freq; filter.Q.value = Q;
    const gain = ctx.createGain();
    gain.gain.value = 0;
    src.connect(filter).connect(gain).connect(this.master);
    src.start(0, Math.random() * buffer.duration);
    return { src, filter, gain };
  }

  set(node, value, tc = 0.1) {
    node.setTargetAtTime(value, this.ctx.currentTime, tc);
  }

  update(s) {
    if (!this.ctx) return;
    const sp = Math.min(1, s.speed / 170);
    this.set(this.wind.gain.gain, 0.12 + sp * 0.55 + s.inCloud * 0.15);
    this.set(this.wind.filter.frequency, 250 + sp * 900);
    this.set(this.wind2.gain.gain, sp * sp * 0.12);
    this.set(this.wind2.filter.frequency, 800 + sp * 1800);
    this.set(this.fire.gain.gain, s.breathing ? 0.55 : 0, s.breathing ? 0.05 : 0.15);
    this.set(this.fireLow.gain.gain, s.breathing ? 0.7 : 0, s.breathing ? 0.05 : 0.2);
    this.set(this.fire.filter.frequency, 700 + Math.random() * 500, 0.03);
    this.set(this.sea.gain.gain, 0.03 + s.water * 0.45);
    this.set(this.blaze.gain.gain, Math.min(0.45, s.burn) * (0.5 + Math.random() * 0.5), 0.04);
  }

  env(gainNode, peak, attack, decay) {
    const t = this.ctx.currentTime;
    gainNode.gain.setValueAtTime(0.0001, t);
    gainNode.gain.exponentialRampToValueAtTime(Math.max(peak, 0.0002), t + attack);
    gainNode.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay);
  }

  burst(buffer, type, f0, f1, peak, attack, decay, Q = 0.7) {
    const ctx = this.ctx;
    const src = ctx.createBufferSource();
    src.buffer = buffer;
    const filter = ctx.createBiquadFilter();
    filter.type = type; filter.Q.value = Q;
    const t = ctx.currentTime;
    filter.frequency.setValueAtTime(f0, t);
    filter.frequency.exponentialRampToValueAtTime(f1, t + attack + decay);
    const g = ctx.createGain();
    src.connect(filter).connect(g).connect(this.master);
    this.env(g, peak, attack, decay);
    src.start(0, Math.random() * (buffer.duration - attack - decay - 0.1));
    src.stop(t + attack + decay + 0.05);
  }

  flap(power) {
    if (!this.ctx) return;
    this.burst(this.brown, 'lowpass', 500, 120, 0.5 * power, 0.06, 0.35);
    this.burst(this.white, 'bandpass', 300, 120, 0.12 * power, 0.05, 0.25, 0.5);
  }

  whoosh(amount = 1) {
    if (!this.ctx) return;
    this.burst(this.white, 'bandpass', 300, 2200, 0.35 * amount, 0.15, 0.45, 1.2);
  }

  explosion(dist) {
    if (!this.ctx) return;
    const v = 1 / (1 + dist / 250);
    if (v < 0.03) return;
    this.burst(this.brown, 'lowpass', 1400, 80, 1.6 * v, 0.01, 1.8);
    this.burst(this.white, 'lowpass', 4000, 300, 0.4 * v, 0.005, 0.6);
    const ctx = this.ctx, t = ctx.currentTime;
    const o = ctx.createOscillator();
    o.frequency.setValueAtTime(70, t);
    o.frequency.exponentialRampToValueAtTime(28, t + 0.9);
    const g = ctx.createGain();
    o.connect(g).connect(this.master);
    this.env(g, 0.8 * v, 0.01, 0.9);
    o.start(t); o.stop(t + 1);
  }

  roar(vol = 1) {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass'; filter.Q.value = 3;
    filter.frequency.setValueAtTime(400, t);
    filter.frequency.linearRampToValueAtTime(1300, t + 0.4);
    filter.frequency.linearRampToValueAtTime(300, t + 2.0);
    const g = ctx.createGain();
    filter.connect(g).connect(this.master);
    this.env(g, 0.55 * vol, 0.15, 1.9);
    const lfo = ctx.createOscillator();
    lfo.frequency.value = 23;
    const lfoGain = ctx.createGain();
    lfoGain.gain.value = 9;
    lfo.connect(lfoGain);
    for (const f of [88, 91, 133, 176]) {
      const o = ctx.createOscillator();
      o.type = 'sawtooth';
      o.frequency.setValueAtTime(f * 1.2, t);
      o.frequency.linearRampToValueAtTime(f, t + 0.5);
      o.frequency.linearRampToValueAtTime(f * 0.75, t + 2.1);
      lfoGain.connect(o.frequency);
      o.connect(filter);
      o.start(t); o.stop(t + 2.2);
    }
    lfo.start(t); lfo.stop(t + 2.2);
    this.burst(this.white, 'bandpass', 900, 400, 0.25 * vol, 0.1, 1.8, 2);
  }

  crackle() {
    if (!this.ctx) return;
    this.burst(this.white, 'highpass', 2500, 1500, 0.15, 0.002, 0.08);
  }

  setMuted(m) {
    this.muted = m;
    if (this.master) this.set(this.master.gain, m ? 0 : 0.85, 0.05);
  }
}
