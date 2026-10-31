// Scarica le texture CC0 da Poly Haven (https://polyhaven.com, licenza CC0) in godot/textures.
// Uso (dalla radice del repository): node godot/tools/fetch_textures.mjs
// Per ogni materiale: colore (diff) e normali in convenzione OpenGL (nor_gl), 1K JPG, verificati con l'MD5.
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// nome locale -> asset di Poly Haven
const TEXTURES = {
  grass: 'leafy_grass',
  dirt: 'forest_ground_04',
  rock: 'rock_face_03',
  sand: 'coast_sand_01',
  snow: 'snow_02',
  cobble: 'cobblestone_floor_01',
  plaster: 'white_stucco_02',
  roof_tiles: 'ceramic_roof_01',
  roof_slate: 'roof_slates_02',
  stone_wall: 'castle_wall_varriation',
  timber: 'rough_wood',
  shutter: 'wood_shutter',
};
const MAPS = { diff: 'Diffuse', nor: 'nor_gl' };

const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'textures');
mkdirSync(dir, { recursive: true });
const credits = [];
for (const [name, asset] of Object.entries(TEXTURES)) {
  const files = await (await fetch(`https://api.polyhaven.com/files/${asset}`)).json();
  for (const [suffix, key] of Object.entries(MAPS)) {
    const f = files[key]['1k'].jpg;
    const out = join(dir, `${name}_${suffix}.jpg`);
    const md5 = (b) => createHash('md5').update(b).digest('hex');
    if (existsSync(out) && md5(readFileSync(out)) === f.md5) continue;
    const buf = Buffer.from(await (await fetch(f.url)).arrayBuffer());
    if (md5(buf) !== f.md5) throw new Error(`MD5 errato per ${f.url}`);
    writeFileSync(out, buf);
    console.log(`${name}_${suffix}.jpg  <- ${asset} (${(buf.length / 1048576).toFixed(1)} MB)`);
  }
  credits.push(`- ${name}: https://polyhaven.com/a/${asset}`);
}
writeFileSync(join(dir, 'CREDITS.md'),
  `# Texture\n\nDa [Poly Haven](https://polyhaven.com), licenza [CC0](https://creativecommons.org/publicdomain/zero/1.0/).\n` +
  `Scaricate con \`node godot/tools/fetch_textures.mjs\`.\n\n${credits.join('\n')}\n`);
