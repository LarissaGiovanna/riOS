#!/usr/bin/env bash
# =============================================================================
# scripts/coleta-bancada.sh — coleta rápida de evidências para T3–T7 (M2)
#
# Registra em docs/revisao-p2.md ou docs/ambiente-de-testes.md:
#   - Modelo do Galaxy, versão do Android, One UI, build
#   - Versão do adb e do scrcpy presentes no sistema
#   - Estado atual de adb devices
#   - Flags aceitas pelo scrcpy (verifica --new-display, --max-fps, etc.)
#   - Log do rios-session e do scrcpy (últimas 100 linhas)
#
# Uso:
#   ./scripts/coleta-bancada.sh [--saida ARQUIVO]
#
# Requisitos: adb e scrcpy instalados; celular conectado e autorizado.
# Roda sem root.
# =============================================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SAIDA="${1:-}"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

if [[ -z "$SAIDA" ]]; then
  SAIDA="$ROOT/docs/coleta-bancada-${TIMESTAMP}.md"
fi

ADB_TIMEOUT=5

adb_cmd() {
  if command -v timeout &>/dev/null; then
    timeout "$ADB_TIMEOUT" adb "$@" 2>/dev/null || true
  else
    adb "$@" 2>/dev/null || true
  fi
}

{
  printf '# Coleta de bancada — %s\n\n' "$(date '+%d/%m/%Y %H:%M:%S')"
  printf '**Script:** `scripts/coleta-bancada.sh`\n'
  printf '**Host:** %s / %s\n\n' "$(uname -n)" "$(uname -r)"
  printf '---\n\n'

  # --- 1. Ferramentas instaladas
  printf '## 1. Versões das ferramentas\n\n'
  printf '```\n'
  if command -v adb &>/dev/null; then
    adb version 2>/dev/null || printf 'adb: erro ao obter versão\n'
  else
    printf 'adb: NÃO ENCONTRADO\n'
  fi
  if command -v scrcpy &>/dev/null; then
    scrcpy --version 2>/dev/null || printf 'scrcpy: erro ao obter versão\n'
  else
    printf 'scrcpy: NÃO ENCONTRADO\n'
  fi
  printf '```\n\n'

  # --- 2. Flags do scrcpy (verificação do T4 / issue #6)
  printf '## 2. Flags do scrcpy presentes (checagem do método A)\n\n'
  if command -v scrcpy &>/dev/null; then
    HELP_OUT="$(scrcpy --help 2>&1 || true)"
    for FLAG in '--new-display' '--render-driver' '--max-fps' '--video-bit-rate' '--no-audio' '--turn-screen-off' '--keep-active' '--keyboard' '--mouse'; do
      if printf '%s' "$HELP_OUT" | grep -q -- "$FLAG"; then
        printf '- [x] `%s`\n' "$FLAG"
      else
        printf '- [ ] `%s` ← **AUSENTE** — método A vai falhar; usar fallback B\n' "$FLAG"
      fi
    done
  else
    printf '> scrcpy não encontrado — instale antes da bancada.\n'
  fi
  printf '\n'

  # --- 3. Estado do adb devices
  printf '## 3. Estado do adb devices\n\n'
  printf '```\n'
  adb_cmd devices
  printf '```\n\n'

  # --- 4. Dados do Galaxy (T3 / issue #5)
  printf '## 4. Dados do aparelho (Galaxy)\n\n'
  if command -v adb &>/dev/null; then
    DEVICE_LINE="$(adb_cmd devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
    if [[ -n "$DEVICE_LINE" ]]; then
      SERIAL="$DEVICE_LINE"
      printf '**Serial:** `%s`\n\n' "$SERIAL"
      printf '```\n'
      printf 'Modelo:        %s\n' "$(adb_cmd -s "$SERIAL" shell getprop ro.product.model)"
      printf 'Fabricante:    %s\n' "$(adb_cmd -s "$SERIAL" shell getprop ro.product.manufacturer)"
      printf 'Android:       %s\n' "$(adb_cmd -s "$SERIAL" shell getprop ro.build.version.release)"
      printf 'SDK:           %s\n' "$(adb_cmd -s "$SERIAL" shell getprop ro.build.version.sdk)"
      printf 'One UI:        %s\n' "$(adb_cmd -s "$SERIAL" shell getprop ro.build.version.oneui)"
      printf 'Build:         %s\n' "$(adb_cmd -s "$SERIAL" shell getprop ro.build.display.id)"
      printf 'Resolução:     %s\n' "$(adb_cmd -s "$SERIAL" shell wm size)"
      printf 'DPI:           %s\n' "$(adb_cmd -s "$SERIAL" shell wm density)"
      printf '```\n\n'

      # Verificação de Android 15+ (exigido pelo --new-display)
      ANDROID_VER="$(adb_cmd -s "$SERIAL" shell getprop ro.build.version.sdk | tr -d '[:space:]')"
      printf '**Android SDK %s:**' "$ANDROID_VER"
      if [[ "$ANDROID_VER" =~ ^[0-9]+$ ]] && (( ANDROID_VER >= 35 )); then
        printf ' ✅ SDK ≥ 35 (Android 15+) — `--new-display` compatível.\n\n'
      else
        printf ' ⚠️  SDK < 35 — `--new-display` pode não funcionar; método A pode falhar.\n\n'
      fi

      # Verificar tela bloqueada (T3 §9.1 do PLAN)
      printf '**Tela bloqueada (dumpsys window)?** '
      LOCKED_OUT="$(adb_cmd -s "$SERIAL" shell dumpsys window | tr -d '\r' || true)"
      if printf '%s' "$LOCKED_OUT" | grep -Eq 'mDreamingLockscreen=true|mShowingLockscreen=true|mKeyguardShowing=true|isStatusBarKeyguard=true'; then
        printf '🔒 **SIM — celular bloqueado**. O daemon mostrará "Desbloqueie o celular".\n\n'
      else
        printf '🔓 Não (celular desbloqueado ou resultado indisponível).\n\n'
      fi
    else
      printf '> Nenhum aparelho no estado `device`. Conecte o Galaxy e aceite a chave RSA.\n\n'
    fi
  else
    printf '> `adb` não encontrado — instale `android-tools` antes da bancada.\n\n'
  fi

  # --- 5. overlay_display_devices (cleanup do T6)
  printf '## 5. overlay_display_devices (cleanup T6)\n\n'
  printf '```\n'
  if [[ -n "${SERIAL:-}" ]]; then
    VAL="$(adb_cmd -s "${SERIAL}" shell settings get global overlay_display_devices || true)"
    printf 'overlay_display_devices = %s\n' "${VAL:-n/d}"
  else
    printf 'Aparelho não conectado — não verificado.\n'
  fi
  printf '```\n\n'

  # --- 6. Logs do rios-session
  printf '## 6. Últimas 100 linhas do rios-session.log\n\n'
  LOG_DIR="${RIOS_LOG_DIR:-}"
  if [[ -z "$LOG_DIR" ]]; then
    if [[ -f "/var/log/rios/rios-session.log" ]]; then
      LOG_DIR="/var/log/rios"
    elif [[ -n "${XDG_STATE_HOME:-}" ]] && [[ -f "${XDG_STATE_HOME}/rios/log/rios-session.log" ]]; then
      LOG_DIR="${XDG_STATE_HOME}/rios/log"
    elif [[ -f "${HOME:-/root}/.local/state/rios/log/rios-session.log" ]]; then
      LOG_DIR="${HOME}/.local/state/rios/log"
    fi
  fi
  if [[ -n "$LOG_DIR" ]] && [[ -f "${LOG_DIR}/rios-session.log" ]]; then
    printf '```\n'
    tail -n 100 "${LOG_DIR}/rios-session.log"
    printf '```\n\n'
  else
    printf '> Log não encontrado em `%s`. Inicie o daemon primeiro.\n\n' "${LOG_DIR:-/var/log/rios}"
  fi

  printf '---\n\n'
  printf '**Arquivo gerado:** `%s`\n' "$SAIDA"
  printf '\n> Coloque o resultado em `docs/ambiente-de-testes.md` ou `docs/revisao-p2.md` após a bancada.\n'

} > "$SAIDA"

printf 'Coleta salva em: %s\n' "$SAIDA"
printf 'Próximo passo: commitar em docs/ após a sessão de bancada.\n'
