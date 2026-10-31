#!/bin/sh
# Avvio del gioco su Linux: l'archivio creato su Windows perde il permesso di esecuzione,
# e su molte distribuzioni il sandbox di Chromium richiede permessi di root: lo si disattiva.
cd "$(dirname "$0")"
chmod +x ./il-volo-del-drago 2>/dev/null
exec ./il-volo-del-drago --no-sandbox "$@"
