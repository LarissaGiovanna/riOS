#!/usr/bin/env bash
# =============================================================================
# tests/test-cli.sh — testa a CLI rios-launch com adb simulado
#
# Cobre start, status, logs, restart, stop, shell e comando inválido no modo
# direto (RIOS_INIT=direct), sem systemd/runit e sem celular.
# =============================================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCH="${ROOT}/runtime/rios-launch"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rios-test-cli.XXXXXX")"
PASS=0
FAIL=0

cleanup() {
  RIOS_INIT=direct RIOS_CONFIG="$TMP/config" RIOS_LOG_DIR="$TMP/log" \
    RIOS_STATE_DIR="$TMP/run" "$LAUNCH" stop >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
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

printf 'test-cli\n'

mkdir -p "$TMP/log" "$TMP/run" "$TMP/adb"
cat >"$TMP/config" <<'CFG'
METHOD=auto
RESOLUTION=1024x600
POLL_INTERVAL=1
ADB_TIMEOUT=2
BLACKOUT_TIMEOUT=1
CFG

export PATH="${ROOT}/tests/mock:${PATH}"
export MOCK_ADB_DIR="$TMP/adb"
export MOCK_ADB_LOG="$TMP/adb.log"
export MOCK_ADB_STATE=none
export MOCK_ADB_ANDROID=16
export MOCK_ADB_SDK=35
export MOCK_SCRCPY_LOG="$TMP/scrcpy.log"
export MOCK_SCRCPY_COUNT_FILE="$TMP/scrcpy-count"
export MOCK_SCRCPY_DURATION=30
export RIOS_INIT=direct
export RIOS_CONFIG="$TMP/config"
export RIOS_LOG_DIR="$TMP/log"
export RIOS_STATE_DIR="$TMP/run"

run_launch() {
  "$LAUNCH" "$@" >"$TMP/out" 2>"$TMP/err"
}

# ---------------------------------------------------------------------------
# 1. start → daemon ativo em modo direto.
# ---------------------------------------------------------------------------
if run_launch start; then
  ok "start retorna sucesso"
else
  bad "start falhou"
  cat "$TMP/err" >&2 || true
fi
check_contains "$TMP/out" 'modo direto' "start informa o modo direto"
if [[ -s "$TMP/run/rios-session.pid" ]]; then
  ok "arquivo de PID criado"
else
  bad "arquivo de PID não foi criado"
fi

# ---------------------------------------------------------------------------
# 2. status mostra daemon ativo, estado IDLE e init detectado.
# ---------------------------------------------------------------------------
sleep 0.3
if run_launch status; then
  ok "status retorna sucesso"
else
  bad "status falhou"
fi
check_contains "$TMP/out" 'Init...........: direct' "status mostra init=direct"
check_contains "$TMP/out" 'Daemon.........: ativo' "status mostra daemon ativo"
check_contains "$TMP/out" 'Estado.........: IDLE' "status mostra estado IDLE"
check_contains "$TMP/out" 'Aparelho.......: nenhum aparelho conectado' \
  "status mostra ausência de aparelho"

# ---------------------------------------------------------------------------
# 3. logs mostra o início do daemon.
# ---------------------------------------------------------------------------
if run_launch logs; then
  ok "logs retorna sucesso"
else
  bad "logs falhou"
fi
check_contains "$TMP/out" 'iniciando' "logs mostram o início do daemon"
check_contains "$TMP/out" 'estado=IDLE' "logs mostram o estado IDLE"

# ---------------------------------------------------------------------------
# 4. restart reinicia o daemon (novo PID).
# ---------------------------------------------------------------------------
OLD_PID="$(tr -dc '0-9' <"$TMP/run/rios-session.pid" 2>/dev/null || true)"
if run_launch restart; then
  ok "restart retorna sucesso"
else
  bad "restart falhou"
  cat "$TMP/err" >&2 || true
fi
sleep 0.3
NEW_PID="$(tr -dc '0-9' <"$TMP/run/rios-session.pid" 2>/dev/null || true)"
if [[ -n "$NEW_PID" && "$NEW_PID" != "$OLD_PID" ]]; then
  ok "restart trocou o PID do daemon"
else
  bad "restart não trocou o PID (antes '${OLD_PID:-}', depois '${NEW_PID:-}')"
fi

# ---------------------------------------------------------------------------
# 5. stop encerra o daemon.
# ---------------------------------------------------------------------------
if run_launch stop; then
  ok "stop retorna sucesso"
else
  bad "stop falhou"
fi
check_contains "$TMP/out" 'encerrado' "stop informa o encerramento"
if [[ -s "$TMP/run/rios-session.pid" ]]; then
  bad "arquivo de PID não foi removido"
else
  ok "arquivo de PID removido"
fi

# ---------------------------------------------------------------------------
# 6. shell usa o adb (mock) e repassa o comando.
# ---------------------------------------------------------------------------
export MOCK_ADB_STATE=device
if run_launch shell getprop ro.build.version.release; then
  ok "shell retorna sucesso"
else
  bad "shell falhou"
  cat "$TMP/err" >&2 || true
fi
check_contains "$TMP/out" '^16$' "shell devolve a versão do Android simulada"
export MOCK_ADB_STATE=none

# ---------------------------------------------------------------------------
# 7. Comando inválido e ajuda.
# ---------------------------------------------------------------------------
RC=0
run_launch banana || RC=$?
check_equals "2" "$RC" "comando inválido retorna código 2"
check_contains "$TMP/err" 'comando desconhecido' "comando inválido explica o erro"

RC=0
run_launch --help || RC=$?
check_equals "0" "$RC" "--help retorna código 0"
check_contains "$TMP/out" 'Uso:' "--help mostra o uso"

printf '\n%d ok, %d falha(s)\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
