# Il Volo del Drago

Gioco 3D in Three.js (browser) impacchettato con Electron per Windows e Linux. Vedi README.md.

## Commit

Usa **sempre** [Conventional Commits](https://www.conventionalcommits.org/) per ogni commit:

```
<tipo>(<ambito opzionale>): <descrizione breve all'imperativo>
```

- Tipi: `feat`, `fix`, `perf`, `refactor`, `style`, `docs`, `test`, `build`, `ci`, `chore`, `revert`.
- Modifica incompatibile: `!` dopo il tipo (`feat!: ...`) oppure il piè di pagina `BREAKING CHANGE: ...`.
- Ambiti utili: `dragon`, `world`, `water`, `sky`, `clouds`, `fx`, `input`, `audio`, `hud`, `electron`, `release`.

I commit decidono la versione rilasciata in automatico dalla CI (semantic-release):
`fix`/`perf` → patch, `feat` → minor, breaking change → major. Gli altri tipi non producono un rilascio.

## Rilascio

Ogni push su `main` esegue `.github/workflows/release.yml`: semantic-release calcola la versione dai commit,
compila `IlVoloDelDrago-<versione>.exe` e lo allega alla GitHub Release con le note generate.
Non modificare a mano la versione in `package.json`: la imposta la CI.

## Sviluppo

- `npm install` copia Three.js in `vendor/` (non versionata).
- `node server.js` → http://localhost:5173; `npm start` → app Electron.
- `npm run dist:win` / `npm run dist:linux` per i pacchetti in `dist/`.
