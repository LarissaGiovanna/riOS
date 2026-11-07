#!/usr/bin/env bash
# =============================================================================
# tests/test-config.sh — testa o parsing de /etc/rios/config
#
# Casos: configuração válida, comentários, valores inválidos (fallback para o
# default e --check-config com erro), arquivo ausente e o template do repo.
# =============================================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON="${ROOT}/runtime/rios-session"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rios-test-cfg.XXXXXX")"
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

# Executa o daemon em modo de inspeção sem criar log em /var/log.
run_daemon() {
  local config="$1" mode="$2" out="$3" err="$4"
  RIOS_CONFIG="$config" \
  RIOS_LOG_DIR="$TMP/log" \
  RIOS_STATE_DIR="$TMP/run" \
    "$DAEMON" "$mode" >"$out" 2>"$err"
}

mkdir -p "$TMP/log" "$TMP/run"
printf 'test-config\n'

# ---------------------------------------------------------------------------
# 1. Configuração válida com comentários e comentário inline.
# ---------------------------------------------------------------------------
cat >"$TMP/valid.conf" <<'CFG'
# comentário de linha inteira
METHOD=mirror          # comentário inline
RESOLUTION=800x480
DPI=140
FPS=20
BITRATE=6M
VIDEO_CODEC=h265
AUDIO=on
RENDER_DRIVER=opengl
KEYBOARD=uhid
MOUSE=uhid
WINDOW_MODE=window
BLACKOUT_TIMEOUT=7
ADB_TIMEOUT=3
POLL_INTERVAL=1
CFG

run_daemon "$TMP/valid.conf" --dump-config "$TMP/valid.out" "$TMP/valid.err"
check_contains "$TMP/valid.out" '^METHOD=mirror$' "METHOD lido"
check_contains "$TMP/valid.out" '^RESOLUTION=800x480$' "RESOLUTION lida"
check_contains "$TMP/valid.out" '^DPI=140$' "DPI lido"
check_contains "$TMP/valid.out" '^FPS=20$' "FPS lido"
check_contains "$TMP/valid.out" '^BITRATE=6M$' "BITRATE lido"
check_contains "$TMP/valid.out" '^VIDEO_CODEC=h265$' "VIDEO_CODEC lido"
check_contains "$TMP/valid.out" '^AUDIO=on$' "AUDIO lido"
check_contains "$TMP/valid.out" '^RENDER_DRIVER=opengl$' "RENDER_DRIVER lido"
check_contains "$TMP/valid.out" '^KEYBOARD=uhid$' "KEYBOARD lido"
check_contains "$TMP/valid.out" '^MOUSE=uhid$' "MOUSE lido"
check_contains "$TMP/valid.out" '^WINDOW_MODE=window$' "WINDOW_MODE lido"
check_contains "$TMP/valid.out" '^BLACKOUT_TIMEOUT=7$' "BLACKOUT_TIMEOUT lido"
check_contains "$TMP/valid.out" '^ADB_TIMEOUT=3$' "ADB_TIMEOUT lido"
check_contains "$TMP/valid.out" '^POLL_INTERVAL=1$' "POLL_INTERVAL lido"

if run_daemon "$TMP/valid.conf" --check-config "$TMP/chk.out" "$TMP/chk.err"; then
  ok "--check-config aceita configuração válida"
else
  bad "--check-config rejeitou configuração válida"
fi

# ---------------------------------------------------------------------------
# 2. Valores inválidos: --check-config falha e dump volta aos defaults.
# ---------------------------------------------------------------------------
cat >"$TMP/invalid.conf" <<'CFG'
METHOD=banana
RESOLUTION=abc
DPI=9999
FPS=0
BITRATE=0
VIDEO_CODEC=vp9
AUDIO=maybe
RENDER_DRIVER=vulkan
KEYBOARD=foo
MOUSE=bar
WINDOW_MODE=float
BLACKOUT_TIMEOUT=0
ADB_TIMEOUT=abc
POLL_INTERVAL=-1
CFG

run_daemon "$TMP/invalid.conf" --dump-config "$TMP/invalid.out" "$TMP/invalid.err"
check_contains "$TMP/invalid.out" '^METHOD=auto$' "METHOD inválido voltou para auto"
check_contains "$TMP/invalid.out" '^RESOLUTION=auto$' "RESOLUTION inválida voltou para auto"
check_contains "$TMP/invalid.out" '^DPI=160$' "DPI inválido voltou para 160"
check_contains "$TMP/invalid.out" '^FPS=15$' "FPS inválido voltou para 15"
check_contains "$TMP/invalid.out" '^BITRATE=4M$' "BITRATE inválido voltou para 4M"
check_contains "$TMP/invalid.out" '^VIDEO_CODEC=h264$' "codec inválido voltou para h264"
check_contains "$TMP/invalid.out" '^AUDIO=off$' "AUDIO inválido voltou para off"
check_contains "$TMP/invalid.out" '^RENDER_DRIVER=software$' "driver inválido voltou para software"
check_contains "$TMP/invalid.out" '^KEYBOARD=sdk$' "KEYBOARD inválido voltou para sdk"
check_contains "$TMP/invalid.out" '^MOUSE=sdk$' "MOUSE inválido voltou para sdk"
check_contains "$TMP/invalid.out" '^WINDOW_MODE=fullscreen$' "WINDOW_MODE inválido voltou para fullscreen"
check_contains "$TMP/invalid.out" '^BLACKOUT_TIMEOUT=15$' "BLACKOUT_TIMEOUT inválido voltou para 15"
check_contains "$TMP/invalid.out" '^ADB_TIMEOUT=4$' "ADB_TIMEOUT inválido voltou para 4"
check_contains "$TMP/invalid.out" '^POLL_INTERVAL=2$' "POLL_INTERVAL inválido voltou para 2"
check_contains "$TMP/invalid.err" 'inválido' "aviso de valor inválido emitido"

if run_daemon "$TMP/invalid.conf" --check-config "$TMP/bad.out" "$TMP/bad.err"; then
  bad "--check-config aceitou configuração inválida"
else
  ok "--check-config rejeita configuração inválida"
fi

# ---------------------------------------------------------------------------
# 3. Arquivo ausente: usa defaults e não falha.
# ---------------------------------------------------------------------------
if run_daemon "$TMP/nao-existe.conf" --dump-config "$TMP/missing.out" "$TMP/missing.err"; then
  ok "arquivo ausente não gera erro"
else
  bad "arquivo ausente gerou erro"
fi
check_contains "$TMP/missing.out" '^METHOD=auto$' "default METHOD=auto sem arquivo"
check_contains "$TMP/missing.out" '^RESOLUTION=auto$' "default RESOLUTION=auto sem arquivo"
check_contains "$TMP/missing.out" '^POLL_INTERVAL=2$' "default POLL_INTERVAL=2 sem arquivo"
check_contains "$TMP/missing.err" 'não encontrado' "aviso de arquivo ausente emitido"

# ---------------------------------------------------------------------------
# 4. Inteiros com zero à esquerda são normalizados (não viram octal).
# ---------------------------------------------------------------------------
cat >"$TMP/zeros.conf" <<'CFG'
DPI=0160
FPS=015
BLACKOUT_TIMEOUT=015
ADB_TIMEOUT=04
POLL_INTERVAL=02
LOG_MAX_BYTES=01048576
LOG_KEEP=05
CFG

run_daemon "$TMP/zeros.conf" --dump-config "$TMP/zeros.out" "$TMP/zeros.err"
check_contains "$TMP/zeros.out" '^DPI=160$' "DPI com zero à esquerda normalizado"
check_contains "$TMP/zeros.out" '^FPS=15$' "FPS com zero à esquerda normalizado"
check_contains "$TMP/zeros.out" '^BLACKOUT_TIMEOUT=15$' "BLACKOUT_TIMEOUT normalizado"
check_contains "$TMP/zeros.out" '^ADB_TIMEOUT=4$' "ADB_TIMEOUT normalizado"
check_contains "$TMP/zeros.out" '^POLL_INTERVAL=2$' "POLL_INTERVAL normalizado"
check_contains "$TMP/zeros.out" '^LOG_MAX_BYTES=1048576$' "LOG_MAX_BYTES normalizado"
check_contains "$TMP/zeros.out" '^LOG_KEEP=5$' "LOG_KEEP normalizado"

# ---------------------------------------------------------------------------
# 5. O template entregue em etc/rios/config é válido.
# ---------------------------------------------------------------------------
if run_daemon "${ROOT}/etc/rios/config" --check-config "$TMP/tpl.out" "$TMP/tpl.err"; then
  ok "template etc/rios/config é válido"
else
  bad "template etc/rios/config é inválido"
  cat "$TMP/tpl.err" >&2 || true
fi

# ---------------------------------------------------------------------------
# 6. Argumento inválido de linha de comando.
# ---------------------------------------------------------------------------
if RIOS_LOG_DIR="$TMP/log" RIOS_STATE_DIR="$TMP/run" \
     "$DAEMON" --max-cycles abc >/dev/null 2>&1; then
  bad "--max-cycles inválido foi aceito"
else
  ok "--max-cycles inválido é rejeitado"
fi

printf '\n%d ok, %d falha(s)\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
