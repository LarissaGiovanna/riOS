#!/usr/bin/env bash
# ==============================================================================
# riOS — Script de Construção da Imagem de Sistema (build-rios.sh)
# Cria rios.img (GPT + ESP UEFI) para uso como Live USB ou Instalação no HD
# ATENÇÃO: Deve ser executado em máquina host x86_64 (Debian/Ubuntu/Mint), NÃO no netbook!
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

# ------------------------------------------------------------------------------
# 0. Verificações de Ambiente e Privilégios
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    log_err "Este script precisa de privilégios de root (execute com sudo)."
    exit 1
fi

HOST_ARCH="$(uname -m)"
if [ "$HOST_ARCH" != "x86_64" ]; then
    log_err "Arquitetura do host inválida: $HOST_ARCH. O build deve ser realizado em host x86_64."
    exit 1
fi

# Diretório base do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Carregar VERSIONS.lock se existir
VERSIONS_FILE="$SCRIPT_DIR/VERSIONS.lock"
if [ -f "$VERSIONS_FILE" ]; then
    log_info "Lendo configurações de $VERSIONS_FILE..."
    # shellcheck disable=SC1090
    source "$VERSIONS_FILE"
fi

DEBIAN_SUITE="${DEBIAN_SUITE:-trixie}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
IMAGE_SIZE_MB="${IMAGE_SIZE_MB:-3072}"
IMAGE_NAME="${IMAGE_NAME:-rios.img}"
OUTPUT_IMAGE="$PROJECT_ROOT/$IMAGE_NAME"

log_info "Configuração do build:"
echo "  - Imagem de saída: $OUTPUT_IMAGE"
echo "  - Tamanho da imagem: ${IMAGE_SIZE_MB} MiB"
echo "  - Debian Suite: $DEBIAN_SUITE"
echo "  - Espelho Debian: $DEBIAN_MIRROR"

# ------------------------------------------------------------------------------
# 1. Verificação de Ferramentas Pré-Requisito
# ------------------------------------------------------------------------------
log_info "Verificando pré-requisitos no host..."

PREREQS=(
    debootstrap
    parted
    losetup
    mkfs.fat
    mkfs.ext4
    blkid
)

MISSING_TOOLS=()
for tool in "${PREREQS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

# Verificar se grub-efi-amd64 ou grub-install está disponível
if ! command -v grub-install >/dev/null 2>&1; then
    MISSING_TOOLS+=(grub-efi-amd64)
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    log_err "Ferramentas ausentes no host de build: ${MISSING_TOOLS[*]}"
    log_err "Instale os pré-requisitos antes de prosseguir:"
    log_err "  sudo apt update && sudo apt install -y debootstrap parted grub-efi-amd64 dosfstools e2fsprogs util-linux"
    exit 1
fi

log_succ "Todos os pré-requisitos foram validados."

# ------------------------------------------------------------------------------
# 2. Preparação de Estruturas e Limpeza (Trap)
# ------------------------------------------------------------------------------
MOUNT_DIR=""
LOOP_DEV=""

cleanup() {
    local exit_code=$?
    log_info "Executando procedimentos de finalização e limpeza..."
    if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
        # Desmontar pontos de montagem virtuais em ordem reversa
        umount "$MOUNT_DIR/dev/pts" 2>/dev/null || true
        umount "$MOUNT_DIR/dev" 2>/dev/null || true
        umount "$MOUNT_DIR/proc" 2>/dev/null || true
        umount "$MOUNT_DIR/sys" 2>/dev/null || true
        umount "$MOUNT_DIR/boot/efi" 2>/dev/null || true
        umount "$MOUNT_DIR" 2>/dev/null || true
        rmdir "$MOUNT_DIR" 2>/dev/null || true
    fi

    if [ -n "$LOOP_DEV" ] && losetup "$LOOP_DEV" >/dev/null 2>&1; then
        log_info "Liberando dispositivo loop $LOOP_DEV..."
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi

    if [ $exit_code -ne 0 ]; then
        log_err "O build de $IMAGE_NAME falhou (código de saída: $exit_code)."
    fi
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# 3. Criação do Arquivo de Imagem
# ------------------------------------------------------------------------------
log_info "Criando arquivo esparso para imagem ${IMAGE_NAME} (${IMAGE_SIZE_MB} MiB)..."
rm -f "$OUTPUT_IMAGE"
fallocate -l "${IMAGE_SIZE_MB}M" "$OUTPUT_IMAGE" 2>/dev/null || dd if=/dev/zero of="$OUTPUT_IMAGE" bs=1M count=0 seek="$IMAGE_SIZE_MB" status=none

# ------------------------------------------------------------------------------
# 4. Particionamento GPT via Loop Device
# ------------------------------------------------------------------------------
log_info "Associando imagem a dispositivo loop..."
LOOP_DEV="$(losetup -fP --show "$OUTPUT_IMAGE")"
log_info "Dispositivo loop alocado: $LOOP_DEV"

log_info "Criando tabela de partições GPT..."
parted -s "$LOOP_DEV" mklabel gpt

log_info "Criando partição 1 (ESP - 512 MiB)..."
parted -s "$LOOP_DEV" mkpart "ESP" fat32 1MiB 513MiB
parted -s "$LOOP_DEV" set 1 boot on
parted -s "$LOOP_DEV" set 1 esp on

log_info "Criando partição 2 (Root - restante do espaço)..."
parted -s "$LOOP_DEV" mkpart "root" ext4 513MiB 100%

# Atualizar mapeamento de partições
partprobe "$LOOP_DEV" 2>/dev/null || true
udevadm settle 2>/dev/null || sleep 2

LOOP_ESP="${LOOP_DEV}p1"
LOOP_ROOT="${LOOP_DEV}p2"

if [ ! -b "$LOOP_ESP" ] || [ ! -b "$LOOP_ROOT" ]; then
    log_err "Falha ao identificar partições do dispositivo loop: $LOOP_ESP / $LOOP_ROOT"
    exit 1
fi

# ------------------------------------------------------------------------------
# 5. Formatação dos Sistemas de Arquivos
# ------------------------------------------------------------------------------
log_info "Formatando partição ESP (FAT32)..."
mkfs.fat -F32 -n "RIOS_ESP" "$LOOP_ESP"

log_info "Formatando partição root (ext4)..."
mkfs.ext4 -F -L "rios-root" -m 0 "$LOOP_ROOT"

# Obter UUIDs definitivos das partições
ESP_UUID="$(blkid -s UUID -o value "$LOOP_ESP")"
ROOT_UUID="$(blkid -s UUID -o value "$LOOP_ROOT")"
log_info "UUIDs das partições geradas:"
echo "  - ESP:  $ESP_UUID"
echo "  - ROOT: $ROOT_UUID"

# ------------------------------------------------------------------------------
# 6. Montagem dos Sistemas de Arquivos
# ------------------------------------------------------------------------------
MOUNT_DIR="$(mktemp -d /tmp/rios-build.XXXXXX)"
log_info "Montando sistema de arquivos alvo em $MOUNT_DIR..."
mount "$LOOP_ROOT" "$MOUNT_DIR"

mkdir -p "$MOUNT_DIR/boot/efi"
mount "$LOOP_ESP" "$MOUNT_DIR/boot/efi"

# ------------------------------------------------------------------------------
# 7. Execução do debootstrap
# ------------------------------------------------------------------------------
log_info "Iniciando debootstrap para Debian $DEBIAN_SUITE (main, contrib, non-free-firmware)..."
debootstrap --arch=amd64 \
            --components=main,contrib,non-free-firmware \
            --include=ca-certificates,locales \
            "$DEBIAN_SUITE" \
            "$MOUNT_DIR" \
            "$DEBIAN_MIRROR"

log_succ "Debootstrap concluído com sucesso."

# ------------------------------------------------------------------------------
# 8. Montar Pseudo-Sistemas de Arquivos para o Chroot
# ------------------------------------------------------------------------------
log_info "Montando proc, sys e dev para o chroot..."
mount -t proc proc "$MOUNT_DIR/proc"
mount -t sysfs sys "$MOUNT_DIR/sys"
mount --bind /dev "$MOUNT_DIR/dev"
mount --bind /dev/pts "$MOUNT_DIR/dev/pts"

# Configurar resolv.conf temporário para conectividade de rede no chroot
cp /etc/resolv.conf "$MOUNT_DIR/etc/resolv.conf"

# ------------------------------------------------------------------------------
# 9. Configurar /etc/fstab com os UUIDs reais
# ------------------------------------------------------------------------------
log_info "Gerando /etc/fstab com UUIDs das partições..."
mkdir -p "$MOUNT_DIR/etc"
cat > "$MOUNT_DIR/etc/fstab" <<EOF
# /etc/fstab gerado pelo build-rios.sh
UUID=$ROOT_UUID / ext4 noatime,errors=remount-ro 0 1
UUID=$ESP_UUID /boot/efi vfat umask=0077 0 2
EOF

# ------------------------------------------------------------------------------
# 10. Executar post-install.sh dentro do Chroot
# ------------------------------------------------------------------------------
log_info "Copiando scripts de build e overlays para o chroot..."
mkdir -p "$MOUNT_DIR/tmp/overlay"
if [ -d "$SCRIPT_DIR/overlay" ]; then
    cp -a "$SCRIPT_DIR/overlay/." "$MOUNT_DIR/tmp/overlay/"
fi

cp "$VERSIONS_FILE" "$MOUNT_DIR/tmp/VERSIONS.lock"
cp "$SCRIPT_DIR/post-install.sh" "$MOUNT_DIR/tmp/post-install.sh"
chmod +x "$MOUNT_DIR/tmp/post-install.sh"

log_info "Executando build/post-install.sh dentro do chroot..."
chroot "$MOUNT_DIR" /tmp/post-install.sh /tmp/overlay /tmp/VERSIONS.lock

# ------------------------------------------------------------------------------
# 11. Instalação e Configuração do GRUB UEFI
# ------------------------------------------------------------------------------
log_info "Instalando GRUB UEFI (x86_64-efi, bootloader-id=rios, --removable)..."
chroot "$MOUNT_DIR" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=rios \
    --removable \
    --no-nvram

log_info "Gerando configuração do GRUB (grub-mkconfig)..."
chroot "$MOUNT_DIR" grub-mkconfig -o /boot/grub/grub.cfg

# ------------------------------------------------------------------------------
# 12. Finalização, Desmontagem e Registro SHA-256
# ------------------------------------------------------------------------------
log_info "Sincronizando dados em disco..."
sync

log_info "Desmontando chroot..."
umount "$MOUNT_DIR/dev/pts" 2>/dev/null || true
umount "$MOUNT_DIR/dev" 2>/dev/null || true
umount "$MOUNT_DIR/proc" 2>/dev/null || true
umount "$MOUNT_DIR/sys" 2>/dev/null || true
umount "$MOUNT_DIR/boot/efi" 2>/dev/null || true
umount "$MOUNT_DIR" 2>/dev/null || true
rmdir "$MOUNT_DIR" 2>/dev/null || true
MOUNT_DIR=""

log_info "Desconectando dispositivo loop..."
losetup -d "$LOOP_DEV" 2>/dev/null || true
LOOP_DEV=""

log_info "Calculando checksum SHA-256 da imagem gerada..."
cd "$PROJECT_ROOT"
IMAGE_SHA=$(sha256sum "$IMAGE_NAME" | awk '{print $1}')
echo "$IMAGE_SHA  $IMAGE_NAME" > "$PROJECT_ROOT/SHA256SUMS"

log_succ "======================================================================"
log_succ "Build do riOS concluído com êxito!"
log_succ "Artefato gerado: $OUTPUT_IMAGE"
log_succ "SHA-256:         $IMAGE_SHA"
log_succ "Checksum registrado em: $PROJECT_ROOT/SHA256SUMS"
log_succ "======================================================================"
