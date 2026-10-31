# Il Volo del Drago

Gioco 3D nel browser (Three.js): un drago vola su isole con villaggi medievali, castello, mare e nuvole.

## Giocare

- **Windows**: scarica `IlVoloDelDrago-<versione>.exe` dalle [Release](https://github.com/lucagessi/FlightOfTheDragon/releases) (eseguibile portatile, non serve installare nulla).
- **Linux 64 bit**: `npm run dist:linux`, estrai `dist/IlVoloDelDrago-<versione>-linux-x64.tar.gz` e avvia `sh avvia.sh` dalla cartella estratta.
- **Browser**: `npm install` (una volta), poi `node server.js` e apri http://localhost:5173.
  Non aprire `index.html` direttamente come file: il browser blocca gli script.

F11 schermo intero, F12 strumenti di sviluppo (solo nell'app).

## Compilare i pacchetti

```bash
npm install
npm run dist        # Windows .exe + Linux x64 .tar.gz in dist/
npm run dist:win    # solo Windows
npm run dist:linux  # solo Linux
```

## Rilasci automatici

Ogni push su `main` avvia la CI (`.github/workflows/release.yml`): semantic-release legge i messaggi di commit
([Conventional Commits](https://www.conventionalcommits.org/)), calcola la nuova versione, compila l'exe e lo pubblica
nella GitHub Release `v<versione>`. `fix:` → patch, `feat:` → minor, `feat!:` / `BREAKING CHANGE:` → major.

## Comandi

| Azione | Tastiera / mouse | Joystick |
|---|---|---|
| Sali / scendi | W S o ↑ ↓ | levetta sinistra |
| Vira | A D o ← → | levetta sinistra |
| Accelera / rallenta | Shift o E / Q o Z | A / B |
| Sputa fuoco | Spazio o clic sinistro | RT |
| Camera | destro + trascina, rotella | levetta destra |
| Aiuto · Pausa · Audio · Inverti asse | H · P · M · I | Back · Start |

### Combinazioni speciali

- **Palla di fuoco**: doppio tocco di Spazio (joystick: X o doppio RT)
- **Tempesta di fuoco**: ↓ ↑ + Spazio (joystick: LT + RT)
- **Piroetta**: doppio tocco di A o D (joystick: LB / RB)
- **Giro della morte**: doppio tocco di W (joystick: Y)

## Struttura

- `src/main.js` — ciclo di gioco, camera in terza persona, HUD, minimappa
- `src/dragon.js` — modello procedurale del drago, ali, volo e manovre
- `src/world.js` — terreno, villaggi, castello, alberi, incendi
- `src/water.js` — shader del mare (onde, riflessi, schiuma, spostamento d'aria)
- `src/sky.js`, `src/clouds.js`, `src/flare.js` — cielo, nuvole, bagliori del sole
- `src/fx.js` — particelle, palle di fuoco, tempesta di fuoco, luci dinamiche
- `src/input.js`, `src/audio.js` — input con combo e audio procedurale
