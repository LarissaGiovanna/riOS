#!/usr/bin/env bash
# =============================================================================
# tests/test-fallback.sh — força a falha do método A e verifica A → B → C
#
# MOCK_SCRCPY_FAIL=1 faz o scrcpy falso morrer imediatamente. O daemon deve
# registrar as tentativas A, B e C, limpar o overlay e voltar para IDLE.
# =============================================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON="${ROOT}/runtime/rios-session"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rios-test-fb.XXXXXX")"
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ok()  { PASS=$(( PASS + 1 )); printf '  ok   %s\n' "$*"; }
bad() { FAIL=$(( FAIL + 1 )); printf '  FALHA %s\n' "$*"; }
check_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -q -- "$pattern" "$file" 2>/dev/null; then
    ok "$label"
  else
    bad "$label (não encontrado: $pattern)"
  fi
}
check_order() {
  local first="$1" second="$2" third="$3" label="$4" l1 l2 l3
  l1="$(grep -n -m1 -- "$first" "$LOG" 2>/dev/null | cut -d: -f1 || true)"
  l2="$(grep -n -m1 -- "$second" "$LOG" 2>/dev/null | cut -d: -f1 || true)"
  l3="$(grep -n -m1 -- "$third" "$LOG" 2>/dev/null | cut -d: -f1 || true)"
  if [[ -n "$l1" && -n "$l2" && -n "$l3" ]] && (( l1 < l2 && l2 < l3 )); then
    ok "$label"
  else
    bad "$label (ordem: $l1, $l2, $l3)"
  fi
}

printf 'test-fallback\n'

mkdir -p "$TMP/log" "$TMP/run" "$TMP/adb"
export PATH="${ROOT}/tests/mock:${PATH}"
export MOCK_ADB_DIR="$TMP/adb"
export MOCK_ADB_LOG="$TMP/adb.log"
export MOCK_ADB_STATE="device"
export MOCK_ADB_ANDROID=16
export MOCK_ADB_SDK=35
export MOCK_SCRCPY_LOG="$TMP/scrcpy.log"
export MOCK_SCRCPY_DURATION=30
export MOCK_SCRCPY_FAIL=1

cat >"$TMP/config" <<'CFG'
METHOD=auto
RESOLUTION=1024x600
POLL_INTERVAL=1
ADB_TIMEOUT=2
BLACKOUT_TIMEOUT=1
CFG

LOG="$TMP/log/rios-session.log"
STATUS="$TMP/run/status"

RC=0
RIOS_CONFIG="$TMP/config" \
RIOS_LOG_DIR="$TMP/log" \
RIOS_STATE_DIR="$TMP/run" \
  timeout 40 "$DAEMON" --once >"$TMP/daemon.out" 2>&1 || RC=$?

if [[ "$RC" == "0" ]]; then
  ok "daemon encerrou com código 0 após a cadeia de fallback"
else
  bad "daemon encerrou com código $RC"
  cat "$TMP/daemon.out" >&2 || true
fi

# A cadeia inteira foi percorrida, nesta ordem.
check_contains "$LOG" 'método A' "método A tentado"
check_contains "$LOG" 'estado=FALLBACK_B' "fallback B acionado"
check_contains "$LOG" 'estado=FALLBACK_C' "fallback C acionado"
check_order 'método A' 'estado=FALLBACK_B' 'estado=FALLBACK_C' "ordem A → B → C"

# O overlay foi criado no B e removido no C/cleanup.
check_contains "$TMP/adb.log" 'settings put global overlay_display_devices' "overlay_display_devices aplicado no B"
check_contains "$TMP/adb.log" 'settings delete global overlay_display_devices' "overlay_display_devices removido"

# Três tentativas de scrcpy, todas falhando.
SCRCPY_FAILS="$(grep -c ' FAIL ' "$TMP/scrcpy.log" 2>/dev/null || true)"
if [[ "$SCRCPY_FAILS" == "3" ]]; then
  ok "scrcpy falhou nas três tentativas (A, B e C)"
else
  bad "esperadas 3 falhas de scrcpy, obtidas ${SCRCPY_FAILS:-0}"
fi

# Limpeza e retorno a IDLE.
check_contains "$LOG" 'cleanup concluído' "cleanup executado"
if [[ -r "$STATUS" ]]; then
  check_contains "$STATUS" '^STATE=IDLE$' "status final STATE=IDLE"
  check_contains "$STATUS" '^METHOD=$' "método limpo no status final"
else
  bad "arquivo de status não foi criado"
fi

printf '\n%d ok, %d falha(s)\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
