# Il Volo del Drago — porting Godot

Versione del gioco per **Godot 4.7** (GDScript, renderer Forward+), affiancata a quella Three.js in `src/`.

## Avvio

Apri la cartella `godot/` con l'editor di Godot e premi F5, oppure da riga di comando:

```bash
Godot_v4.7.2-stable_win64.exe --path godot
```

Opzioni di verifica (dopo `--`): `--start` salta la schermata iniziale, `--burn` incendia il villaggio
più vicino, `--land` atterra lì accanto, `--peak` porta davanti alla vetta più alta, `--breathe` tiene premuto il fuoco,
`--novsync` toglie il limite di fps,
`--screenshot=<file.png> --shot-time=<secondi>` salva un'immagine e chiude.

## Dati del terreno

Altezze e rumore del terreno sono calcolati dal codice JavaScript originale ed esportati in
`data/terrain.bin`, così le isole sono identiche alle due versioni. Se cambi `src/world.js` rigenerali:

```bash
node godot/tools/export_world.mjs
```

Villaggi, edifici e alberi sono generati in GDScript con lo stesso generatore casuale (`mulberry32`, seme 2024).

## Build

Servono i modelli di esportazione di Godot 4.7.2 (editor: *Editor → Gestisci modelli di esportazione*).
I preset in `export_presets.cfg` includono già `data/*`. Dalla radice del repository:

```bash
GODOT="E:/Apps/win11/Godot/Godot_v4.7.2-stable_win64_console.exe" npm run dist:godot
```

crea `dist/godot/IlVoloDelDrago-godot.exe` con accanto `IlVoloDelDrago-godot.pck` (i dati del gioco: tienili nella
stessa cartella); `npm run dist:godot -- linux` crea la versione Linux x64. Il pacchetto non è incorporato nell'exe
perché su Windows l'antivirus blocca il file appena creato e l'incorporazione fallisce.

## Struttura

| File | Contenuto |
| --- | --- |
| `scripts/main.gd` | ciclo di gioco, ambiente, camera in terza persona |
| `scripts/world.gd` | terreno, villaggi, castello, alberi, incendi |
| `scripts/dragon.gd` | modello procedurale del drago, volo, atterraggio e camminata |
| `scripts/fx.gd`, `scripts/particles.gd` | particelle, soffio, palle di fuoco, tempesta, esplosioni, luci |
| `scripts/water.gd` | mare che segue la camera |
| `scripts/game_input.gd` | tastiera, mouse, joystick e combinazioni |
| `scripts/hud.gd` | HUD, minimappa, aiuto, schermata iniziale |
| `shaders/` | terreno, edifici in fiamme, mare, pelle e membrana del drago, particelle |

## Non ancora portato

- draghi guardiani nemici, vita del giocatore e abbattimento
- nuvole, audio, bagliore del sole sullo schermo
- bruciature sul terreno e detriti delle esplosioni
- pipeline di rilascio in CI
