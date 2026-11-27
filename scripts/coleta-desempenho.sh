#!/usr/bin/env bash
# =============================================================================
# scripts/coleta-desempenho.sh — coleta a série temporal de desempenho (M6-01)
#
# Uma execução = UMA condição (C0 ou C1) + UMA repetição. Grava:
#
#   docs/medicoes/<AAAAMMDD-HHMMSS>-<C0|C1>-r<N>.csv     série amostrada
#   docs/medicoes/<AAAAMMDD-HHMMSS>-<C0|C1>-r<N>.meta.md contexto da rodada
#   docs/medicoes/indice.csv                             uma linha por rodada
#
# O protocolo (condições, métricas, fases, o que invalida uma rodada) está em
# docs/protocolo-medicoes.md — leia antes de medir.
#
# Uso:
#   ./coleta-desempenho.sh --condicao C0                     # bancada Void
#   ./coleta-desempenho.sh --condicao C1 --duracao-carga 0    # imagem na VM
#   ./coleta-desempenho.sh --condicao C0 --metodo A --repeticao 2
#   ./coleta-desempenho.sh --rapido                           # teste (~3 s)
#   ./coleta-desempenho.sh --ajuda
#
# Fases (padrão): aquecimento 5 min → repouso 30 min → carga 10 min.
# Amostragem: 1 linha de CSV a cada 5 s.
#
# Este script MEDE a sessão que já está rodando: não instala nada, não reinicia
# serviço e não abre scrcpy. Para o fps, inicie o scrcpy com --print-fps e
# aponte --log-scrcpy para o log.
#
# Roda sem root (lê /proc, /sys e, se houver, adb).
# Escrito em sintaxe POSIX (sem arrays, sem [[ ]]): roda em dash/busybox ash,
# que é o que permite testá-lo fora do Linux alvo. Não usa "set -e":
# métrica ausente não pode abortar a coleta.
# =============================================================================

set -u
export LC_NUMERIC=C
# pipefail é do bash; em dash o teste abaixo falha e o script segue sem ele.
(set -o pipefail) 2>/dev/null && set -o pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"

# ---------------------------------------------------------------- padrões

CONDICAO=""
METODO="auto"
REPETICAO=1
SAIDA="$ROOT/docs/medicoes"
SAIDA_EXPLICITA=0
CONFIG="$ROOT/etc/rios/config"

AQUECIMENTO=5
REPOUSO=30
CARGA=10
INTERVALO=5
INTERVALO_CELULAR=60

RESOLUCAO=""
FPS_ALVO=""
BITRATE=""
CODEC=""
AUDIO=""
RENDER=""
SCRCPY_VERSAO=""
LOG_SCRCPY=""

LATENCIA=""
FPS_MEDIDO=""
TEMP_AMB=""
NOTA=""
RAPIDO=0

criar_tmp() {
    # /tmp pode não existir (imagem mínima) ou TMPDIR apontar para lugar inválido.
    for _d in "${TMPDIR:-/tmp}" /tmp .; do
        [ -d "$_d" ] || continue
        _t="$(mktemp -d "$_d/rios-medicao.XXXXXX" 2>/dev/null)" && { printf '%s' "$_t"; return 0; }
    done
    _d=".medicao.$$"
    if mkdir -p "$_d" 2>/dev/null; then printf '%s' "$_d"; return 0; fi
    return 1
}

TMP="$(criar_tmp)" || {
    printf 'erro: não consegui criar diretório temporário (defina TMPDIR)\n' >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

AMOSTRA=0
CEL_ULTIMO=0
INTERROMPIDO=0
T0=0

# ---------------------------------------------------------------- utilidades

erro()  { printf 'erro: %s\n' "$*" >&2; exit 2; }
aviso() { printf 'aviso: %s\n' "$*" >&2; }
tem()   { command -v "$1" >/dev/null 2>&1; }
agora() { date +%s; }

# timeout é opcional: sem ele, o comando roda sem limite (adb pode travar).
TIMEOUT=""
tem timeout && TIMEOUT=timeout
com_timeout() { # com_timeout SEGUNDOS comando...
    _seg="$1"; shift
    if [ -n "$TIMEOUT" ]; then "$TIMEOUT" "$_seg" "$@"; else "$@"; fi
}

uso() {
    cat <<FIM
coleta-desempenho.sh — série temporal de desempenho do riOS (M6-01)

Uso: ./coleta-desempenho.sh --condicao C0|C1 [opções]

Obrigatório:
  --condicao C0|C1        C0 = bancada Void (swap em disco, sem zram, Xfce/lightdm)
                          C1 = imagem Debian (zram, LXQt/SDDM ou lightdm)

Sessão:
  --metodo auto|A|B|C     método de abertura do DeX em uso (padrão: auto)
  --repeticao N           número da repetição, 1..3 (padrão: 1)
  --saida DIR             diretório de saída (padrão: docs/medicoes)
  --config ARQ            configuração lida para o contexto (padrão: etc/rios/config)

Durações (minutos):
  --aquecimento MIN       padrão: 5   (0 desliga a fase)
  --duracao-repouso MIN   padrão: 30
  --duracao-carga MIN     padrão: 10  (0 = só repouso, caso C1 sem sessão)
  --intervalo SEG         intervalo de amostragem (padrão: 5)
  --intervalo-celular SEG intervalo da leitura de bateria do celular (padrão: 60)

Contexto da sessão (se omitido, vem de --config):
  --resolucao WxH   --fps N   --bitrate 4M   --codec h264   --audio on|off
  --render software|opengl        --scrcpy-versao X.Y
  --log-scrcpy ARQ                log do scrcpy iniciado com --print-fps

Preenchimento manual (opcional, vai para o .meta.md e para o índice):
  --latencia-ms N   --fps-medido N   --temp-ambiente C   --nota "texto"

Atalhos:
  --rapido                fases de 2 s, para testar o script (NÃO mede nada)
  --ajuda, -h             esta ajuda

Saída: exit 0 = coleta gravada (mesmo parcial); 2 = erro de uso.
FIM
}

# ---------------------------------------------------------------- argumentos

while [ $# -gt 0 ]; do
    case "$1" in
        --condicao)          [ $# -ge 2 ] || erro "falta valor em --condicao"; CONDICAO="$2"; shift 2 ;;
        --metodo)            [ $# -ge 2 ] || erro "falta valor em --metodo"; METODO="$2"; shift 2 ;;
        --repeticao)         [ $# -ge 2 ] || erro "falta valor em --repeticao"; REPETICAO="$2"; shift 2 ;;
        --saida)             [ $# -ge 2 ] || erro "falta valor em --saida"; SAIDA="$2"; SAIDA_EXPLICITA=1; shift 2 ;;
        --config)            [ $# -ge 2 ] || erro "falta valor em --config"; CONFIG="$2"; shift 2 ;;
        --aquecimento)       [ $# -ge 2 ] || erro "falta valor em --aquecimento"; AQUECIMENTO="$2"; shift 2 ;;
        --duracao-repouso)   [ $# -ge 2 ] || erro "falta valor em --duracao-repouso"; REPOUSO="$2"; shift 2 ;;
        --duracao-carga)     [ $# -ge 2 ] || erro "falta valor em --duracao-carga"; CARGA="$2"; shift 2 ;;
        --intervalo)         [ $# -ge 2 ] || erro "falta valor em --intervalo"; INTERVALO="$2"; shift 2 ;;
        --intervalo-celular) [ $# -ge 2 ] || erro "falta valor em --intervalo-celular"; INTERVALO_CELULAR="$2"; shift 2 ;;
        --resolucao)         [ $# -ge 2 ] || erro "falta valor em --resolucao"; RESOLUCAO="$2"; shift 2 ;;
        --fps)               [ $# -ge 2 ] || erro "falta valor em --fps"; FPS_ALVO="$2"; shift 2 ;;
        --bitrate)           [ $# -ge 2 ] || erro "falta valor em --bitrate"; BITRATE="$2"; shift 2 ;;
        --codec)             [ $# -ge 2 ] || erro "falta valor em --codec"; CODEC="$2"; shift 2 ;;
        --audio)             [ $# -ge 2 ] || erro "falta valor em --audio"; AUDIO="$2"; shift 2 ;;
        --render)            [ $# -ge 2 ] || erro "falta valor em --render"; RENDER="$2"; shift 2 ;;
        --scrcpy-versao)     [ $# -ge 2 ] || erro "falta valor em --scrcpy-versao"; SCRCPY_VERSAO="$2"; shift 2 ;;
        --log-scrcpy)        [ $# -ge 2 ] || erro "falta valor em --log-scrcpy"; LOG_SCRCPY="$2"; shift 2 ;;
        --latencia-ms)       [ $# -ge 2 ] || erro "falta valor em --latencia-ms"; LATENCIA="$2"; shift 2 ;;
        --fps-medido)        [ $# -ge 2 ] || erro "falta valor em --fps-medido"; FPS_MEDIDO="$2"; shift 2 ;;
        --temp-ambiente)     [ $# -ge 2 ] || erro "falta valor em --temp-ambiente"; TEMP_AMB="$2"; shift 2 ;;
        --nota)              [ $# -ge 2 ] || erro "falta valor em --nota"; NOTA="$2"; shift 2 ;;
        --rapido)            RAPIDO=1; shift ;;
        --ajuda|-h|--help)   uso; exit 0 ;;
        *)                   erro "opção desconhecida: $1 (use --ajuda)" ;;
    esac
done

# ---------------------------------------------------------------- validação

[ -n "$CONDICAO" ] || erro "--condicao é obrigatório (C0 ou C1; veja --ajuda)"

CONDICAO="$(printf '%s' "$CONDICAO" | tr 'a-z' 'A-Z')"
case "$CONDICAO" in
    C0|C1) : ;;
    *) erro "--condicao aceita C0 ou C1 (recebi '$CONDICAO')" ;;
esac

case "$(printf '%s' "$METODO" | tr 'A-Z' 'a-z')" in
    auto)               METODO=auto ;;
    a|new-display)      METODO=A ;;
    b|overlay)          METODO=B ;;
    c|mirror|espelho)   METODO=C ;;
    *) erro "--metodo aceita auto, A, B ou C (recebi '$METODO')" ;;
esac

for par in "repeticao=$REPETICAO" "aquecimento=$AQUECIMENTO" \
           "duracao-repouso=$REPOUSO" "duracao-carga=$CARGA" \
           "intervalo=$INTERVALO" "intervalo-celular=$INTERVALO_CELULAR"; do
    nome="${par%%=*}"; valor="${par#*=}"
    case "$valor" in
        ''|*[!0-9]*) erro "--$nome precisa ser inteiro não negativo (recebi '$valor')" ;;
    esac
done
[ "$REPETICAO" -ge 1 ] || erro "--repeticao começa em 1"
[ "$INTERVALO" -ge 1 ] || erro "--intervalo mínimo é 1 segundo"
[ "$INTERVALO_CELULAR" -ge 1 ] || erro "--intervalo-celular mínimo é 1 segundo"
[ $(( AQUECIMENTO + REPOUSO + CARGA )) -gt 0 ] || erro "todas as fases estão em 0: nada a medir"

# As fases são informadas em minutos; a execução trabalha em segundos.
AQUECIMENTO_SEG=$(( AQUECIMENTO * 60 ))
REPOUSO_SEG=$(( REPOUSO * 60 ))
CARGA_SEG=$(( CARGA * 60 ))

if [ "$RAPIDO" -eq 1 ]; then
    AQUECIMENTO_SEG=0; REPOUSO_SEG=3; CARGA_SEG=0; INTERVALO=1
    if [ "$SAIDA_EXPLICITA" -eq 0 ]; then SAIDA="$ROOT/docs/medicoes/_teste"; fi
    aviso "--rapido: repouso de 3 s para testar o script. ESTES DADOS NÃO SERVEM PARA MEDIÇÃO."
fi

# ---------------------------------------------------------------- config

ler_config() { # ler_config CHAVE [padrão]
    _k="$1"; _d="${2:-}"
    _v=""
    if [ -r "$CONFIG" ]; then
        _v="$(sed -n "s/^[[:space:]]*${_k}=//p" "$CONFIG" 2>/dev/null | sed -n '1p' \
              | sed 's/[[:space:]]#.*$//' | tr -d '\r' | sed 's/^"\(.*\)"$/\1/')"
    fi
    if [ -n "$_v" ]; then printf '%s' "$_v"; else printf '%s' "$_d"; fi
}

[ -n "$RESOLUCAO" ] || RESOLUCAO="$(ler_config RESOLUTION auto)"
[ -n "$FPS_ALVO" ]  || FPS_ALVO="$(ler_config FPS 15)"
[ -n "$BITRATE" ]   || BITRATE="$(ler_config BITRATE 4M)"
[ -n "$CODEC" ]     || CODEC="$(ler_config VIDEO_CODEC h264)"
[ -n "$AUDIO" ]     || AUDIO="$(ler_config AUDIO off)"
[ -n "$RENDER" ]    || RENDER="$(ler_config RENDER_DRIVER software)"
[ -n "$SCRCPY_VERSAO" ] || {
    if tem scrcpy; then SCRCPY_VERSAO="$(scrcpy --version 2>/dev/null | sed -n '1p')"; fi
}

# Resolução real quando a configuração diz "auto".
if [ "$RESOLUCAO" = "auto" ] && tem xrandr; then
    _r="$(xrandr --current 2>/dev/null | awk '/ connected/ {print $3; exit}' | sed 's/+.*//')"
    [ -n "$_r" ] && RESOLUCAO="$_r (auto)"
fi

# ---------------------------------------------------------------- ambiente

INIT_SISTEMA="desconhecido"
if [ -d /run/systemd/system ]; then INIT_SISTEMA=systemd
elif [ -d /etc/sv ] && tem sv; then INIT_SISTEMA=runit
elif tem rc-service; then INIT_SISTEMA=openrc
fi

DISTRO="$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release 2>/dev/null | sed -n '1p')"
KERNEL="$(uname -r 2>/dev/null)"
ARQ="$(uname -m 2>/dev/null)"
HOST="$(hostname 2>/dev/null || echo desconhecido)"
CPU_MODELO="$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | sed -n '1p')"
RAM_TOTAL_KB="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"

DE_ATUAL=""
for _de in XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION; do
    eval "_v=\${$_de:-}"; [ -n "$_v" ] && DE_ATUAL="$_v" && break
done
if [ -z "$DE_ATUAL" ]; then
    if tem pgrep; then
        if pgrep -x xfce4-session >/dev/null 2>&1; then DE_ATUAL="Xfce"
        elif pgrep -x lxqt-session >/dev/null 2>&1; then DE_ATUAL="LXQt"
        elif pgrep -x lxsession >/dev/null 2>&1; then DE_ATUAL="LXDE"
        fi
    fi
fi

DM_ATUAL=""
if tem pgrep; then
    for _dm in lightdm sddm gdm gdm3; do
        pgrep -x "$_dm" >/dev/null 2>&1 && DM_ATUAL="$_dm" && break
    done
fi

SWAP_DISP=""
if tem swapon; then
    SWAP_DISP="$(swapon --show=NAME --noheadings 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g;s/ $//')"
fi

ZRAM_DISP=""
for _z in /sys/block/zram*; do
    [ -d "$_z" ] && ZRAM_DISP="$ZRAM_DISP$(basename "$_z") "
done
ZRAM_DISP="${ZRAM_DISP% }"
ZRAM_TOTAL_MB=""
if [ -n "$ZRAM_DISP" ]; then
    ZRAM_TOTAL_MB="$(awk '{s+=$1} END{printf "%d", s/1048576}' /sys/block/zram*/disksize 2>/dev/null)"
fi

BAT_DIR=""
for _b in /sys/class/power_supply/BAT*; do
    [ -d "$_b" ] && BAT_DIR="$_b" && break
done

TEM_ZONAS=0
for _t in /sys/class/thermal/thermal_zone*; do [ -d "$_t" ] && TEM_ZONAS=1 && break; done

ADB_OK=0
if tem adb && com_timeout 5 adb get-state >/dev/null 2>&1; then ADB_OK=1; fi
CELULAR_DESCRICAO=""
if [ "$ADB_OK" -eq 1 ]; then
    CELULAR_DESCRICAO="$(com_timeout 5 adb shell getprop ro.product.model 2>/dev/null | tr -d '\r' | sed -n '1p')"
fi

# ---------------------------------------------------------------- conformidade

verificar_conformidade() {
    # Só avisa: divergência não impede medir, mas precisa ficar registrada.
    if [ "$CONDICAO" = "C0" ]; then
        [ "$INIT_SISTEMA" = runit ] || \
            printf 'desvio: init é %s, C0 espera runit (Void)\n' "$INIT_SISTEMA"
        [ -n "$ZRAM_DISP" ] && \
            printf 'desvio: há zram (%s) em C0, que exige sem zram\n' "$ZRAM_DISP"
        case "$SWAP_DISP" in
            *zram*) printf 'desvio: swap em zram em C0, que exige swap em disco\n' ;;
        esac
        case "$DE_ATUAL" in
            *Xfce*|*xfce*) : ;;
            *) [ -n "$DE_ATUAL" ] && printf 'desvio: desktop é %s, C0 espera Xfce\n' "$DE_ATUAL" ;;
        esac
        [ "$ADB_OK" -eq 1 ] || printf 'aviso: nenhum celular autorizado em C0 (DeX ativo depende dele)\n'
    else
        [ "$INIT_SISTEMA" = systemd ] || \
            printf 'desvio: init é %s, C1 espera systemd (Debian)\n' "$INIT_SISTEMA"
        [ -n "$ZRAM_DISP" ] || printf 'desvio: sem zram em C1, que exige zram ativo\n'
        case "$DE_ATUAL" in
            *LXQt*|*lxqt*|*LXDE*) : ;;
            *) [ -n "$DE_ATUAL" ] && printf 'desvio: desktop é %s, C1 espera LXQt\n' "$DE_ATUAL" ;;
        esac
        [ "$ADB_OK" -eq 1 ] && \
            printf 'aviso: há celular conectado em C1, que é medida sem celular\n'
    fi
    if tem timedatectl; then
        case "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" in
            no) printf 'aviso: relógio não sincronizado (NTP); a data do CSV pode estar errada\n' ;;
        esac
    fi
    if ! tem awk || ! tem sed; then
        printf 'desvio: falta awk/sed; as métricas vão sair vazias\n'
    fi
    return 0
}

verificar_conformidade > "$TMP/conformidade.txt" 2>/dev/null
DESVIOS="$(grep -c '^desvio:' "$TMP/conformidade.txt" 2>/dev/null)"
[ -n "$DESVIOS" ] || DESVIOS=0

# ---------------------------------------------------------------- métricas

ler_mem() { # -> total_mb usada_mb disp_mb swap_total_mb swap_usada_mb
    awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2}
         /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
         END{ if (t > 0) printf "%d %d %d %d %d\n", t/1024, (t-a)/1024, a/1024, st/1024, (st-sf)/1024 }' \
        /proc/meminfo 2>/dev/null
}

ler_cpu() { # grava "ocupado total" (jiffies) em $TMP/cpu.now
    awk '/^cpu /{t=0; for (i=2; i<=NF; i++) t+=$i; printf "%d %d\n", t-$5-$6, t; exit}' \
        /proc/stat > "$TMP/cpu.now" 2>/dev/null
    return 0
}

cpu_pct() { # -> % de CPU desde a amostra anterior (vazio na primeira)
    ler_cpu
    _pct=""
    if [ -s "$TMP/cpu.now" ] && [ -s "$TMP/cpu.prev" ]; then
        _pct="$(awk 'NR==FNR{b=$1;t=$2;next}{ if (t>$2 && b>=$1) printf "%d", (b-$1)*100/(t-$2) }' \
                "$TMP/cpu.prev" "$TMP/cpu.now" 2>/dev/null)"
    fi
    [ -s "$TMP/cpu.now" ] && cp "$TMP/cpu.now" "$TMP/cpu.prev" 2>/dev/null
    printf '%s' "$_pct"
}

ler_load() { awk '{print $1}' /proc/loadavg 2>/dev/null; }

ler_zram_usada() {
    [ -n "$ZRAM_DISP" ] || return 0
    awk '{s+=$1} END{printf "%d", s/1048576}' /sys/block/zram*/mm_stat 2>/dev/null
}

ler_temp() {
    _t=""
    if [ "$TEM_ZONAS" -eq 1 ]; then
        _t="$(LC_ALL=C awk '{v=$1/1000; if (v>m) m=v} END{ if (NR>0) printf "%.1f", m }' \
              /sys/class/thermal/thermal_zone*/temp 2>/dev/null)"
    fi
    if [ -z "$_t" ] && tem sensors; then
        _t="$(sensors 2>/dev/null | sed -n 's/.*[+ ]\([0-9][0-9]*\(\.[0-9]*\)\?\)°C.*/\1/p' \
              | LC_ALL=C sort -n | tail -1 | tr "," ".")"
    fi
    printf '%s' "$_t"
}

ler_bat_pct() {
    [ -n "$BAT_DIR" ] || return 0
    cat "$BAT_DIR/capacity" 2>/dev/null | tr -d '\n'
}

ler_bat_w() {
    [ -n "$BAT_DIR" ] || return 0
    _pw="$(cat "$BAT_DIR/power_now" 2>/dev/null)"
    if [ -z "$_pw" ]; then
        _cur="$(cat "$BAT_DIR/current_now" 2>/dev/null)"
        _vol="$(cat "$BAT_DIR/voltage_now" 2>/dev/null)"
        if [ -n "$_cur" ] && [ -n "$_vol" ]; then
            # awk e não $(( )): sysfs pode devolver vazio/lixo e derrubar o shell.
            _pw="$(awk -v c="$_cur" -v v="$_vol" 'BEGIN{ if (c+0 > 0) printf "%.0f", c*v/1000000 }')"
        fi
    fi
    [ -n "$_pw" ] && awk -v p="$_pw" 'BEGIN{printf "%.1f", p/1000000}'
}

ler_bat_status() {
    [ -n "$BAT_DIR" ] || return 0
    cat "$BAT_DIR/status" 2>/dev/null | tr -d '\n'
}

ler_celular() { # -> "nivel temperatura" ou vazio
    [ "$ADB_OK" -eq 1 ] || return 0
    _d="$(com_timeout 5 adb shell dumpsys battery 2>/dev/null | tr -d '\r')"
    [ -n "$_d" ] || return 0
    printf '%s\n' "$_d" | awk -F': ' '
        / level:/{gsub(/ /,"",$2); l=$2}
        / temperature:/{gsub(/ /,"",$2); t=$2}
        END{ if (l != "") { printf "%s", l; if (t != "") printf " %.1f", t/10 } }'
}

ler_fps_log() {
    # O formato do --print-fps muda entre versões do scrcpy ("15.0 fps", "FPS: 15.0").
    # Se nada casar, use --fps-medido e registre no .meta.md.
    [ -n "$LOG_SCRCPY" ] && [ -r "$LOG_SCRCPY" ] || return 0
    tail -100 "$LOG_SCRCPY" 2>/dev/null | tr -d '\r' \
        | grep -oiE 'fps[[:space:]]*[=:][[:space:]]*[0-9]+(\.[0-9]+)?|[0-9]+(\.[0-9]+)?[[:space:]]*fps' \
        | tail -1 | grep -oE '[0-9]+(\.[0-9]+)?'
}

# ---------------------------------------------------------------- amostragem

amostrar() {
    local _fase="$1"
    local _cpu _load _mem _total _usada _disp _sw_t _sw_u _resto
    local _zram _temp _bat_pct _bat_w _bat_st _cel_pct _cel_temp _cel _fps
    local _ts_seg _ts_iso

    AMOSTRA=$(( AMOSTRA + 1 ))
    _ts_seg=$(( $(agora) - T0 ))
    _ts_iso="$(date -Iseconds)"

    _cpu="$(cpu_pct)"
    _load="$(ler_load)"

    _total=""; _usada=""; _disp=""; _sw_t=""; _sw_u=""
    _mem="$(ler_mem)"
    if [ -n "$_mem" ]; then
        _total="${_mem%% *}"; _resto="${_mem#* }"
        _usada="${_resto%% *}"; _resto="${_resto#* }"
        _disp="${_resto%% *}"; _resto="${_resto#* }"
        _sw_t="${_resto%% *}"; _sw_u="${_resto#* }"
    fi

    _zram="$(ler_zram_usada)"
    _temp="$(ler_temp)"
    _bat_pct="$(ler_bat_pct)"
    _bat_w="$(ler_bat_w)"
    _bat_st="$(ler_bat_status)"

    # O celular é lido a cada --intervalo-celular, não a cada amostra:
    # "adb shell" custa CPU e contaminaria justamente o T11.
    _cel_pct=""; _cel_temp=""
    if [ "$ADB_OK" -eq 1 ]; then
        if [ $(( _ts_seg - CEL_ULTIMO )) -ge "$INTERVALO_CELULAR" ] || [ "$AMOSTRA" -eq 1 ]; then
            CEL_ULTIMO="$_ts_seg"
            _cel="$(ler_celular)"
            if [ -n "$_cel" ]; then
                _cel_pct="${_cel%% *}"
                case "$_cel" in *" "*) _cel_temp="${_cel#* }" ;; esac
            fi
        fi
    fi

    _fps="$(ler_fps_log)"

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$AMOSTRA" "$_ts_seg" "$_ts_iso" "$_fase" "$_cpu" "$_load" \
        "$_usada" "$_disp" "$_total" "$_sw_u" "$_sw_t" "$_zram" "$_temp" \
        "$_bat_pct" "$_bat_w" "$_bat_st" "$_cel_pct" "$_cel_temp" "$_fps" >> "$CSV"

    printf '  [%3d] %-11s cpu=%-3s ram=%-5s swap=%-5s temp=%-5s\n' \
        "$AMOSTRA" "$_fase" "${_cpu:--}" "${_usada:--}" "${_sw_u:--}" "${_temp:--}"
    return 0
}

executar_fase() {
    local _fase="$1" _seg="$2" _fim _primeira
    [ "$_seg" -gt 0 ] || return 0
    _fim=$(( $(agora) + _seg ))
    _primeira=1
    while [ "$_primeira" -eq 1 ] || [ "$(agora)" -lt "$_fim" ]; do
        if [ "$INTERROMPIDO" -eq 1 ]; then return 1; fi
        amostrar "$_fase"
        _primeira=0
        [ "$(agora)" -lt "$_fim" ] || break
        sleep "$INTERVALO"
    done
    return 0
}

# ---------------------------------------------------------------- saída

mkdir -p "$SAIDA" 2>/dev/null || erro "não consegui criar $SAIDA"
CSV="$SAIDA/$(date +%Y%m%d-%H%M%S)-${CONDICAO}-r${REPETICAO}.csv"
META="${CSV%.csv}.meta.md"
: > "$CSV" || erro "não consegui escrever $CSV"

printf '%s\n' \
'amostra,ts_seg,ts_iso,fase,cpu_pct,load1,ram_usada_mb,ram_disp_mb,ram_total_mb,swap_usada_mb,swap_total_mb,zram_usada_mb,temp_c,bat_pct,bat_w,bat_status,cel_pct,cel_temp_c,fps_scrcpy' \
    >> "$CSV"

TOTAL_SEG=$(( AQUECIMENTO_SEG + REPOUSO_SEG + CARGA_SEG ))
printf 'riOS — coleta de desempenho (M6-01)\n'
printf 'condição %s · repetição %s · método %s\n' "$CONDICAO" "$REPETICAO" "$METODO"
printf 'fases: aquecimento %s s, repouso %s s, carga %s s (total %s s)\n' \
    "$AQUECIMENTO_SEG" "$REPOUSO_SEG" "$CARGA_SEG" "$TOTAL_SEG"
printf 'amostragem: %s s · saída: %s\n' "$INTERVALO" "$CSV"
if [ "$DESVIOS" -gt 0 ]; then
    printf 'conformidade: %s desvio(s) — veja o .meta.md antes de usar estes dados\n' "$DESVIOS"
    sed 's/^/  /' "$TMP/conformidade.txt" >&2
else
    printf 'conformidade: ambiente compatível com %s\n' "$CONDICAO"
fi
printf '\n'

trap 'INTERROMPIDO=1' INT TERM
T0=$(agora)
executar_fase aquecimento "$AQUECIMENTO_SEG"
executar_fase repouso "$REPOUSO_SEG"
executar_fase carga "$CARGA_SEG"
trap - INT TERM

DURACAO=$(( $(agora) - T0 ))

if [ "$INTERROMPIDO" -eq 1 ]; then
    printf '\nInterrompido — gravando o que já foi coletado.\n'
fi

# ---------------------------------------------------------------- resumo

# Índices das colunas: fase=4, cpu=5, ram=7, swap=10, temp=13.
RESUMO="$(awk -F, '
    NR > 1 && $4 == "repouso" {
        n++
        if ($5 != "") { c += $5; if ($5 > cm) cm = $5; nc++ }
        if ($7 != "") { r += $7; if ($7 > rm) rm = $7; nr++ }
        if ($10 != "") { s += $10; ns++ }
        if ($13 != "") { if ($13 > tm) tm = $13; nt++ }
    }
    END {
        printf "%d ", n
        if (nc) printf "%.1f %s ", c / nc, cm; else printf "- - "
        if (nr) printf "%.1f %s ", r / nr, rm; else printf "- - "
        if (ns) printf "%.1f " s / ns; else printf "- "
        if (nt) printf "%.1f\n"; else printf "-\n"
    }' "$CSV" 2>/dev/null)"

N_REPOUSO=""; CPU_MEDIA=""; CPU_MAX=""; RAM_MEDIA=""; RAM_MAX=""; SWAP_MEDIA=""; TEMP_MAX=""
if [ -n "$RESUMO" ]; then
    N_REPOUSO="${RESUMO%% *}"; _r="${RESUMO#* }"
    CPU_MEDIA="${_r%% *}"; _r="${_r#* }"
    CPU_MAX="${_r%% *}"; _r="${_r#* }"
    RAM_MEDIA="${_r%% *}"; _r="${_r#* }"
    RAM_MAX="${_r%% *}"; _r="${_r#* }"
    SWAP_MEDIA="${_r%% *}"; _r="${_r#* }"
    TEMP_MAX="${_r%% *}"
fi

printf '\n%-22s %s\n' 'amostras (repouso)' "${N_REPOUSO:--}"
printf '%-22s %s\n' 'CPU média/máx' "${CPU_MEDIA:--} / ${CPU_MAX:--} %"
printf '%-22s %s\n' 'RAM média/máx' "${RAM_MEDIA:--} / ${RAM_MAX:--} MB"
printf '%-22s %s\n' 'swap média' "${SWAP_MEDIA:--} MB"
printf '%-22s %s\n' 'temperatura máx' "${TEMP_MAX:--} °C"

# Pré-checagem contra o T11 (PLAN.md §11). O veredito é do M6-02, não daqui.
if [ "$CONDICAO" = "C0" ] && [ -n "$CPU_MEDIA" ] && [ "$CPU_MEDIA" != "-" ]; then
    printf '\nReferência T11: CPU < 60%% e RAM < 450 MB em repouso.\n'
    awk -v c="$CPU_MEDIA" -v r="$RAM_MEDIA" 'BEGIN{
        printf "  CPU %s (%.1f%%) · RAM %s (%s MB)\n", (c < 60 ? "dentro" : "FORA"), c, (r != "-" && r < 450 ? "dentro" : "FORA"), r
    }'
fi

# ---------------------------------------------------------------- metadados

{
    printf '# Medição %s — repetição %s\n\n' "$CONDICAO" "$REPETICAO"
    printf '> Gerado por `scripts/coleta-desempenho.sh`. Protocolo: `docs/protocolo-medicoes.md`.\n'
    if [ "$RAPIDO" -eq 1 ]; then
        printf '>\n> **MODO TESTE (`--rapido`): poucos segundos de coleta, não usar como medição.**\n'
    fi
    printf '\n## Rodada\n\n| Campo | Valor |\n|---|---|\n'
    printf '| Série (CSV) | `%s` |\n' "$(basename "$CSV")"
    printf '| Condição | %s |\n' "$CONDICAO"
    printf '| Repetição | %s de 3 |\n' "$REPETICAO"
    printf '| Método | %s |\n' "$METODO"
    printf '| Data/hora | %s |\n' "$(date -Iseconds)"
    printf '| Duração real | %s s |\n' "$DURACAO"
    printf '| Fases | aquecimento %s s · repouso %s s · carga %s s |\n' \
        "$AQUECIMENTO_SEG" "$REPOUSO_SEG" "$CARGA_SEG"
    printf '| Amostragem | %s s |\n' "$INTERVALO"
    printf '| Amostras | %s |\n' "$AMOSTRA"
    printf '\n## Sessão medida\n\n| Campo | Valor |\n|---|---|\n'
    printf '| Resolução | %s |\n' "${RESOLUCAO:-?}"
    printf '| FPS alvo | %s |\n' "${FPS_ALVO:-?}"
    printf '| Bitrate | %s |\n' "${BITRATE:-?}"
    printf '| Codec | %s |\n' "${CODEC:-?}"
    printf '| Áudio | %s |\n' "${AUDIO:-?}"
    printf '| Render | %s |\n' "${RENDER:-?}"
    printf '| scrcpy | %s |\n' "${SCRCPY_VERSAO:-não informado}"
    printf '| Log do scrcpy | %s |\n' "${LOG_SCRCPY:-não informado}"
    printf '\n## Ambiente\n\n| Campo | Valor |\n|---|---|\n'
    printf '| Host | %s |\n' "$HOST"
    printf '| Distribuição | %s |\n' "${DISTRO:-?}"
    printf '| Kernel | %s (%s) |\n' "${KERNEL:-?}" "${ARQ:-?}"
    printf '| Init | %s |\n' "$INIT_SISTEMA"
    printf '| Desktop | %s |\n' "${DE_ATUAL:-não detectado}"
    printf '| Gerenciador de display | %s |\n' "${DM_ATUAL:-não detectado}"
    printf '| CPU | %s |\n' "${CPU_MODELO:-?}"
    printf '| RAM total | %s MB |\n' "$( [ -n "$RAM_TOTAL_KB" ] && awk -v k="$RAM_TOTAL_KB" 'BEGIN{printf "%d", k/1024}' || printf '?')"
    printf '| Swap ativo | %s |\n' "${SWAP_DISP:-nenhum}"
    printf '| zram | %s |\n' "$( [ -n "$ZRAM_DISP" ] && printf '%s (%s MB)' "$ZRAM_DISP" "${ZRAM_TOTAL_MB:-?}" || printf 'nenhum')"
    printf '| Bateria | %s |\n' "${BAT_DIR:-não detectada}"
    printf '| Celular | %s |\n' "$( [ "$ADB_OK" -eq 1 ] && printf '%s' "${CELULAR_DESCRICAO:-autorizado (modelo não lido)}" || printf 'não conectado' )"
    printf '\n## Conformidade com %s\n\n' "$CONDICAO"
    if [ -s "$TMP/conformidade.txt" ]; then
        printf '```\n'; sed 's/^/  /' "$TMP/conformidade.txt"; printf '```\n'
    else
        printf 'Ambiente compatível: sem desvios registrados.\n'
    fi
    printf '\n## Métricas manuais (completar se ainda estiverem vazias)\n\n'
    printf '| Métrica | Valor |\n|---|---|\n'
    printf '| Latência de entrada (mediana de 10) | %s |\n' "${LATENCIA:-—}"
    printf '| FPS observado | %s |\n' "${FPS_MEDIDO:-—}"
    printf '| Temperatura ambiente | %s |\n' "${TEMP_AMB:-—}"
    printf '\n## Resumo automático (fase de repouso)\n\n'
    printf '| Métrica | Média | Máximo |\n|---|---|---|\n'
    printf '| CPU %% | %s | %s |\n' "${CPU_MEDIA:--}" "${CPU_MAX:--}"
    printf '| RAM MB | %s | %s |\n' "${RAM_MEDIA:--}" "${RAM_MAX:--}"
    printf '| Swap MB | %s | — |\n' "${SWAP_MEDIA:--}"
    printf '| Temperatura °C | — | %s |\n' "${TEMP_MAX:--}"
    printf '\n## Observações\n\n'
    if [ -n "$NOTA" ]; then printf '%s\n' "$NOTA"; else printf '—\n'; fi
    printf '\n## Antes de commitar\n\n'
    printf -- '- [ ] As 3 repetições de %s foram feitas (r1, r2, r3)\n' "$CONDICAO"
    printf -- '- [ ] Latência, FPS observado e temperatura ambiente preenchidos\n'
    printf -- '- [ ] CSV e este .meta.md adicionados em `docs/medicoes/`\n'
    printf -- '- [ ] Divergências de conformidade explicadas nas observações\n'
} > "$META"

# ---------------------------------------------------------------- índice

INDICE="$SAIDA/indice.csv"
if [ ! -f "$INDICE" ]; then
    printf '%s\n' \
'arquivo,data_iso,host,condicao,metodo,repeticao,aquecimento_s,repouso_s,carga_s,intervalo_s,amostras_repouso,cpu_media,cpu_max,ram_media_mb,ram_max_mb,swap_media_mb,temp_max_c,latencia_ms,fps_medido,scrcpy_versao,resolucao,fps_alvo,bitrate,render,nota' \
        >> "$INDICE"
fi

NOTA_CSV="$(printf '%s' "$NOTA" | tr '\n' ' ' | tr -d '"')"

printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
    "$(basename "$CSV")" "$(date -Iseconds)" "$HOST" "$CONDICAO" "$METODO" "$REPETICAO" \
    "$AQUECIMENTO_SEG" "$REPOUSO_SEG" "$CARGA_SEG" "$INTERVALO" "${N_REPOUSO:-0}" \
    "${CPU_MEDIA:--}" "${CPU_MAX:--}" "${RAM_MEDIA:--}" "${RAM_MAX:--}" \
    "${SWAP_MEDIA:--}" "${TEMP_MAX:--}" "${LATENCIA:--}" "${FPS_MEDIDO:--}" \
    "${SCRCPY_VERSAO:--}" "${RESOLUCAO:--}" "${FPS_ALVO:--}" "${BITRATE:--}" "${RENDER:--}" \
    "$NOTA_CSV" >> "$INDICE" 2>/dev/null || {
        aviso "índice não pôde ser atualizado ($INDICE)"
    }

printf '\nArquivos gravados:\n  %s\n  %s\n  %s\n' "$CSV" "$META" "$INDICE"
printf '\nPróximo passo: repetir até r3 e depois consolidar com `--condicao` oposta.\n'
exit 0
