// Cielo fisico (Preetham), sole, riflessi ambientali, nebbia atmosferica
import * as THREE from 'three';
import { Sky } from 'three/addons/objects/Sky.js';

export class SkySystem {
  constructor(scene, renderer) {
    this.sky = new Sky();
    this.sky.scale.setScalar(45000);
    // la cupola segue la camera: la direzione va calcolata dalla posizione reale della camera
    this.sky.material.fragmentShader = this.sky.material.fragmentShader
      .replace(/const\s+vec3\s+cameraPos\s*=\s*vec3\([^)]*\);/, '#define cameraPos cameraPosition');
    const u = this.sky.material.uniforms;
    u.turbidity.value = 3.2;
    u.rayleigh.value = 1.1;
    u.mieCoefficient.value = 0.004;
    u.mieDirectionalG.value = 0.86;

    const elevation = 17, azimuth = 210;
    this.sunDir = new THREE.Vector3().setFromSphericalCoords(1, THREE.MathUtils.degToRad(90 - elevation), THREE.MathUtils.degToRad(azimuth));
    u.sunPosition.value.copy(this.sunDir);

    // riflessi ambientali: il cielo renderizzato in una cubemap
    const skyScene = new THREE.Scene();
    skyScene.add(this.sky);
    this.cubeRT = new THREE.WebGLCubeRenderTarget(256, { type: THREE.HalfFloatType, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter });
    const cubeCam = new THREE.CubeCamera(1, 100000, this.cubeRT);
    cubeCam.update(renderer, skyScene);
    const pmrem = new THREE.PMREMGenerator(renderer);
    this.envMap = pmrem.fromScene(skyScene, 0, 1, 100000).texture;
    pmrem.dispose();
    scene.add(this.sky);
    scene.environment = this.envMap;

    // luce del sole con ombre che seguono il drago
    this.sunColor = new THREE.Color(1.0, 0.93, 0.82);
    this.sun = new THREE.DirectionalLight(this.sunColor, 3.2);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(2048, 2048);
    const sc = this.sun.shadow.camera;
    sc.left = -220; sc.right = 220; sc.top = 220; sc.bottom = -220; sc.near = 10; sc.far = 1600;
    this.sun.shadow.bias = -0.0004;
    this.sun.shadow.normalBias = 0.6;
    scene.add(this.sun);
    scene.add(this.sun.target);
    this.hemi = new THREE.HemisphereLight(0xb8d4ff, 0x4a4030, 0.9);
    scene.add(this.hemi);

    this.fogColor = new THREE.Color(0.62, 0.72, 0.84);
    this.fogDensity = 0.00016;
    scene.fog = new THREE.FogExp2(this.fogColor, this.fogDensity);
  }

  update(camera, focus) {
    this.sun.position.copy(focus).addScaledVector(this.sunDir, 700);
    this.sun.target.position.copy(focus);
    this.sky.position.copy(camera.position);
  }
}
