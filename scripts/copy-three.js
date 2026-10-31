// Copia Three.js in vendor/three: electron-builder scarta le cartelle "examples" dentro node_modules
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const src = path.join(root, 'node_modules', 'three');
const dst = path.join(root, 'vendor', 'three');

fs.rmSync(dst, { recursive: true, force: true });
fs.mkdirSync(dst, { recursive: true });
fs.copyFileSync(path.join(src, 'build', 'three.module.js'), path.join(dst, 'three.module.js'));
fs.cpSync(path.join(src, 'examples', 'jsm'), path.join(dst, 'addons'), { recursive: true });
console.log('Three.js copiato in vendor/three');
