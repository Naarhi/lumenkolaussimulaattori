#!/usr/bin/env bash
# Moninpelitesti: headless-palvelin ja kaksi automaattista asiakasta paikallisesti.
# Käyttö: tests/multiplayer_test.sh [godot-binääri]
set -u
GODOT="${1:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-17777}"
LOG="$(mktemp -d)"

SAVE="$LOG/kolaajat.json"
"$GODOT" --headless --path "$ROOT" -- --server --port=$PORT --save="$SAVE" >"$LOG/server.log" 2>&1 &
SERVER=$!
sleep 2

"$GODOT" --headless --path "$ROOT" -- --connect=127.0.0.1 --port=$PORT --autotest --name=Testi1 >"$LOG/client1.log" 2>&1 &
C1=$!
"$GODOT" --headless --path "$ROOT" -- --connect=127.0.0.1 --port=$PORT --autotest --name=Testi2 >"$LOG/client2.log" 2>&1 &
C2=$!

fail=0
for pid in $C1 $C2; do
	( sleep 40; kill $pid 2>/dev/null ) &
	wait $pid || fail=1
done
kill $SERVER 2>/dev/null

for f in server client1 client2; do
	echo "=== $f ==="
	grep -E "AUTOTEST|\[Peli\]|\[Chat\]|SCRIPT ERROR|ERROR" "$LOG/$f.log" | head -40
done
grep -q "AUTOTEST OK" "$LOG/client1.log" && grep -q "AUTOTEST OK" "$LOG/client2.log" || fail=1
grep -q "SCRIPT ERROR" "$LOG"/*.log && fail=1
# Palvelin välitti molempien chat-viestit.
[ "$(grep -c '\[Chat\]' "$LOG/server.log")" -ge 2 ] || { echo "Chat-viestit puuttuvat"; fail=1; }
# XP säilyy nimen mukaan palvelimen uudelleenkäynnistyksen yli.
sleep 1
"$GODOT" --headless --path "$ROOT" -- --server --port=$PORT --save="$SAVE" >"$LOG/server2.log" 2>&1 &
SERVER=$!
sleep 2
timeout 40 "$GODOT" --headless --path "$ROOT" -- --connect=127.0.0.1 --port=$PORT --autotest --name=testi1 >"$LOG/client3.log" 2>&1
kill $SERVER 2>/dev/null
if grep -qi "Testi1 (Kolaus-taso [0-9]*) palasi" "$LOG/client3.log"; then
	grep -h "palasi" "$LOG/client3.log"
else
	echo "XP ei säilynyt (tallennus: $(cat "$SAVE" 2>/dev/null | tr -d '\n\t'))"; fail=1
fi

# Pertti tuo Jallu-colaa, ja sen juominen antaa boostin.
if "$GODOT" --headless --path "$ROOT" -- --host --port=$((PORT + 20)) --autotest --jallu --give --save="$LOG/tool.json" >"$LOG/jallu.log" 2>&1; then
	grep "Jallu-cola:" "$LOG/jallu.log"
else
	echo "Jallu-cola epäonnistui"; grep -E "AUTOTEST|SCRIPT ERROR" "$LOG/jallu.log" | head -5; fail=1
fi

# Naapuri maksaa kolauksesta ja rahalla saa rautakaupasta MASI-kolan.
if "$GODOT" --headless --path "$ROOT" -- --host --port=$((PORT + 21)) --autotest --economy --save="$LOG/talous.json" >"$LOG/economy.log" 2>&1; then
	grep "Talous:" "$LOG/economy.log"
	grep -q '"masi"' "$LOG/talous.json" || { echo "Ostos ei tallentunut"; fail=1; }
else
	echo "Talous epäonnistui"; grep -E "AUTOTEST|SCRIPT ERROR" "$LOG/economy.log" | head -5; fail=1
fi

# Hirvi potkii tyhjin käsin tulevaa ja lähtee naavalla.
if "$GODOT" --headless --path "$ROOT" -- --host --port=$((PORT + 23)) --autotest --hirvi --save="$LOG/tool.json" >"$LOG/moose.log" 2>&1; then
	grep "Hirvi:" "$LOG/moose.log"
else
	echo "Hirvi epäonnistui"; grep -E "AUTOTEST|SCRIPT ERROR" "$LOG/moose.log" | head -5; fail=1
fi

# Tanssit ja aura-auton alle jääminen.
if "$GODOT" --headless --path "$ROOT" -- --host --port=$((PORT + 24)) --autotest --tanssi --aura --save="$LOG/tool.json" >"$LOG/dance.log" 2>&1; then
	grep -E "Tanssi:|Aura-auto:" "$LOG/dance.log"
else
	echo "Tanssi tai aura-auto epäonnistui"; grep -E "AUTOTEST|SCRIPT ERROR" "$LOG/dance.log" | head -5; fail=1
fi

# Moottorikelkalla pääsee ajamaan.
if "$GODOT" --headless --path "$ROOT" -- --host --port=$((PORT + 22)) --autotest --kelkka --give --save="$LOG/tool.json" >"$LOG/sled.log" 2>&1; then
	grep "Moottorikelkka:" "$LOG/sled.log"
else
	echo "Moottorikelkka epäonnistui"; grep -E "AUTOTEST|SCRIPT ERROR" "$LOG/sled.log" | head -5; fail=1
fi

# Jokainen työkalu yksinpelissä
for t in 1 2 3 4; do
	if "$GODOT" --headless --path "$ROOT" -- --host --port=$((PORT + 10 + t)) --autotest --tool=$t --give --save="$LOG/tool.json" >"$LOG/tool$t.log" 2>&1; then
		grep "AUTOTEST .*lumi" "$LOG/tool$t.log"
	else
		echo "Työkalu $t epäonnistui"; grep -E "AUTOTEST|SCRIPT ERROR" "$LOG/tool$t.log" | head -5; fail=1
	fi
done
if [ $fail -eq 0 ]; then echo "MONINPELITESTI OK"; else echo "MONINPELITESTI EPÄONNISTUI (lokit: $LOG)"; fi
exit $fail
