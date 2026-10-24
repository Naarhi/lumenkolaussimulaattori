#!/usr/bin/env bash
# Moninpelitesti: headless-palvelin ja kaksi automaattista asiakasta paikallisesti.
# Käyttö: tests/multiplayer_test.sh [godot-binääri]
set -u
GODOT="${1:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-17777}"
LOG="$(mktemp -d)"

"$GODOT" --headless --path "$ROOT" -- --server --port=$PORT >"$LOG/server.log" 2>&1 &
SERVER=$!
sleep 2

"$GODOT" --headless --path "$ROOT" -- --connect=127.0.0.1 --port=$PORT --autotest >"$LOG/client1.log" 2>&1 &
C1=$!
"$GODOT" --headless --path "$ROOT" -- --connect=127.0.0.1 --port=$PORT --autotest >"$LOG/client2.log" 2>&1 &
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
# Jokainen työkalu yksinpelissä
for t in 1 2 3 4; do
	if "$GODOT" --headless --path "$ROOT" -- --host --port=$((PORT + 10 + t)) --autotest --tool=$t >"$LOG/tool$t.log" 2>&1; then
		grep "AUTOTEST .*lumi" "$LOG/tool$t.log"
	else
		echo "Työkalu $t epäonnistui"; grep -E "AUTOTEST|SCRIPT ERROR" "$LOG/tool$t.log" | head -5; fail=1
	fi
done
if [ $fail -eq 0 ]; then echo "MONINPELITESTI OK"; else echo "MONINPELITESTI EPÄONNISTUI (lokit: $LOG)"; fi
exit $fail
