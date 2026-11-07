#!/usr/bin/env bash
# =============================================================================
# tests/test-fallback.sh — valida a cadeia de fallback A → B → C
#
# Cenários:
#   1. todos os métodos falham: A → B → C → cleanup;
#   2. só A falha: B assume e a sessão fica em RUNNING (METHOD=B);
#   3. A e B falham: C assume e a sessão fica em RUNNING (METHOD=C).
#
# Usa os mocks de adb e scrcpy; não precisa de celular nem de root.
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
check_equals() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$label"
  else
    bad "$label (esperado '$expected', obtido '$actual')"
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

# Prepara diretórios e variáveis isoladas para um cenário.
setup_scenario() {
  local name="$1"
  SCENARIO_DIR="$TMP/$name"
  mkdir -p "$SCENARIO_DIR/log" "$SCENARIO_DIR/run" "$SCENARIO_DIR/adb"
  LOG="$SCENARIO_DIR/log/rios-session.log"
  STATUS="$SCENARIO_DIR/run/status"
  export MOCK_ADB_DIR="$SCENARIO_DIR/adb"
  export MOCK_ADB_LOG="$SCENARIO_DIR/adb.log"
  export MOCK_SCRCPY_LOG="$SCENARIO_DIR/scrcpy.log"
  export MOCK_SCRCPY_COUNT_FILE="$SCENARIO_DIR/scrcpy-count"
  export MOCK_ADB_STATE_FILE="$SCENARIO_DIR/device-state"
  echo "device" >"$MOCK_ADB_STATE_FILE"
  cat >"$SCENARIO_DIR/config" <<'CFG'
METHOD=auto
RESOLUTION=1024x600
POLL_INTERVAL=1
ADB_TIMEOUT=2
BLACKOUT_TIMEOUT=1
CFG
}

# Executa o daemon até o fim e devolve o código de saída em DAEMON_RC.
run_daemon_once() {
  DAEMON_RC=0
  RIOS_CONFIG="$SCENARIO_DIR/config" \
  RIOS_LOG_DIR="$SCENARIO_DIR/log" \
  RIOS_STATE_DIR="$SCENARIO_DIR/run" \
    timeout 40 "$DAEMON" --once >"$SCENARIO_DIR/daemon.out" 2>&1 || DAEMON_RC=$?
}

# Espera o status publicar STATE=RUNNING com o método esperado.
wait_for_running() {
  local expected="$1" _
  for _ in $(seq 1 100); do
    if grep -q '^STATE=RUNNING$' "$STATUS" 2>/dev/null &&
       grep -q "^METHOD=${expected}$" "$STATUS" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# Espera o cleanup aparecer no log.
wait_for_cleanup() {
  local _
  for _ in $(seq 1 100); do
    grep -q 'cleanup concluído' "$LOG" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

printf 'test-fallback\n'

export PATH="${ROOT}/tests/mock:${PATH}"
export MOCK_ADB_ANDROID=16
export MOCK_ADB_SDK=35
export MOCK_SCRCPY_DURATION=30

# ---------------------------------------------------------------------------
# Cenário 1 — todos os métodos falham: A → B → C → cleanup.
# ---------------------------------------------------------------------------
setup_scenario all-fail
export MOCK_SCRCPY_FAIL=1
unset MOCK_SCRCPY_FAIL_TIMES

run_daemon_once
check_equals "0" "$DAEMON_RC" "todos falham: daemon encerrou com código 0"

check_contains "$LOG" 'método A' "todos falham: método A tentado"
check_contains "$LOG" 'estado=FALLBACK_B' "todos falham: fallback B acionado"
check_contains "$LOG" 'estado=FALLBACK_C' "todos falham: fallback C acionado"
check_order 'método A' 'estado=FALLBACK_B' 'estado=FALLBACK_C' \
  "todos falham: ordem A → B → C"

check_contains "$MOCK_ADB_LOG" 'settings put global overlay_display_devices' \
  "todos falham: overlay_display_devices aplicado no B"
check_contains "$MOCK_ADB_LOG" 'settings delete global overlay_display_devices' \
  "todos falham: overlay_display_devices removido"

SCRCPY_FAILS="$(grep -c ' FAIL ' "$MOCK_SCRCPY_LOG" 2>/dev/null || true)"
check_equals "3" "$SCRCPY_FAILS" "todos falham: scrcpy falhou nas três tentativas"

check_contains "$LOG" 'cleanup concluído' "todos falham: cleanup executado"
check_contains "$STATUS" '^STATE=IDLE$' "todos falham: status final STATE=IDLE"
check_contains "$STATUS" '^METHOD=$' "todos falham: método limpo no status final"

# ---------------------------------------------------------------------------
# Cenários 2 e 3 — um dos fallbacks assume a sessão.
# ---------------------------------------------------------------------------
run_fallback_success() {
  local fail_times="$1" expected="$2" name="$3" pid rc
  setup_scenario "$name"
  export MOCK_SCRCPY_FAIL=0
  export MOCK_SCRCPY_FAIL_TIMES="$fail_times"

  RIOS_CONFIG="$SCENARIO_DIR/config" \
  RIOS_LOG_DIR="$SCENARIO_DIR/log" \
  RIOS_STATE_DIR="$SCENARIO_DIR/run" \
    "$DAEMON" --once >"$SCENARIO_DIR/daemon.out" 2>&1 &
  pid=$!

  if wait_for_running "$expected"; then
    ok "$name: sessão em RUNNING com METHOD=$expected"
  else
    bad "$name: não chegou a RUNNING/METHOD=$expected"
    cat "$STATUS" 2>/dev/null >&2 || true
    cat "$SCENARIO_DIR/daemon.out" >&2 || true
  fi

  # Encerra o scrcpy com o aparelho ainda conectado: é o caminho em que o
  # cleanup consegue remover o overlay_display_devices do celular.
  local scrcpy_pid
  scrcpy_pid="$(grep -m1 '^SCRCPY_PID=' "$STATUS" 2>/dev/null | cut -d= -f2- || true)"
  if [[ -n "$scrcpy_pid" ]] && kill -TERM "$scrcpy_pid" 2>/dev/null; then
    ok "$name: scrcpy encerrado com o aparelho conectado"
  else
    bad "$name: não foi possível encerrar o scrcpy (PID '${scrcpy_pid:-}')"
  fi

  if wait_for_cleanup; then
    ok "$name: cleanup executado após o encerramento do scrcpy"
  else
    bad "$name: cleanup não executado após o encerramento do scrcpy"
  fi

  rc=0
  wait "$pid" || rc=$?
  check_equals "0" "$rc" "$name: daemon encerrou com código 0"

  local starts fails
  starts="$(grep -c ' START ' "$MOCK_SCRCPY_LOG" 2>/dev/null || true)"
  fails="$(grep -c ' FAIL ' "$MOCK_SCRCPY_LOG" 2>/dev/null || true)"
  check_equals "$fail_times" "$fails" "$name: scrcpy falhou $fail_times vez(es)"
  check_equals "$(( fail_times + 1 ))" "$starts" \
    "$name: scrcpy iniciado no método vencedor"
  check_contains "$MOCK_ADB_LOG" 'settings delete global overlay_display_devices' \
    "$name: overlay removido no cleanup"
  check_contains "$STATUS" '^STATE=IDLE$' "$name: status final STATE=IDLE"
  check_contains "$STATUS" '^METHOD=$' "$name: método limpo no status final"
}

run_fallback_success 1 B "b-assume"
run_fallback_success 2 C "c-assume"

printf '\n%d ok, %d falha(s)\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
