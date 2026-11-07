#!/usr/bin/env bash
# =============================================================================
# tests/test-state-machine.sh — testa IDLE → PREPARING → RUNNING → IDLE
#
# Usa os mocks de adb e scrcpy no PATH; não precisa de celular nem de root.
# =============================================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON="${ROOT}/runtime/rios-session"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rios-test-sm.XXXXXX")"
PID=""
PASS=0
FAIL=0

cleanup() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill -TERM "$PID" 2>/dev/null || true
    sleep 0.3
    kill -KILL "$PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

ok()   { PASS=$(( PASS + 1 )); printf '  ok   %s\n' "$*"; }
bad()  { FAIL=$(( FAIL + 1 )); printf '  FALHA %s\n' "$*"; }
check_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -q -- "$pattern" "$file" 2>/dev/null; then
    ok "$label"
  else
    bad "$label (não encontrado: $pattern)"
  fi
}
check_equals() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$label"
  else
    bad "$label (esperado '$expected', obtido '$actual')"
  fi
}
# Verifica a ordem de dois padrões no arquivo de log.
check_order() {
  local first="$1" second="$2" label="$3" l1 l2
  l1="$(grep -n -m1 -- "$first" "$LOG" 2>/dev/null | cut -d: -f1 || true)"
  l2="$(grep -n -m1 -- "$second" "$LOG" 2>/dev/null | cut -d: -f1 || true)"
  if [[ -n "$l1" && -n "$l2" ]] && (( l1 < l2 )); then
    ok "$label"
  else
    bad "$label (ordem: '$first'=$l1, '$second'=$l2)"
  fi
}

printf 'test-state-machine\n'

mkdir -p "$TMP/log" "$TMP/run" "$TMP/adb"
export PATH="${ROOT}/tests/mock:${PATH}"
export MOCK_ADB_DIR="$TMP/adb"
export MOCK_ADB_LOG="$TMP/adb.log"
export MOCK_ADB_STATE_FILE="$TMP/device-state"
export MOCK_ADB_ANDROID=16
export MOCK_ADB_SDK=35
export MOCK_SCRCPY_LOG="$TMP/scrcpy.log"
export MOCK_SCRCPY_DURATION=30
export MOCK_SCRCPY_FAIL=0

echo "device" >"$TMP/device-state"

cat >"$TMP/config" <<'CFG'
METHOD=auto
RESOLUTION=1024x600
DPI=160
POLL_INTERVAL=1
ADB_TIMEOUT=2
BLACKOUT_TIMEOUT=1
CFG

LOG="$TMP/log/rios-session.log"
STATUS="$TMP/run/status"

RIOS_CONFIG="$TMP/config" \
RIOS_LOG_DIR="$TMP/log" \
RIOS_STATE_DIR="$TMP/run" \
  "$DAEMON" --once >"$TMP/daemon.out" 2>&1 &
PID=$!

# Espera o daemon entrar em RUNNING (máximo ~10 s).
for _ in $(seq 1 100); do
  grep -q 'estado=RUNNING' "$LOG" 2>/dev/null && break
  sleep 0.1
done
if grep -q 'estado=RUNNING' "$LOG" 2>/dev/null; then
  ok "daemon entrou em RUNNING"
else
  bad "daemon não entrou em RUNNING"
  cat "$LOG" 2>/dev/null || true
fi

# Confere o status publicado para a CLI.
if [[ -r "$STATUS" ]]; then
  check_contains "$STATUS" '^STATE=RUNNING$' "status com STATE=RUNNING"
  check_contains "$STATUS" '^METHOD=A$' "status com METHOD=A"
else
  bad "arquivo de status não foi criado"
fi

# Desconecta o celular e espera a limpeza.
echo "none" >"$TMP/device-state"
for _ in $(seq 1 100); do
  grep -q 'cleanup concluído' "$LOG" 2>/dev/null && break
  sleep 0.1
done
if grep -q 'cleanup concluído' "$LOG" 2>/dev/null; then
  ok "cleanup executado após o unplug"
else
  bad "cleanup não executado após o unplug"
fi

# Espera o processo terminar (o --once encerra após o primeiro ciclo).
for _ in $(seq 1 100); do
  [[ -e "/proc/$PID" ]] || break
  [[ "$(awk '{print $3}' "/proc/$PID/stat" 2>/dev/null || true)" == "Z" ]] && break
  sleep 0.1
done
DAEMON_RC=0
wait "$PID" || DAEMON_RC=$?
PID=""
check_equals "0" "$DAEMON_RC" "daemon encerrou com código 0"

# Transições esperadas.
check_contains "$LOG" 'estado=IDLE' "estado IDLE registrado"
check_contains "$LOG" 'estado=PREPARING' "estado PREPARING registrado"
check_contains "$LOG" 'estado=RUNNING' "estado RUNNING registrado"
check_contains "$LOG" 'método A' "método A tentado"
check_order 'estado=IDLE' 'estado=PREPARING' "ordem IDLE → PREPARING"
check_order 'estado=PREPARING' 'estado=RUNNING' "ordem PREPARING → RUNNING"
check_order 'estado=RUNNING' 'cleanup concluído' "ordem RUNNING → cleanup"

# O scrcpy foi iniciado e encerrado pelo daemon.
check_contains "$TMP/scrcpy.log" 'START' "scrcpy iniciado"
check_contains "$TMP/scrcpy.log" 'TERM' "scrcpy encerrado no cleanup"

# Os três settings globais foram aplicados.
check_contains "$TMP/adb.log" 'enable_freeform_support' "setting enable_freeform_support aplicado"
check_contains "$TMP/adb.log" 'force_desktop_mode_on_external_displays' "setting force_desktop_mode aplicado"
check_contains "$TMP/adb.log" 'enable_non_resizable_multi_window' "setting enable_non_resizable aplicado"

# O overlay é limpo no prepare (o unplug deixa o aparelho sem transporte para
# o cleanup falar com ele).
OVERLAY_DELETES="$(grep -c 'settings delete global overlay_display_devices' "$TMP/adb.log" 2>/dev/null || true)"
if [[ "${OVERLAY_DELETES:-0}" -ge 1 ]]; then
  ok "overlay_display_devices limpo no prepare"
else
  bad "nenhuma limpeza de overlay no prepare"
fi

# O daemon voltou a IDLE.
if [[ -r "$STATUS" ]]; then
  check_contains "$STATUS" '^STATE=IDLE$' "status final STATE=IDLE"
  check_contains "$STATUS" '^METHOD=$' "método limpo no status final"
else
  bad "status final ausente"
fi

printf '\n%d ok, %d falha(s)\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
