// Esporta i dati del terreno della versione Three.js per il porting Godot.
// Uso (dalla radice del repository): node godot/tools/export_world.mjs
// Scrive godot/data/terrain.bin: griglia N x N di float32 [altezza, rumore fine, foresta].
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { heightAt, TERRAIN_SIZE, TERRAIN_SEGS } from '../../src/world.js';
import { makeNoise2D, fbm } from '../../src/noise.js';

const nD = makeNoise2D(99);
const N = TERRAIN_SEGS + 1, HALF = TERRAIN_SIZE / 2, STEP = TERRAIN_SIZE / TERRAIN_SEGS;
const out = new Float32Array(N * N * 3);
for (let j = 0; j < N; j++) {
  for (let i = 0; i < N; i++) {
    const x = -HALF + i * STEP, z = -HALF + j * STEP, k = (j * N + i) * 3;
    out[k] = heightAt(x, z);
    out[k + 1] = fbm(nD, x * 0.004, z * 0.004, 3) * 0.5 + 0.5;
    out[k + 2] = fbm(nD, x * 0.002, z * 0.002, 3);
  }
}
const file = join(dirname(fileURLToPath(import.meta.url)), '..', 'data', 'terrain.bin');
mkdirSync(dirname(file), { recursive: true });
writeFileSync(file, Buffer.from(out.buffer));
console.log(`${file}: ${N}x${N}, ${out.byteLength} byte`);
