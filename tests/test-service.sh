#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="${ROOT}/scripts/install-runtime.sh"
LAUNCH="${ROOT}/runtime/rios-launch"
UNIT_SRC="${ROOT}/runtime/systemd/rios-session.service"
WAIT_SRC="${ROOT}/runtime/systemd/wait-display.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rios-test-service.XXXXXX")"
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ok()  { PASS=$(( PASS + 1 )); printf '  ok   %s\n' "$*"; }
bad() { FAIL=$(( FAIL + 1 )); printf '  FALHA %s\n' "$*"; }

check_file() {
  local file="$1" label="$2"
  if [[ -f "$file" ]]; then ok "$label"; else bad "$label (não existe: $file)"; fi
}

check_exec() {
  local file="$1" label="$2"
  if [[ -x "$file" ]]; then ok "$label"; else bad "$label (não executável: $file)"; fi
}

check_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -q -- "$pattern" "$file" 2>/dev/null; then
    ok "$label"
  else
    bad "$label (não encontrado: $pattern)"
  fi
}

check_absent() {
  local file="$1" label="$2"
  if [[ ! -e "$file" ]]; then ok "$label"; else bad "$label (ainda existe: $file)"; fi
}

printf 'test-service\n'

export PATH="${ROOT}/tests/mock:${PATH}"
export MOCK_SYSTEMCTL_LOG="$TMP/systemctl.log"
export MOCK_JOURNAL_LOG="$TMP/journalctl.log"
export MOCK_SYSTEMCTL_ACTIVE=1
export MOCK_SYSTEMCTL_UNIT=both

TARGET_USER="$(id -un)"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [[ -x "$INSTALL" ]]; then
  ok "instalador é executável"
else
  bad "instalador sem bit de execução"
fi

if [[ -f "$UNIT_SRC" ]]; then
  ok "unidade systemd existe"
else
  bad "unidade systemd não encontrada"
fi

check_contains "$UNIT_SRC" '^Type=simple' "unidade usa Type=simple"
check_contains "$UNIT_SRC" '^ExecStart=/usr/local/bin/rios-session' "unidade chama rios-session instalado"
check_contains "$UNIT_SRC" '^ExecStartPre=/usr/local/lib/rios/wait-display.sh' "unidade espera a sessão X"
check_contains "$UNIT_SRC" '^Restart=on-failure' "unidade reinicia em falha"
check_contains "$UNIT_SRC" '^WantedBy=default.target' "unidade sobe com o usuário"

check_exec "$WAIT_SRC" "wait-display.sh é executável"
if sh -n "$WAIT_SRC"; then
  ok "wait-display.sh tem sintaxe válida"
else
  bad "wait-display.sh tem erro de sintaxe"
fi

if "$INSTALL" --help >"$TMP/help" 2>&1; then
  ok "--help termina com 0"
else
  bad "--help retornou erro"
fi
check_contains "$TMP/help" '--destdir' "--help documenta --destdir"
check_contains "$TMP/help" '--uninstall' "--help documenta --uninstall"

DEST="$TMP/dest"
UNIT="$DEST${TARGET_HOME}/.config/systemd/user/rios-session.service"

if "$INSTALL" --user "$TARGET_USER" --destdir "$DEST" --no-enable \
        >"$TMP/install.out" 2>&1; then
  ok "instalação em --destdir termina com 0"
else
  bad "instalação em --destdir falhou"
  cat "$TMP/install.out" >&2 || true
fi

check_exec "$DEST/usr/local/bin/rios-session" "rios-session instalado"
check_exec "$DEST/usr/local/bin/rios-launch" "rios-launch instalado"
check_exec "$DEST/usr/local/bin/rios-wait-screen/setup.sh" "tela de espera instalada"
check_exec "$DEST/usr/local/lib/rios/wait-display.sh" "wait-display instalado"
check_file "$DEST/etc/rios/config" "config instalado"
check_file "$UNIT" "unidade instalada no usuário"
check_contains "$UNIT" '^ExecStart=/usr/local/bin/rios-session' "unidade instalada aponta para o binário"

printf '# marcador local\n' >>"$DEST/etc/rios/config"
if "$INSTALL" --user "$TARGET_USER" --destdir "$DEST" --no-enable \
        >"$TMP/install2.out" 2>&1; then
  ok "reinstalação termina com 0"
else
  bad "reinstalação falhou"
fi
check_contains "$DEST/etc/rios/config" '# marcador local' "config existente preservado"

if "$INSTALL" --user "$TARGET_USER" --destdir "$DEST" --no-enable --force-config \
        >"$TMP/install3.out" 2>&1; then
  ok "--force-config termina com 0"
else
  bad "--force-config falhou"
fi
if grep -q '# marcador local' "$DEST/etc/rios/config" 2>/dev/null; then
  bad "--force-config não sobrescreveu o config"
else
  ok "--force-config sobrescreveu o config"
fi

DRY="$TMP/dry"
if "$INSTALL" --user "$TARGET_USER" --destdir "$DRY" --dry-run \
        >"$TMP/dry.out" 2>&1; then
  ok "--dry-run termina com 0"
else
  bad "--dry-run falhou"
fi
check_absent "$DRY/usr" "--dry-run não criou binários"
check_absent "$DRY/etc" "--dry-run não criou config"

if "$INSTALL" --user "$TARGET_USER" --destdir "$DEST" --no-enable --uninstall \
        >"$TMP/uninstall.out" 2>&1; then
  ok "--uninstall termina com 0"
else
  bad "--uninstall falhou"
fi
check_absent "$DEST/usr/local/bin/rios-session" "--uninstall remove rios-session"
check_absent "$DEST/usr/local/bin/rios-launch" "--uninstall remove rios-launch"
check_absent "$UNIT" "--uninstall remove a unidade"
check_file "$DEST/etc/rios/config" "--uninstall preserva o config"

if "$INSTALL" --user "$TARGET_USER" --destdir "$DEST" --no-enable --uninstall --purge \
        >"$TMP/purge.out" 2>&1; then
  ok "--uninstall --purge termina com 0"
else
  bad "--uninstall --purge falhou"
fi
check_absent "$DEST/etc/rios/config" "--purge remove o config"

CLI_CONFIG="$TMP/cli/config"
CLI_LOG="$TMP/cli/log"
CLI_RUN="$TMP/cli/run"
mkdir -p "$CLI_LOG" "$CLI_RUN"
: >"$CLI_CONFIG"

export RIOS_CONFIG="$CLI_CONFIG"
export RIOS_LOG_DIR="$CLI_LOG"
export RIOS_STATE_DIR="$CLI_RUN"
export RIOS_INIT=systemd
export RIOS_SERVICE_SCOPE=user

: >"$MOCK_SYSTEMCTL_LOG"
if "$LAUNCH" status >"$TMP/status-user.out" 2>&1; then
  ok "status systemd/usuário termina com 0"
else
  bad "status systemd/usuário falhou"
fi
check_contains "$TMP/status-user.out" 'Serviço........: ativo (usuário)' "status mostra serviço de usuário ativo"
check_contains "$MOCK_SYSTEMCTL_LOG" '--user is-active --quiet rios-session' "status consulta systemctl --user"

: >"$MOCK_SYSTEMCTL_LOG"
if MOCK_SYSTEMCTL_ACTIVE=0 "$LAUNCH" start >"$TMP/start-user.out" 2>&1; then
  ok "start systemd/usuário termina com 0"
else
  bad "start systemd/usuário falhou"
fi
check_contains "$TMP/start-user.out" 'iniciado via systemd (rios-session, user)' "start informa systemd/usuário"
check_contains "$MOCK_SYSTEMCTL_LOG" '--user start rios-session' "start usa systemctl --user"

: >"$MOCK_SYSTEMCTL_LOG"
if "$LAUNCH" stop >"$TMP/stop-user.out" 2>&1; then
  ok "stop systemd/usuário termina com 0"
else
  bad "stop systemd/usuário falhou"
fi
check_contains "$TMP/stop-user.out" 'encerrado via systemd (user)' "stop informa systemd/usuário"
check_contains "$MOCK_SYSTEMCTL_LOG" '--user stop rios-session' "stop usa systemctl --user"

rm -f "$CLI_LOG/rios-session.log"
: >"$MOCK_JOURNAL_LOG"
if "$LAUNCH" logs >"$TMP/logs-user.out" 2>&1; then
  ok "logs systemd/usuário termina com 0"
else
  bad "logs systemd/usuário falhou"
fi
check_contains "$MOCK_JOURNAL_LOG" '--user -u rios-session -n 100' "logs usa journalctl --user"

: >"$MOCK_SYSTEMCTL_LOG"
if RIOS_SERVICE_SCOPE=system "$LAUNCH" status >"$TMP/status-system.out" 2>&1; then
  ok "status systemd/sistema termina com 0"
else
  bad "status systemd/sistema falhou"
fi
check_contains "$TMP/status-system.out" 'Serviço........: ativo (sistema)' "status mostra serviço de sistema ativo"
check_contains "$MOCK_SYSTEMCTL_LOG" 'is-active --quiet rios-session' "status consulta systemctl de sistema"
if grep -q -- '--user is-active' "$MOCK_SYSTEMCTL_LOG" 2>/dev/null; then
  bad "status de sistema usou --user"
else
  ok "status de sistema não usou --user"
fi

if RIOS_SERVICE_SCOPE=none "$LAUNCH" status >"$TMP/status-none.out" 2>&1; then
  ok "status sem unidade termina com 0"
else
  bad "status sem unidade falhou"
fi
check_contains "$TMP/status-none.out" 'Serviço........: não instalado' "status informa unidade ausente"

printf '\n%d ok, %d falha(s)\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
