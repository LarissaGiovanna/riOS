#!/usr/bin/env bash
# =============================================================================
# tests/test-device-states.sh — testa as mensagens da tela de espera
#
# Casos: sem aparelho, não autorizado, offline, bloqueado e adb ausente.
# Cada caso roda o daemon com --once, sem celular e sem root, usando o mock
# de adb em tests/mock/.
# =============================================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON="${ROOT}/runtime/rios-session"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rios-test-ds.XXXXXX")"
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ok()  { PASS=$(( PASS + 1 )); printf '  ok   %s\n' "$*"; }
bad() { FAIL=$(( FAIL + 1 )); printf '  FALHA %s\n' "$*"; }
check_equals() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$label"
  else
    bad "$label (esperado '$expected', obtido '$actual')"
  fi
}
check_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -q -- "$pattern" "$file" 2>/dev/null; then
    ok "$label"
  else
    bad "$label (não encontrado: $pattern)"
  fi
}

# Cria diretórios isolados para um caso.
setup_case() {
  local name="$1"
  SCENARIO_DIR="$TMP/$name"
  mkdir -p "$SCENARIO_DIR/log" "$SCENARIO_DIR/run" "$SCENARIO_DIR/adb" "$SCENARIO_DIR/empty"
  LOG="$SCENARIO_DIR/log/rios-session.log"
  STATUS="$SCENARIO_DIR/run/status"
  WAIT_MSG="$SCENARIO_DIR/run/wait-message"
  export MOCK_ADB_DIR="$SCENARIO_DIR/adb"
  export MOCK_ADB_LOG="$SCENARIO_DIR/adb.log"
  export MOCK_SCRCPY_LOG="$SCENARIO_DIR/scrcpy.log"
  export MOCK_SCRCPY_COUNT_FILE="$SCENARIO_DIR/scrcpy-count"
  unset MOCK_ADB_STATE_FILE MOCK_ADB_SEQUENCE MOCK_ADB_LOCKED MOCK_ADB_STATE
  cat >"$SCENARIO_DIR/config" <<'CFG'
METHOD=auto
RESOLUTION=1024x600
POLL_INTERVAL=1
ADB_TIMEOUT=2
BLACKOUT_TIMEOUT=1
CFG
}

# Roda o daemon uma vez com o ambiente do caso atual.
run_case() {
  local name="$1" expected="$2" rc=0
  local run_path="${DAEMON_PATH:-$PATH}"
  env PATH="$run_path" \
    RIOS_CONFIG="$SCENARIO_DIR/config" \
    RIOS_LOG_DIR="$SCENARIO_DIR/log" \
    RIOS_STATE_DIR="$SCENARIO_DIR/run" \
    RIOS_WAIT_SCREEN_DIR="$SCENARIO_DIR/empty" \
    "$DAEMON" --once >"$SCENARIO_DIR/daemon.out" 2>"$SCENARIO_DIR/daemon.err" || rc=$?

  check_equals "0" "$rc" "$name: daemon encerrou com código 0"
  check_contains "$WAIT_MSG" "$expected" "$name: mensagem na tela de espera"
  check_contains "$LOG" 'tela de espera' "$name: mensagem registrada no log"
  check_contains "$STATUS" '^STATE=IDLE$' "$name: status final STATE=IDLE"
  if [[ -s "${MOCK_SCRCPY_LOG:-}" ]]; then
    bad "$name: scrcpy não deveria ter sido iniciado"
  else
    ok "$name: scrcpy não foi iniciado"
  fi
}

printf 'test-device-states\n'

export PATH="${ROOT}/tests/mock:${PATH}"
export MOCK_ADB_ANDROID=16
export MOCK_ADB_SDK=35
export MOCK_SCRCPY_DURATION=30

# ---------------------------------------------------------------------------
# 1. Nenhum aparelho conectado.
# ---------------------------------------------------------------------------
setup_case none
export MOCK_ADB_STATE=none
run_case "sem aparelho" "Conecte o celular Samsung por USB"

# ---------------------------------------------------------------------------
# 2. Aparelho conectado, mas sem autorização da chave RSA.
# ---------------------------------------------------------------------------
setup_case unauthorized
export MOCK_ADB_STATE=unauthorized
run_case "não autorizado" "Autorize a depuração USB no celular"

# ---------------------------------------------------------------------------
# 3. Aparelho offline (cabo ruim ou adb travado).
# ---------------------------------------------------------------------------
setup_case offline
export MOCK_ADB_STATE=offline
run_case "offline" "Celular offline — reconecte o cabo USB"

# ---------------------------------------------------------------------------
# 4. Aparelho autorizado, mas com a tela bloqueada.
# ---------------------------------------------------------------------------
setup_case locked
export MOCK_ADB_STATE=device
export MOCK_ADB_LOCKED=1
run_case "bloqueado" "Desbloqueie o celular"

# ---------------------------------------------------------------------------
# 5. adb ausente do PATH (sandbox mínima, sem o mock).
# ---------------------------------------------------------------------------
setup_case noadb
export MOCK_ADB_STATE=none
SANDBOX="$SCENARIO_DIR/sandbox"
mkdir -p "$SANDBOX"
for tool in bash env date mkdir mv rm stat dirname sleep cat; do
  src="$(command -v "$tool" 2>/dev/null || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$SANDBOX/$tool"
done
SAVED_PATH="$PATH"
DAEMON_PATH="$SANDBOX"
run_case "adb ausente" "adb não encontrado"
unset DAEMON_PATH
export PATH="$SAVED_PATH"

printf '\n%d ok, %d falha(s)\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
