/* Squish Sort ASMR squish sounds, v1 (16 Nov 2026). Game design thread.
   Nothing is recorded: every sound is made live from how fast the squishy is being deformed, so the
   sound follows the finger. Layers: foam crackle grains + air, jelly squelch + hum, gel bubbles, mochi tack.
   Drive it once per frame with update(dt, body.metric, materialKey, pan). Browser only (Web Audio). */
(function (root) {
  'use strict';
  const clamp = (x, a, b) => x < a ? a : x > b ? b : x, rnd = (a, b) => a + Math.random() * (b - a);

  function SquishAudio() { this.ctx = null; this.enabled = true; this.acc = {}; this.grains = 0; this.prevStretch = 0; this.level = 0; }

  SquishAudio.prototype.unlock = function () {
    try {
      if (!this.ctx) {
        const AC = root.AudioContext || root.webkitAudioContext; if (!AC) return false;
        this.ctx = new AC(); this._build();
        // iPhone: play through the silent switch where the browser allows it
        try { if (navigator.audioSession) navigator.audioSession.type = 'playback'; } catch (e) { }
        try {
          const a = this.keep = new Audio('data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=');
          a.loop = true; a.setAttribute('playsinline', ''); const p = a.play(); if (p && p.catch) p.catch(function () { });
        } catch (e) { }
      }
      if (this.ctx.state !== 'running') this.ctx.resume();
      return true;
    } catch (e) { return false; }
  };

  SquishAudio.prototype._build = function () {
    const c = this.ctx, sr = c.sampleRate, len = sr * 2;
    const white = c.createBuffer(1, len, sr), pink = c.createBuffer(1, len, sr), w = white.getChannelData(0), pk = pink.getChannelData(0);
    let b0 = 0, b1 = 0, b2 = 0;
    for (let i = 0; i < len; i++) { const x = Math.random() * 2 - 1; w[i] = x; b0 = 0.99765 * b0 + x * 0.0990460; b1 = 0.96300 * b1 + x * 0.2965164; b2 = 0.57000 * b2 + x * 1.0526913; pk[i] = (b0 + b1 + b2 + x * 0.1848) * 0.22; }
    this.white = white; this.pink = pink;
    const comp = c.createDynamicsCompressor(); comp.threshold.value = -16; comp.knee.value = 12; comp.ratio.value = 5; comp.attack.value = 0.004; comp.release.value = 0.16;
    const master = this.master = c.createGain(); master.gain.value = 1.6; master.connect(comp); comp.connect(c.destination);
    const an = this.analyser = c.createAnalyser(); an.fftSize = 1024; comp.connect(an); this.buf = new Float32Array(an.fftSize);
    const loop = (buf) => { const s = c.createBufferSource(); s.buffer = buf; s.loop = true; s.start(0, Math.random()); return s; };
    const pan = () => (c.createStereoPanner ? c.createStereoPanner() : c.createGain());
    // air: breathy hiss as foam is pressed (out) and as it rises (in)
    const air = this.air = { f: c.createBiquadFilter(), g: c.createGain(), p: pan() }; air.f.type = 'bandpass'; air.f.Q.value = 0.9; air.g.gain.value = 0;
    loop(pink).connect(air.f); air.f.connect(air.g); air.g.connect(air.p); air.p.connect(master);
    // squelch: wet, resonant, sweeps with how far the jelly is squashed
    const sq = this.squelch = { lp: c.createBiquadFilter(), f: c.createBiquadFilter(), g: c.createGain(), p: pan() }; sq.lp.type = 'lowpass'; sq.lp.frequency.value = 2600; sq.f.type = 'bandpass'; sq.f.Q.value = 5; sq.g.gain.value = 0;
    loop(white).connect(sq.lp); sq.lp.connect(sq.f); sq.f.connect(sq.g); sq.g.connect(sq.p); sq.p.connect(master);
    // hum: the low wobble of a jelly body
    const hum = this.hum = { o: c.createOscillator(), f: c.createBiquadFilter(), g: c.createGain() }; hum.o.type = 'triangle'; hum.o.frequency.value = 92; hum.f.type = 'lowpass'; hum.f.frequency.value = 260; hum.g.gain.value = 0;
    hum.o.connect(hum.f); hum.f.connect(hum.g); hum.g.connect(master); hum.o.start();
    // creak: stick-slip of stretched mochi
    const cr = this.creak = { f: c.createBiquadFilter(), am: c.createGain(), g: c.createGain(), l: c.createOscillator(), lg: c.createGain() }; cr.f.type = 'bandpass'; cr.f.frequency.value = 620; cr.f.Q.value = 7; cr.am.gain.value = 0.5; cr.g.gain.value = 0; cr.l.type = 'sawtooth'; cr.l.frequency.value = 31; cr.lg.gain.value = 0.5;
    loop(white).connect(cr.f); cr.f.connect(cr.am); cr.am.connect(cr.g); cr.g.connect(master); cr.l.connect(cr.lg); cr.lg.connect(cr.am.gain); cr.l.start();
  };

  SquishAudio.prototype._grain = function (buf, freq, q, dur, vol, pan, attack) {
    const c = this.ctx; if (this.grains > 40 || vol <= 0.002) return; this.grains++;
    const t = c.currentTime + 0.004, s = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain(); s.buffer = buf;
    f.type = 'bandpass'; f.frequency.value = freq; f.Q.value = q;
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol, t + (attack || 0.001)); g.gain.exponentialRampToValueAtTime(0.0005, t + dur);
    s.connect(f); f.connect(g);
    if (c.createStereoPanner) { const p = c.createStereoPanner(); p.pan.value = clamp(pan + rnd(-0.25, 0.25), -1, 1); g.connect(p); p.connect(this.master); } else g.connect(this.master);
    s.start(t, Math.random() * 1.8, dur + 0.02); const me = this; s.onended = function () { me.grains--; };
  };
  SquishAudio.prototype._tone = function (f0, f1, dur, vol, pan, type) {
    const c = this.ctx; if (this.grains > 40 || vol <= 0.002) return; this.grains++;
    const t = c.currentTime + 0.004, o = c.createOscillator(), g = c.createGain(); o.type = type || 'sine';
    o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(f1, t + dur);
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol, t + 0.004); g.gain.exponentialRampToValueAtTime(0.0005, t + dur);
    o.connect(g);
    if (c.createStereoPanner) { const p = c.createStereoPanner(); p.pan.value = clamp(pan || 0, -1, 1); g.connect(p); p.connect(this.master); } else g.connect(this.master);
    o.start(t); o.stop(t + dur + 0.03); const me = this; o.onended = function () { me.grains--; };
  };
  SquishAudio.prototype.thud = function (vol, pan) { if (!this.ready()) return; this._tone(105, 46, 0.16, vol, pan); this._grain(this.pink, 240, 0.7, 0.09, vol * 0.8, pan || 0, 0.003); };
  SquishAudio.prototype.pop = function (vol, pan) { if (!this.ready()) return; this._tone(330, 150, 0.07, vol, pan); this._grain(this.white, 1800, 1.5, 0.02, vol * 0.5, pan || 0); };
  SquishAudio.prototype.bubble = function (vol, pan) { const f = rnd(380, 1300); this._tone(f, f * rnd(1.5, 2.1), rnd(0.035, 0.07), vol, pan); };
  SquishAudio.prototype.ready = function () { return !!(this.ctx && this.enabled && this.ctx.state === 'running'); };

  SquishAudio.prototype._emit = function (key, perSecond, dt, fn) {
    let a = (this.acc[key] || 0) + perSecond * dt; let n = 0;
    while (a >= 1 && n < 6) { fn(); a -= 1; n++; }
    this.acc[key] = a > 6 ? 0 : a;
  };

  /* m: body.metric (D, rate, stretch, speed, impact). mat: 'foam' | 'jelly' | 'gel' | 'mochi'. pan: -1..1 */
  SquishAudio.prototype.update = function (dt, m, mat, pan) {
    if (!this.ctx) return; const c = this.ctx, t = c.currentTime, me = this, on = this.ready();
    const rate = m.rate, a = Math.abs(rate), compress = Math.max(0, rate), rise = Math.max(0, -rate), D = clamp(m.D * 3, 0, 1);
    const sRate = (m.stretch - this.prevStretch) / Math.max(dt, 0.004); this.prevStretch = m.stretch;
    let air = 0, airF = 1500, sq = 0, sqF = 500, hum = 0, humF = 92, creak = 0;
    if (on) {
      if (mat === 'foam') {
        // dry foam: fine crackle while pressed, then sparse crackle and a breath in for as long as it is still rising
        const gps = clamp(a * 320, 0, 90) + (rise > 0.004 && m.D > 0.012 && !m.held ? 9 + 40 * D : 0);
        if (gps > 0.5) this._emit('ck', gps, dt, function () { me._grain(me.white, rise > 0 ? rnd(3800, 8200) : rnd(2200, 6000), rnd(3, 9), rnd(0.003, 0.010), rnd(0.16, 0.42) * (rise > 0 ? 0.55 : 1), pan); });
        air = clamp(compress * 0.55, 0, 0.5) + clamp(rise * 0.8, 0, 0.16); airF = rise > compress ? 760 : 1300 + 2200 * D;
      } else if (mat === 'jelly') {
        sq = clamp(a * 0.17, 0, 0.22); sqF = 300 + 2300 * D; hum = clamp(m.speed * 0.08, 0, 0.1); humF = 84 + 70 * D;
        if (compress > 0.05) this._emit('jb', clamp(compress * 16, 0, 12), dt, function () { me.bubble(rnd(0.03, 0.08), pan); });
      } else if (mat === 'gel') {
        if (a > 0.02) this._emit('gb', clamp(a * 60, 0, 44), dt, function () { me.bubble(rnd(0.05, 0.14), pan + rnd(-0.3, 0.3)); });
        sq = clamp(a * 0.2, 0, 0.26); sqF = 220 + 800 * D; hum = clamp(m.speed * 0.05, 0, 0.07); humF = 70 + 30 * D;
      } else if (mat === 'mochi') {
        // sticky: soft tacks as it is pressed, a creak as it stretches, quick tacks as it peels back
        creak = clamp(Math.max(0, sRate) * 1.2, 0, 0.4);
        if (compress > 0.02) this._emit('mp', clamp(compress * 45, 0, 24), dt, function () { me._grain(me.white, rnd(600, 1500), rnd(2, 4), rnd(0.012, 0.022), rnd(0.08, 0.2), pan); });
        if (rise > 0.02) this._emit('mt', clamp(rise * 70, 0, 30), dt, function () { me._grain(me.white, rnd(900, 2300), rnd(2, 5), rnd(0.008, 0.018), rnd(0.12, 0.3), pan); });
        air = clamp(compress * 0.4, 0, 0.35); airF = 900 + 900 * D; sq = clamp(a * 0.10, 0, 0.14); sqF = 380 + 500 * D;
      }
      if (m.impact > 0.5) { this.thud(clamp((m.impact - 0.3) * 0.11, 0.04, 0.34), pan); if (mat === 'gel' || mat === 'jelly') for (let i = 0; i < 3; i++) this.bubble(rnd(0.03, 0.07), pan); }
    }
    m.impact = 0;
    const set = (param, v, tc) => param.setTargetAtTime(v, t, tc || 0.035);
    set(this.air.g.gain, air); set(this.air.f.frequency, airF, 0.06); if (this.air.p.pan) set(this.air.p.pan, pan, 0.05);
    set(this.squelch.g.gain, sq); set(this.squelch.f.frequency, sqF, 0.04); if (this.squelch.p.pan) set(this.squelch.p.pan, pan, 0.05);
    set(this.hum.g.gain, hum, 0.05); set(this.hum.o.frequency, humF, 0.05); set(this.creak.g.gain, creak, 0.04); set(this.creak.f.frequency, 520 + 500 * clamp(m.stretch, 0, 1), 0.05);
    this.analyser.getFloatTimeDomainData(this.buf); let s = 0; for (let i = 0; i < this.buf.length; i++) s += this.buf[i] * this.buf[i];
    this.level = Math.sqrt(s / this.buf.length);
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = { SquishAudio }; else root.SquishAudio = SquishAudio;
})(typeof window !== 'undefined' ? window : this);
