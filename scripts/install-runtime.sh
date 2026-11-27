#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SERVICE="rios-session"

TARGET_USER="${SUDO_USER:-$(id -un)}"
USER_EXPLICIT=0
DESTDIR=""
DRY_RUN=0
ENABLE=1
UNINSTALL=0
PURGE=0
FORCE_CONFIG=0

info() { printf '%s\n' "$*"; }
aviso() { printf 'aviso: %s\n' "$*" >&2; }
erro() { printf 'erro: %s\n' "$*" >&2; exit 1; }

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

uso() {
  cat <<'FIM'
install-runtime.sh — instala o runtime e o serviço do riOS

Uso:
  sudo scripts/install-runtime.sh [opções]

Opções:
  --user NOME        usuário da sessão gráfica (padrão: SUDO_USER ou usuário atual)
  --destdir DIR      instala sob DIR (para testes; não mexe no sistema)
  --dry-run, -n      mostra o que seria feito, sem alterar nada
  --no-enable        instala sem habilitar/iniciar o serviço
  --uninstall        remove runtime e unidade do serviço
  --purge            com --uninstall, remove também /etc/rios/config
  --force-config     sobrescreve /etc/rios/config existente
  -h, --help         mostra esta ajuda
FIM
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --user)
      [ "$#" -ge 2 ] || erro "--user exige um nome"
      TARGET_USER="$2"
      USER_EXPLICIT=1
      shift 2
      ;;
    --user=*)
      TARGET_USER="${1#*=}"
      USER_EXPLICIT=1
      shift
      ;;
    --destdir)
      [ "$#" -ge 2 ] || erro "--destdir exige um caminho"
      DESTDIR="${2%/}"
      shift 2
      ;;
    --destdir=*)
      DESTDIR="${1#*=}"
      DESTDIR="${DESTDIR%/}"
      shift
      ;;
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --no-enable)
      ENABLE=0
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    --purge)
      PURGE=1
      shift
      ;;
    --force-config)
      FORCE_CONFIG=1
      shift
      ;;
    -h|--help)
      uso
      exit 0
      ;;
    *)
      erro "opção desconhecida: $1"
      ;;
  esac
done

if [ "$PURGE" -eq 1 ] && [ "$UNINSTALL" -eq 0 ]; then
  erro "--purge só pode ser usado com --uninstall"
fi

if ! getent passwd "$TARGET_USER" >/dev/null 2>&1; then
  erro "usuário não existe: $TARGET_USER"
fi

if [ "$(id -u)" -eq 0 ] && [ "$USER_EXPLICIT" -eq 0 ] && [ "$TARGET_USER" = "root" ]; then
  erro "rode como o usuário da sessão ou informe --user NOME"
fi

if [ -z "$DESTDIR" ] && [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  erro "instalação no sistema exige root; use sudo, --destdir ou --dry-run"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
TARGET_UID="$(id -u "$TARGET_USER")"

BIN_DIR="${DESTDIR}/usr/local/bin"
LIB_DIR="${DESTDIR}/usr/local/lib/rios"
CONFIG_DIR="${DESTDIR}/etc/rios"
UNIT_DIR="${DESTDIR}${TARGET_HOME}/.config/systemd/user"
WANTS_DIR="${UNIT_DIR}/default.target.wants"

user_systemctl() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ systemctl --user'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  if [ "$(id -u)" -eq 0 ]; then
    runuser -u "$TARGET_USER" -- env \
      XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
      systemctl --user "$@"
  else
    XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" systemctl --user "$@"
  fi
}

habilitar_unidade() {
  if [ -n "$DESTDIR" ] || [ "$ENABLE" -eq 0 ]; then
    return 0
  fi

  if user_systemctl show-environment >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
      user_systemctl daemon-reload
      user_systemctl enable --now "$SERVICE"
      info "serviço seria habilitado e iniciado para ${TARGET_USER}"
      return 0
    fi
    user_systemctl daemon-reload || true
    if user_systemctl enable --now "$SERVICE"; then
      info "serviço habilitado e iniciado para ${TARGET_USER}"
      return 0
    fi
    aviso "não consegui iniciar o serviço agora; habilitando para o próximo login"
  else
    aviso "sessão systemd --user não está ativa; habilitando para o próximo login"
  fi

  run_cmd mkdir -p "$WANTS_DIR"
  run_cmd ln -sfn "../${SERVICE}.service" "${WANTS_DIR}/${SERVICE}.service"
  info "unidade habilitada em ${WANTS_DIR}/${SERVICE}.service"
}

desabilitar_unidade() {
  if [ -n "$DESTDIR" ]; then
    run_cmd rm -f "${WANTS_DIR}/${SERVICE}.service"
    run_cmd rm -f "${UNIT_DIR}/${SERVICE}.service"
    return 0
  fi

  if [ "$ENABLE" -eq 1 ] && user_systemctl show-environment >/dev/null 2>&1; then
    user_systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
    user_systemctl daemon-reload >/dev/null 2>&1 || true
  fi
  run_cmd rm -f "${WANTS_DIR}/${SERVICE}.service"
  run_cmd rm -f "${UNIT_DIR}/${SERVICE}.service"
}

ajustar_grupos() {
  if [ -n "$DESTDIR" ]; then
    return 0
  fi
  if [ "$(id -u)" -ne 0 ]; then
    aviso "sem root: não alterei os grupos de ${TARGET_USER}"
    return 0
  fi

  local grupos_atual
  local grupos_alterados=0
  grupos_atual=" $(id -nG "$TARGET_USER" | tr ' ' '\n' | tr '\n' ' ') "
  for grupo in audio video input; do
    getent group "$grupo" >/dev/null 2>&1 || continue
    case "$grupos_atual" in
      *" $grupo "*) ;;
      *)
        run_cmd usermod -aG "$grupo" "$TARGET_USER"
        grupos_alterados=1
        ;;
    esac
  done
  if [ "$grupos_alterados" -eq 1 ]; then
    info "grupos atualizados; faça logout/login para valerem na sessão"
  fi
}

instalar() {
  [ -f "${ROOT}/runtime/rios-session" ] || erro "runtime/rios-session não encontrado"
  [ -f "${ROOT}/runtime/rios-launch" ] || erro "runtime/rios-launch não encontrado"
  [ -f "${ROOT}/runtime/systemd/rios-session.service" ] || erro "unidade systemd não encontrada"
  [ -f "${ROOT}/runtime/systemd/wait-display.sh" ] || erro "wait-display.sh não encontrado"
  [ -d "${ROOT}/runtime/rios-wait-screen" ] || erro "rios-wait-screen não encontrado"

  run_cmd install -D -m 0755 "${ROOT}/runtime/rios-session" "${BIN_DIR}/rios-session"
  run_cmd install -D -m 0755 "${ROOT}/runtime/rios-launch" "${BIN_DIR}/rios-launch"
  run_cmd install -D -m 0755 "${ROOT}/runtime/systemd/wait-display.sh" "${LIB_DIR}/wait-display.sh"
  run_cmd install -d -m 0755 "${BIN_DIR}/rios-wait-screen"
  run_cmd cp -a "${ROOT}/runtime/rios-wait-screen/." "${BIN_DIR}/rios-wait-screen/"

  if [ "$DRY_RUN" -eq 0 ]; then
    chmod 0755 "${BIN_DIR}/rios-wait-screen/setup.sh"
    for atalho in "${BIN_DIR}/rios-wait-screen/"*.desktop; do
      [ -e "$atalho" ] && chmod 0644 "$atalho"
    done
  fi

  run_cmd install -d -m 0755 "$CONFIG_DIR"
  if [ -f "${CONFIG_DIR}/config" ] && [ "$FORCE_CONFIG" -eq 0 ]; then
    info "config existente preservado: ${CONFIG_DIR}/config"
  else
    run_cmd install -m 0644 "${ROOT}/etc/rios/config" "${CONFIG_DIR}/config"
  fi

  run_cmd install -d -m 0755 "$UNIT_DIR"
  run_cmd install -m 0644 "${ROOT}/runtime/systemd/rios-session.service" "${UNIT_DIR}/${SERVICE}.service"

  if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -eq 0 ]; then
    chown "$TARGET_USER:$TARGET_GROUP" "$UNIT_DIR"
    chown "$TARGET_USER:$TARGET_GROUP" "${UNIT_DIR}/${SERVICE}.service"
  fi

  ajustar_grupos
  habilitar_unidade

  if [ "$DRY_RUN" -eq 1 ]; then
    info "runtime seria instalado em ${BIN_DIR}"
    info "configuração em ${CONFIG_DIR}/config"
    info "unidade em ${UNIT_DIR}/${SERVICE}.service"
  else
    info "runtime instalado em ${BIN_DIR}"
    info "configuração em ${CONFIG_DIR}/config"
    info "unidade em ${UNIT_DIR}/${SERVICE}.service"
  fi

  if [ "$ENABLE" -eq 1 ] && [ -z "$DESTDIR" ] && [ "$DRY_RUN" -eq 0 ]; then
    info "verifique com: systemctl --user status ${SERVICE}"
    info "e também:      rios-launch status"
  fi
}

desinstalar() {
  desabilitar_unidade

  run_cmd rm -f "${BIN_DIR}/rios-session"
  run_cmd rm -f "${BIN_DIR}/rios-launch"
  run_cmd rm -rf "${BIN_DIR}/rios-wait-screen"
  run_cmd rm -f "${LIB_DIR}/wait-display.sh"
  if [ "$DRY_RUN" -eq 0 ]; then
    rmdir "$LIB_DIR" 2>/dev/null || true
  fi

  if [ "$PURGE" -eq 1 ]; then
    run_cmd rm -f "${CONFIG_DIR}/config"
    if [ "$DRY_RUN" -eq 0 ]; then
      rmdir "$CONFIG_DIR" 2>/dev/null || true
    fi
  fi

  info "runtime removido"
}

if [ "$UNINSTALL" -eq 1 ]; then
  desinstalar
else
  instalar
fi
