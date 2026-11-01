# Il Volo del Drago — porting Godot

Versione del gioco per **Godot 4.7** (GDScript, renderer Forward+), affiancata a quella Three.js in `src/`.

## Avvio

Apri la cartella `godot/` con l'editor di Godot e premi F5, oppure da riga di comando:

```bash
Godot_v4.7.2-stable_win64.exe --path godot
```

Opzioni di verifica (dopo `--`): `--start` salta la schermata iniziale, `--burn` incendia il villaggio
più vicino, `--land` atterra lì accanto, `--peak` porta davanti alla vetta più alta, `--house` a terra davanti alle case, `--closeup[=<angolo>]` inquadra da vicino una casa, `--guardian` mette di fronte al guardiano più vicino già ostile, `--fortress` davanti alla fortezza già risvegliata (`--fortress=<angolo>` la inquadra tutta da quella direzione, `--fortress=post` da vicino sulle armi del mastio), `--breathe` tiene premuto il fuoco,
`--novsync` toglie il limite di fps,
`--screenshot=<file.png> --shot-time=<secondi>` salva un'immagine e chiude.

## Dati del terreno

Altezze e rumore del terreno sono calcolati dal codice JavaScript originale ed esportati in
`data/terrain.bin`, così le isole sono identiche alle due versioni. Se cambi `src/world.js` rigenerali:

```bash
node godot/tools/export_world.mjs
```

Villaggi, edifici e alberi sono generati in GDScript con lo stesso generatore casuale (`mulberry32`, seme 2024);
i dettagli aggiunti alle case (graticcio, imposte, cornici) usano un generatore separato per edificio.

## La fortezza di Monte Nero

Esiste solo nella versione Godot. Sulla vetta più alta lontana dai villaggi, quattro anelli di mura a gradoni
seguono le curve di livello dalla costa alla cima, con torri, bastioni, caserme e il mastio con la guglia arcana.
Dorme finché non la attacchi (soffio, palle di fuoco o un incendio appiccato alle sue mura), poi suona il corno
e tutte le postazioni a tiro sparano con tiro balistico e anticipo sul bersaglio:

| Postazione | Gittata | Colpo |
| --- | --- | --- |
| cannone | 900 m | palla di ferro che esplode |
| trabucco | 1150 m | macigno infuocato a parabola alta |
| balestra su ruote | 760 m | dardo veloce e preciso |
| arcieri | 420 m | raffiche di frecce incendiarie |
| fuoco greco | 140 m | getto di fiamme dai sifoni sulle mura basse |
| torre arcana | 1100 m | sfere magiche che inseguono il drago |

Ogni postazione si distrugge col fuoco o incendiando la sua torre; quando cadono tutte, cade la fortezza.
Ha un generatore casuale proprio (seme 7331), così il resto del mondo resta identico alla versione Three.js.

## Texture

Terreno, edifici e cortecce usano materiali PBR CC0 di [Poly Haven](https://polyhaven.com) in `textures/`
(elenco in `textures/CREDITS.md`): per ognuno colore (`_diff`), normali (`_nor`), occlusione/rugosità (`_arm`)
e rilievo (`_disp`, usato per il parallasse di tegole e pietra e per fondere i materiali del terreno). All'avvio
vengono raccolti in array di texture, uno strato per materiale. Per riscaricarle, o cambiarle modificando l'elenco nello script:

```bash
node godot/tools/fetch_textures.mjs
```

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
| `scripts/foliage.gd` | modelli procedurali degli alberi e atlante delle foglie |
| `scripts/dragon.gd` | modello procedurale del drago, volo, atterraggio e camminata |
| `scripts/audio.gd` | audio procedurale: vento, ali, fiamme, mare, incendi, esplosioni, ruggiti |
| `scripts/fortress.gd` | fortezza di Monte Nero: mura sui pendii, mastio, armi, proiettili e difesa |
| `scripts/enemies.gd` | draghi guardiani: ronda, inseguimento, attacchi, vita e abbattimento |
| `scripts/fx.gd`, `scripts/particles.gd` | particelle, soffio, palle di fuoco, tempesta, esplosioni, luci |
| `scripts/water.gd` | mare che segue la camera |
| `scripts/game_input.gd` | tastiera, mouse, joystick e combinazioni |
| `scripts/hud.gd` | HUD, minimappa, aiuto, schermata iniziale |
| `shaders/` | terreno, edifici in fiamme, foglie, mare, pelle e membrana del drago, particelle |
| `textures/` | materiali PBR CC0 (colore, normali, occlusione/rugosità, rilievo) |

## Non ancora portato

- nuvole, bagliore del sole sullo schermo
- bruciature sul terreno e detriti delle esplosioni
- pipeline di rilascio in CI
