#!/usr/bin/env bash
# =============================================================================
# rios-wait-screen/setup.sh — gera e aplica a tela de espera do riOS
#
# Gera um papel de parede 1024x600 com instruções em português:
#   - PNG via ImageMagick (magick/convert), quando disponível;
#   - SVG + TXT como alternativa sem dependências.
#
# Uso:
#   ./setup.sh                    gera os arquivos
#   ./setup.sh --apply            gera e aplica o papel de parede
#   ./setup.sh --install-shortcuts copia os atalhos para ~/Desktop
#
# Variáveis: RIOS_WAIT_MESSAGE (mensagem dinâmica), RIOS_WAIT_SCREEN_OUT
# (diretório de saída).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
WIDTH=1024
HEIGHT=600
BG="#0f1720"
FG="#e6edf3"
ACCENT="#4cc2ff"
MUTED="#8b949e"
MESSAGE="${RIOS_WAIT_MESSAGE:-Conecte o celular Samsung por USB}"

APPLY=0
INSTALL_SHORTCUTS=0

# Processa os argumentos.
parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --apply) APPLY=1; shift ;;
      --install-shortcuts) INSTALL_SHORTCUTS=1; shift ;;
      -h|--help)
        sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
      *) printf 'argumento desconhecido: %s\n' "$1" >&2; exit 2 ;;
    esac
  done
}

# Escolhe um diretório de saída gravável.
resolve_out_dir() {
  if [[ -n "${RIOS_WAIT_SCREEN_OUT:-}" ]]; then
    OUT_DIR="$RIOS_WAIT_SCREEN_OUT"
  else
    OUT_DIR=""
    local cand
    for cand in /var/lib/rios/wait-screen "${TMPDIR:-/tmp}/rios-wait-screen"; do
      if mkdir -p "$cand" 2>/dev/null && [[ -w "$cand" ]]; then
        OUT_DIR="$cand"
        break
      fi
    done
    if [[ -z "$OUT_DIR" ]]; then
      printf 'erro: nenhum diretório gravável para a tela de espera\n' >&2
      exit 1
    fi
  fi
  mkdir -p "$OUT_DIR"
}

# Escreve o arquivo de texto com as instruções (fallback sem ImageMagick).
write_text() {
  cat >"$TEXT_FILE" <<TXT
============================================================
 riOS — Estação DeX
============================================================

 $MESSAGE

 COMO CONECTAR
 1. Ligue o cabo USB entre o celular Samsung e o netbook.
 2. Desbloqueie o celular.
 3. Autorize a depuração USB quando o aviso aparecer.
 4. Aguarde: o DeX abre automaticamente em tela cheia.

 ATALHOS
 - Terminal de manutenção: Alt+T ou o atalho "Terminal".
 - Reiniciar a sessão: atalho "Reiniciar sessão" ou:
     rios-launch restart

 DIAGNÓSTICO
 - Status:   rios-launch status
 - Logs:     rios-launch logs -f
 - Parar:    rios-launch stop

 Se a tela ficar preta, pressione Ctrl+Alt+F2 para um TTY.
============================================================
TXT
}

# Escapa caracteres especiais para uso dentro do SVG.
xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

# Escreve um SVG equivalente (não depende de ImageMagick).
write_svg() {
  local msg
  msg="$(xml_escape "$MESSAGE")"
  cat >"$SVG_FILE" <<SVG
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${HEIGHT}" viewBox="0 0 ${WIDTH} ${HEIGHT}">
  <rect width="${WIDTH}" height="${HEIGHT}" fill="${BG}"/>
  <rect x="0" y="0" width="${WIDTH}" height="8" fill="${ACCENT}"/>
  <g font-family="DejaVu Sans, Liberation Sans, sans-serif" text-anchor="middle">
    <text x="512" y="120" font-size="68" font-weight="bold" fill="${ACCENT}">riOS</text>
    <text x="512" y="165" font-size="22" fill="${MUTED}">Estação DeX — o netbook vira terminal do celular</text>
    <text x="512" y="250" font-size="30" fill="${FG}">1. Conecte o celular Samsung por USB</text>
    <text x="512" y="305" font-size="30" fill="${FG}">2. Desbloqueie o celular</text>
    <text x="512" y="360" font-size="30" fill="${FG}">3. Autorize a depuração USB no aviso</text>
    <text x="512" y="415" font-size="30" fill="${FG}">4. Aguarde: o DeX abre automaticamente</text>
    <text x="512" y="495" font-size="24" fill="#f0b429">${msg}</text>
    <text x="512" y="560" font-size="18" fill="${MUTED}">Alt+T terminal  •  rios-launch status  •  Ctrl+Alt+F2 TTY</text>
  </g>
</svg>
SVG
}

# Renderiza o PNG com ImageMagick. Devolve 1 se o ImageMagick não existir.
render_png() {
  local -a cmd=()
  if command -v magick >/dev/null 2>&1; then
    cmd=(magick)
  elif command -v convert >/dev/null 2>&1; then
    cmd=(convert)
  else
    return 1
  fi
  local tmp="${PNG_FILE}.tmp.$$"
  if "${cmd[@]}" -size "${WIDTH}x${HEIGHT}" "xc:${BG}" \
      -fill "$ACCENT" -pointsize 64 -gravity north -annotate +0+70 "riOS" \
      -fill "$MUTED" -pointsize 20 -gravity north -annotate +0+160 "Estação DeX — o netbook vira terminal do celular" \
      -fill "$FG" -pointsize 28 -gravity north -annotate +0+245 "1. Conecte o celular Samsung por USB" \
      -fill "$FG" -pointsize 28 -gravity north -annotate +0+300 "2. Desbloqueie o celular" \
      -fill "$FG" -pointsize 28 -gravity north -annotate +0+355 "3. Autorize a depuração USB no aviso" \
      -fill "$FG" -pointsize 28 -gravity north -annotate +0+410 "4. Aguarde: o DeX abre automaticamente" \
      -fill "#f0b429" -pointsize 22 -gravity north -annotate +0+490 "$MESSAGE" \
      -fill "$MUTED" -pointsize 17 -gravity south -annotate +0+50 "Alt+T terminal  •  rios-launch status  •  Ctrl+Alt+F2 TTY" \
      "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$PNG_FILE"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Aplica o papel de parede na sessão gráfica atual, se possível.
apply_wallpaper() {
  if [[ -z "${DISPLAY:-}" ]]; then
    printf 'aviso: DISPLAY não definido; papel de parede não aplicado.\n'
    return 0
  fi
  local img=""
  [[ -f "$PNG_FILE" ]] && img="$PNG_FILE"

  if [[ -n "$img" ]] && command -v feh >/dev/null 2>&1; then
    feh --bg-fill "$img" >/dev/null 2>&1 || true
  elif [[ -n "$img" ]] && command -v xwallpaper >/dev/null 2>&1; then
    xwallpaper --zoom "$img" >/dev/null 2>&1 || true
  elif [[ -n "$img" ]] && command -v pcmanfm-qt >/dev/null 2>&1; then
    pcmanfm-qt --set-wallpaper="$img" >/dev/null 2>&1 || true
  elif [[ -n "$img" ]] && command -v pcmanfm >/dev/null 2>&1; then
    pcmanfm --set-wallpaper="$img" >/dev/null 2>&1 || true
  elif [[ -n "$img" ]] && command -v nitrogen >/dev/null 2>&1; then
    nitrogen --set-zoom-fill --save "$img" >/dev/null 2>&1 || true
  elif command -v xsetroot >/dev/null 2>&1; then
    xsetroot -solid "$BG" >/dev/null 2>&1 || true
  fi

  if command -v xsetroot >/dev/null 2>&1; then
    xsetroot -name "riOS — $MESSAGE" >/dev/null 2>&1 || true
  fi
}

# Copia os atalhos de desktop para a área de trabalho do usuário.
install_shortcuts() {
  local dest="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
  mkdir -p "$dest" 2>/dev/null || {
    printf 'aviso: não foi possível criar %s\n' "$dest" >&2
    return 0
  }
  local f
  for f in rios-terminal.desktop rios-restart.desktop; do
    if [[ -f "${SCRIPT_DIR}/${f}" ]]; then
      cp -f "${SCRIPT_DIR}/${f}" "${dest}/${f}"
      chmod +x "${dest}/${f}"
      if command -v gio >/dev/null 2>&1; then
        gio set "${dest}/${f}" metadata::trusted true >/dev/null 2>&1 || true
      fi
      printf 'atalho instalado: %s\n' "${dest}/${f}"
    fi
  done
}

# Ponto de entrada.
main() {
  parse_args "$@"
  resolve_out_dir
  TEXT_FILE="${OUT_DIR}/rios-wait.txt"
  SVG_FILE="${OUT_DIR}/rios-wait.svg"
  PNG_FILE="${OUT_DIR}/rios-wait.png"
  MESSAGE_FILE="${OUT_DIR}/message.txt"

  write_text
  write_svg

  local previous=""
  [[ -f "$MESSAGE_FILE" ]] && previous="$(cat "$MESSAGE_FILE" 2>/dev/null || true)"
  if [[ ! -f "$PNG_FILE" || "$previous" != "$MESSAGE" ]]; then
    if ! render_png; then
      printf 'aviso: ImageMagick ausente; usando SVG/TXT como tela de espera.\n'
    fi
  fi
  printf '%s\n' "$MESSAGE" >"$MESSAGE_FILE"

  if (( APPLY == 1 )); then
    apply_wallpaper
  fi
  if (( INSTALL_SHORTCUTS == 1 )); then
    install_shortcuts
  fi
  printf 'tela de espera gerada em %s\n' "$OUT_DIR"
}

main "$@"
