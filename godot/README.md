# Il Volo del Drago — porting Godot

Versione del gioco per **Godot 4.7** (GDScript, renderer Forward+), affiancata a quella Three.js in `src/`.

## Avvio

Apri la cartella `godot/` con l'editor di Godot e premi F5, oppure da riga di comando:

```bash
Godot_v4.7.2-stable_win64.exe --path godot
```

Opzioni di verifica (dopo `--`): `--start` salta la schermata iniziale, `--burn` incendia il villaggio
più vicino, `--land` atterra lì accanto, `--breathe` tiene premuto il fuoco,
`--screenshot=<file.png> --shot-time=<secondi>` salva un'immagine e chiude.

## Dati del terreno

Altezze e rumore del terreno sono calcolati dal codice JavaScript originale ed esportati in
`data/terrain.bin`, così le isole sono identiche alle due versioni. Se cambi `src/world.js` rigenerali:

```bash
node godot/tools/export_world.mjs
```

Villaggi, edifici e alberi sono generati in GDScript con lo stesso generatore casuale (`mulberry32`, seme 2024).
Per esportare il gioco aggiungi `data/*` ai file non risorsa nel preset di esportazione.

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
- preset di esportazione e pipeline di rilascio
