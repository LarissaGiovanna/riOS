#!/usr/bin/env bash
# ==============================================================================
# riOS — Instalação no Disco Interno (install-on-disk.sh)
# Realiza backup de salvaguarda, particiona GPT, transfere o rootfs da imagem
# e instala o GRUB UEFI dedicado ao riOS.
# Uso: install-on-disk.sh <dispositivo> <imagem>
# Exemplo: sudo ./scripts/install-on-disk.sh /dev/sda rios.img
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
    log_err "Exemplo: sudo $0 /dev/sda rios.img"
    exit 1
fi

DISK="$1"
IMAGE="$2"

# ------------------------------------------------------------------------------
# 1. Verificações de Privilégios e Dispositivo
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    log_err "Este script precisa de privilégios de root (execute com sudo)."
    exit 1
fi

if [ ! -f "$IMAGE" ]; then
    log_err "Arquivo de imagem de origem não encontrado: $IMAGE"
    exit 1
fi

if [ ! -b "$DISK" ]; then
    log_err "Dispositivo de bloco não encontrado: $DISK"
    exit 1
fi

# Verificar se é um disco inteiro e NÃO uma partição
DEV_TYPE="$(lsblk -no TYPE "$DISK" 2>/dev/null | head -n 1 || true)"
if [ "$DEV_TYPE" != "disk" ]; then
    log_err "O alvo '$DISK' é do tipo '$DEV_TYPE', e NÃO um disco inteiro!"
    log_err "A instalação requer o dispositivo do disco completo (exemplo: /dev/sda, não /dev/sda1)."
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. Confirmação Dupla Obrigatória ('APAGAR')
# ------------------------------------------------------------------------------
echo -e "\n${CLR_BOLD}Dispositivo alvo para instalação do riOS:${CLR_RESET}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,MOUNTPOINTS "$DISK"
echo ""

log_warn "PERIGO: ESTA OPERAÇÃO IRÁ DESTRUIR DEFINITIVAMENTE TODOS OS DADOS EM $DISK!"
echo -ne "${CLR_BOLD}Confirmação 1/2: Digite 'APAGAR' para prosseguir: ${CLR_RESET}"
read -r CONFIRM1

if [ "$CONFIRM1" != "APAGAR" ]; then
    log_warn "Operação cancelada na primeira confirmação. Nenhuma alteração realizada."
    exit 0
fi

echo -ne "${CLR_BOLD}Confirmação 2/2: Digite 'APAGAR' novamente para autorizar a destruição e instalação: ${CLR_RESET}"
read -r CONFIRM2

if [ "$CONFIRM2" != "APAGAR" ]; then
    log_warn "Operação cancelada na segunda confirmação. Nenhuma alteração realizada."
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. Rotina de Backup de Salvaguarda
# ------------------------------------------------------------------------------
BACKUP_DIR="./backups/backup-pre-install-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
log_info "Iniciando backup preventivo de segurança em: $BACKUP_DIR..."

log_info "- Salvando tabela de partição via sgdisk / sfdisk..."
if command -v sgdisk >/dev/null 2>&1; then
    sgdisk --backup="$BACKUP_DIR/gpt-table.bin" "$DISK" 2>/dev/null || true
fi
if command -v sfdisk >/dev/null 2>&1; then
    sfdisk -d "$DISK" > "$BACKUP_DIR/partitions.sfdisk" 2>/dev/null || true
fi

log_info "- Salvando os primeiros 2 MiB do disco físico..."
dd if="$DISK" of="$BACKUP_DIR/mbr-e-gpt-header-2M.bin" bs=1M count=2 conv=fsync status=none

log_info "- Salvando conteúdo da ESP atual..."
if [ -d "/boot/efi" ] && [ "$(ls -A /boot/efi 2>/dev/null)" ]; then
    tar -czf "$BACKUP_DIR/esp-bootloader.tar.gz" -C /boot efi 2>/dev/null || true
else
    ESP_PART=$(lsblk -no PATH,PARTTYPE,FSTYPE "$DISK" 2>/dev/null | grep -E "vfat|c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | awk '{print $1}' | head -n 1 || true)
    if [ -n "$ESP_PART" ] && [ -b "$ESP_PART" ]; then
        TMP_ESP=$(mktemp -d /tmp/inst-esp.XXXXXX)
        mount -o ro "$ESP_PART" "$TMP_ESP" 2>/dev/null || mount "$ESP_PART" "$TMP_ESP"
        tar -czf "$BACKUP_DIR/esp-bootloader.tar.gz" -C "$TMP_ESP" . 2>/dev/null || true
        umount "$TMP_ESP" 2>/dev/null || true
        rmdir "$TMP_ESP" 2>/dev/null || true
    fi
fi

log_info "- Salvando /etc e /home atuais..."
tar -czf "$BACKUP_DIR/etc.tar.gz" -C / etc 2>/dev/null || true
tar -czf "$BACKUP_DIR/home.tar.gz" -C / home 2>/dev/null || true

(
    cd "$BACKUP_DIR"
    sha256sum * > SHA256SUMS 2>/dev/null || true
)
log_succ "Backup de salvaguarda concluído com sucesso em $BACKUP_DIR."

# ------------------------------------------------------------------------------
# 4. Desmontar Qualquer Partição Ativa no Disco Alvo
# ------------------------------------------------------------------------------
log_info "Desmontando partições do disco $DISK..."
MOUNTS=$(lsblk -no MOUNTPOINTS "$DISK" 2>/dev/null | grep -v '^[[:space:]]*$' || true)
if [ -n "$MOUNTS" ]; then
    while IFS= read -r mnt; do
        if [ -n "$mnt" ]; then
            log_info "Desmontando $mnt..."
            umount -f "$mnt" 2>/dev/null || true
        fi
    done <<< "$MOUNTS"
fi

# ------------------------------------------------------------------------------
# 5. Particionamento GPT (ESP 512 MiB + root restante)
# ------------------------------------------------------------------------------
log_info "Limpando assinaturas antigas e criando tabela GPT..."
wipefs -a "$DISK" 2>/dev/null || true
parted -s "$DISK" mklabel gpt

log_info "Criando partição 1: ESP (512 MiB, FAT32, flags boot+esp)..."
parted -s "$DISK" mkpart "ESP" fat32 1MiB 513MiB
parted -s "$DISK" set 1 boot on
parted -s "$DISK" set 1 esp on

log_info "Criando partição 2: root (ext4, espaço restante)..."
parted -s "$DISK" mkpart "root" ext4 513MiB 100%

partprobe "$DISK" 2>/dev/null || true
udevadm settle 2>/dev/null || sleep 2

# Determinar nomes das partições geradas
if [[ "$DISK" =~ [0-9]$ ]]; then
    P_PREFIX="${DISK}p"
else
    P_PREFIX="${DISK}"
fi

TARGET_ESP="${P_PREFIX}1"
TARGET_ROOT="${P_PREFIX}2"

if [ ! -b "$TARGET_ESP" ] || [ ! -b "$TARGET_ROOT" ]; then
    log_err "Falha ao identificar partições criadas: $TARGET_ESP / $TARGET_ROOT"
    exit 1
fi

# ------------------------------------------------------------------------------
# 6. Formatação dos Sistemas de Arquivos
# ------------------------------------------------------------------------------
log_info "Formatando $TARGET_ESP como FAT32 (RIOS_ESP)..."
mkfs.fat -F32 -n "RIOS_ESP" "$TARGET_ESP"

log_info "Formatando $TARGET_ROOT como ext4 (rios-root)..."
mkfs.ext4 -F -L "rios-root" -m 0 "$TARGET_ROOT"

TARGET_ESP_UUID=$(blkid -s UUID -o value "$TARGET_ESP")
TARGET_ROOT_UUID=$(blkid -s UUID -o value "$TARGET_ROOT")

log_info "Novos UUIDs gerados:"
echo "  - ESP:  $TARGET_ESP_UUID"
echo "  - Root: $TARGET_ROOT_UUID"

# ------------------------------------------------------------------------------
# 7. Montagem e Transferência do Rootfs via rsync -aHAX
# ------------------------------------------------------------------------------
log_info "Mapeando imagem de origem $IMAGE..."
SRC_LOOP=$(losetup -fP --show "$IMAGE")
SRC_ROOT_PART="${SRC_LOOP}p2"

SRC_MOUNT=$(mktemp -d /tmp/rios-src.XXXXXX)
TARGET_MOUNT=$(mktemp -d /tmp/rios-target.XXXXXX)

cleanup_install() {
    log_info "Finalizando montagens de instalação..."
    umount "$TARGET_MOUNT/dev/pts" 2>/dev/null || true
    umount "$TARGET_MOUNT/dev" 2>/dev/null || true
    umount "$TARGET_MOUNT/proc" 2>/dev/null || true
    umount "$TARGET_MOUNT/sys" 2>/dev/null || true
    umount "$TARGET_MOUNT/boot/efi" 2>/dev/null || true
    umount "$TARGET_MOUNT" 2>/dev/null || true
    rmdir "$TARGET_MOUNT" 2>/dev/null || true

    umount "$SRC_MOUNT" 2>/dev/null || true
    rmdir "$SRC_MOUNT" 2>/dev/null || true

    if [ -n "$SRC_LOOP" ] && losetup "$SRC_LOOP" >/dev/null 2>&1; then
        losetup -d "$SRC_LOOP" 2>/dev/null || true
    fi
}
trap cleanup_install EXIT INT TERM

mount -o ro "$SRC_ROOT_PART" "$SRC_MOUNT"
mount "$TARGET_ROOT" "$TARGET_MOUNT"
mkdir -p "$TARGET_MOUNT/boot/efi"
mount "$TARGET_ESP" "$TARGET_MOUNT/boot/efi"

log_info "Transferindo sistema de arquivos com rsync -aHAX (preservando atributos, hardlinks e ACLs)..."
rsync -aHAX --exclude="/boot/efi/*" "$SRC_MOUNT/" "$TARGET_MOUNT/"

# Ajustar /etc/fstab com os UUIDs reais do disco interno
log_info "Atualizando /etc/fstab com UUIDs do disco permanente..."
cat > "$TARGET_MOUNT/etc/fstab" <<EOF
# /etc/fstab configurado pelo install-on-disk.sh
UUID=$TARGET_ROOT_UUID / ext4 noatime,errors=remount-ro 0 1
UUID=$TARGET_ESP_UUID /boot/efi vfat umask=0077 0 2
EOF

# ------------------------------------------------------------------------------
# 8. Instalação do GRUB UEFI no Disco
# ------------------------------------------------------------------------------
log_info "Montando pseudo-sistemas de arquivos para chroot de bootloader..."
mount -t proc proc "$TARGET_MOUNT/proc"
mount -t sysfs sys "$TARGET_MOUNT/sys"
mount --bind /dev "$TARGET_MOUNT/dev"
mount --bind /dev/pts "$TARGET_MOUNT/dev/pts"

log_info "Instalando GRUB no disco alvo (bootloader-id=rios, --removable)..."
chroot "$TARGET_MOUNT" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=rios \
    --removable \
    --no-nvram

log_info "Gerando grub.cfg no disco alvo..."
chroot "$TARGET_MOUNT" grub-mkconfig -o /boot/grub/grub.cfg

sync
log_succ "======================================================================"
log_succ "Instalação do riOS concluída com sucesso no disco $DISK!"
log_succ "O netbook agora possui uma instalação dedicada e permanente do riOS."
log_succ "Você já pode reiniciar o computador (reboot)."
log_succ "======================================================================"
