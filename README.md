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
| Atterra / decolla | L | pressione levetta sinistra |
| Aiuto · Pausa · Audio · Inverti asse | H · P · M · I | Back · Start |

### A terra

Vicino al suolo premi **L** per atterrare (non sull'acqua). A terra il drago cammina: W/S avanti e indietro,
A/D per girare, Shift per correre. Il mouse (clicca per catturarlo, Esc lo libera), le frecce o la levetta destra
muovono la testa; girandola molto di lato il corpo la segue. La camera sta dietro al drago, orientata come la mira,
e il fuoco (soffio e palle di fuoco) va esattamente nel mirino. Da fermo, dopo qualche secondo, il drago si guarda
intorno da solo. Premi di nuovo **L** (joystick: pressione della levetta sinistra) per decollare.

### Combinazioni speciali

- **Palla di fuoco**: doppio tocco di Spazio (joystick: X o doppio RT)
- **Tempesta di fuoco**: ↓ ↑ + Spazio (joystick: LT + RT)
- **Piroetta**: doppio tocco di A o D (joystick: LB / RB)
- **Giro della morte**: doppio tocco di W (joystick: Y)

### Draghi guardiani

Cinque draghi rivali (Smeraldo, Zaffiro, Ambra e il più robusto drago d'Ombra, che difende il castello) proteggono
ciascuno un villaggio e gli volano intorno. Sono neutrali finché non attacchi loro o incendi il loro villaggio:
allora diventano ostili, ti inseguono e attaccano con fiamme e palle di fuoco viola; se lasci il loro territorio
dopo un po' si calmano. Hanno una barra della vita (dorata se neutrali, rossa se ostili): colpiscili con soffio,
palle di fuoco o tempesta finché non precipitano. Un villaggio rimasto scoperto riceve più tardi un nuovo guardiano.
Con un drago davanti si attiva la mira assistita. Se la tua vita si esaurisce precipiti e riparti dopo qualche
secondo; la vita si rigenera se non vieni colpito.

## Struttura

- `src/main.js` — ciclo di gioco, camera in terza persona, HUD, minimappa
- `src/dragon.js` — modello procedurale del drago, ali, volo e manovre
- `src/world.js` — terreno, villaggi, castello, alberi, incendi
- `src/water.js` — shader del mare (onde, riflessi, schiuma, spostamento d'aria)
- `src/sky.js`, `src/clouds.js`, `src/flare.js` — cielo, nuvole, bagliori del sole
- `src/enemies.js` — draghi nemici: comportamento, attacchi, vita, abbattimento
- `src/fx.js` — particelle, palle di fuoco, tempesta di fuoco, luci dinamiche
- `src/input.js`, `src/audio.js` — input con combo e audio procedurale
