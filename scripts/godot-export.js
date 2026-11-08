// Esporta il porting Godot in dist/godot (servono i modelli di esportazione di Godot 4.7.2).
// Uso: npm run dist:godot [-- linux]   ·   eseguibile di Godot nella variabile GODOT (predefinito: godot)
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const root = path.join(__dirname, '..');
const linux = process.argv[2] === 'linux';
const preset = linux ? 'Linux' : 'Windows Desktop';
const out = path.join(root, 'dist', 'godot', linux ? 'IlVoloDelDrago-godot.x86_64' : 'IlVoloDelDrago-godot.exe');
const godot = process.env.GODOT || 'godot';

fs.mkdirSync(path.dirname(out), { recursive: true });
const r = spawnSync(godot, ['--headless', '--path', path.join(root, 'godot'), '--export-release', preset, out], { stdio: 'inherit' });
if (r.error) {
  console.error(`Impossibile avviare Godot (${godot}): imposta la variabile GODOT con il percorso dell'eseguibile`);
  process.exit(1);
}
if (r.status !== 0 || !fs.existsSync(out)) process.exit(r.status || 1);
console.log(`Build Godot: ${out}`);
