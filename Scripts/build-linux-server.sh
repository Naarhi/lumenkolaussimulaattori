#!/usr/bin/env bash
# Paketoi dedikoidun Linux-palvelimen Linuxilla (esim. suoraan kotipalvelimella).
# Vaatii lähdekoodista käännetyn UE5:n hakemistossa $UE_ROOT.
set -euo pipefail

: "${UE_ROOT:?Aseta UE_ROOT osoittamaan lähdekoodista käännettyyn Unreal Engineen}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$UE_ROOT/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
  -project="$ROOT/LumenKolaus.uproject" -noP4 -utf8output \
  -platform=Linux -server -serverplatform=Linux -noclient \
  -serverconfig=Development \
  -build -cook -stage -pak -archive -archivedirectory="$ROOT/Out"

echo "Valmis: $ROOT/Out/LinuxServer"
