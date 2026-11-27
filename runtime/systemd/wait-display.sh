#!/bin/sh
# Espera a sessão gráfica ficar disponível antes de iniciar o rios-session.
# O serviço de usuário herda DISPLAY/XAUTHORITY do systemd --user; este script
# cobre a corrida com o LXQt no login.

set -u

: "${DISPLAY:=:0}"
export DISPLAY

tela="${DISPLAY#:}"
tela="${tela%%.*}"

tentativa=0
while [ "$tentativa" -lt 30 ]; do
    if command -v xset >/dev/null 2>&1; then
        xset q >/dev/null 2>&1 && exit 0
    elif [ -S "/tmp/.X11-unix/X${tela}" ]; then
        exit 0
    fi
    tentativa=$((tentativa + 1))
    sleep 1
done

printf 'rios-session: DISPLAY=%s indisponível após 30s\n' "$DISPLAY" >&2
exit 1
