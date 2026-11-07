#!/usr/bin/env bash
# ==============================================================================
# riOS — Gravação de Live USB (make-live-usb.sh)
# Grava a imagem rios.img em um pendrive com verificação e cálculo de integridade
# Uso: make-live-usb.sh <dispositivo> <imagem>
# Exemplo: sudo ./scripts/make-live-usb.sh /dev/sdb rios.img
# ==============================================================================
set -euo pipefail

# Cores ANSI para saída no terminal
CLR_RESET="\033[0m"
CLR_INFO="\033[1;34m"
CLR_WARN="\033[1;33m"
CLR_ERR="\033[1;31m"
CLR_SUCC="\033[1;32m"
CLR_BOLD="\033[1m"

log_info() { echo -e "${CLR_INFO}[INFO]${CLR_RESET} $*"; }
log_warn() { echo -e "${CLR_WARN}[AVISO]${CLR_RESET} $*"; }
log_err()  { echo -e "${CLR_ERR}[ERRO]${CLR_RESET} $*" >&2; }
log_succ() { echo -e "${CLR_SUCC}[SUCESSO]${CLR_RESET} $*"; }

if [ "$#" -ne 2 ]; then
    log_err "Uso: $0 <dispositivo> <imagem>"
    log_err "Exemplo: sudo $0 /dev/sdb rios.img"
    exit 1
fi

DEVICE="$1"
IMAGE="$2"

# ------------------------------------------------------------------------------
# 1. Verificações de Ambiente e Parâmetros
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    log_err "Este script precisa de privilégios de root (execute com sudo)."
    exit 1
fi

if [ ! -f "$IMAGE" ]; then
    log_err "Arquivo de imagem não encontrado: $IMAGE"
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    log_err "Dispositivo de bloco não encontrado ou inválido: $DEVICE"
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. Verificar se o dispositivo ou alguma de suas partições está montado
# ------------------------------------------------------------------------------
log_info "Verificando se o dispositivo $DEVICE possui montagens ativas..."
MOUNTS=$(lsblk -no MOUNTPOINTS "$DEVICE" 2>/dev/null | grep -v '^[[:space:]]*$' || true)

if [ -n "$MOUNTS" ]; then
    log_err "O dispositivo $DEVICE (ou uma de suas partições) está MONTADO!"
    echo "$MOUNTS" >&2
    log_err "Desmonte todas as partições do dispositivo antes de prosseguir."
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. Exibir Detalhes do Alvo e Solicitar Confirmação Estrita
# ------------------------------------------------------------------------------
echo -e "\n${CLR_BOLD}Informações do dispositivo alvo:${CLR_RESET}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,VENDOR,TRAN "$DEVICE"
echo ""

IMAGE_SIZE_BYTES=$(stat -c%s "$IMAGE")
IMAGE_SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$IMAGE_SIZE_BYTES" 2>/dev/null || echo "${IMAGE_SIZE_BYTES} bytes")

log_warn "ATENÇÃO: TODOS OS DADOS EM ${DEVICE} SERÃO DESTRUÍDOS DEFINITIVAMENTE!"
log_warn "A imagem '$IMAGE' ($IMAGE_SIZE_HUMAN) será gravada em '$DEVICE'."
echo -ne "${CLR_BOLD}Digite exatamente 'SIM' para autorizar a gravação: ${CLR_RESET}"
read -r CONFIRMACAO

if [ "$CONFIRMACAO" != "SIM" ]; then
    log_warn "Operação cancelada pelo usuário. Nenhuma alteração foi realizada."
    exit 0
fi

# ------------------------------------------------------------------------------
# 4. Gravação da Imagem com dd
# ------------------------------------------------------------------------------
log_info "Iniciando gravação no pendrive via dd..."
dd if="$IMAGE" of="$DEVICE" bs=4M status=progress conv=fsync

log_info "Sincronizando buffers com o dispositivo físico..."
sync

log_succ "Gravação física concluída."

# ------------------------------------------------------------------------------
# 5. Comparação de SHA-256 entre Imagem e Pendrive
# ------------------------------------------------------------------------------
log_info "Calculando checksum SHA-256 da imagem original..."
IMAGE_SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
log_info "SHA-256 Imagem:   $IMAGE_SHA"

log_info "Lendo $IMAGE_SIZE_HUMAN do pendrive para validação do checksum..."
DEVICE_SHA=$(head -c "$IMAGE_SIZE_BYTES" "$DEVICE" | sha256sum | awk '{print $1}')
log_info "SHA-256 Pendrive: $DEVICE_SHA"

if [ "$IMAGE_SHA" = "$DEVICE_SHA" ]; then
    log_succ "======================================================================"
    log_succ "Verificação de integridade confirmada! O pendrive está pronto."
    log_succ "SHA-256 idêntico: $DEVICE_SHA"
    log_succ "Você já pode ejetar o dispositivo com segurança."
    log_succ "======================================================================"
else
    log_err "FALHA DE INTEGRIDADE! O checksum do pendrive diverge da imagem."
    log_err "Imagem:   $IMAGE_SHA"
    log_err "Pendrive: $DEVICE_SHA"
    exit 1
fi
