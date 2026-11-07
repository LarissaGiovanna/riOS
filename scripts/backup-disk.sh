#!/usr/bin/env bash
# ==============================================================================
# riOS — Backup de Segurança do Disco (backup-disk.sh)
# Salva tabela GPT, primeiros 2 MiB, ESP (/boot/efi), /home e /etc com data/hora
# Uso: backup-disk.sh [dispositivo] [diretorio_destino]
# Exemplo: sudo ./scripts/backup-disk.sh /dev/sda /root/backups
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
# 1. Verificações de Ambiente e Parâmetros
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    log_err "Este script precisa de privilégios de root (execute com sudo)."
    exit 1
fi

DISK="${1:-/dev/sda}"
DEST_BASE="${2:-./backups}"

if [ ! -b "$DISK" ]; then
    log_err "Dispositivo de bloco não encontrado: $DISK"
    exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$DEST_BASE/backup-rios-$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

log_info "Iniciando rotina de backup do disco $DISK..."
log_info "Destino: $BACKUP_DIR"

# ------------------------------------------------------------------------------
# 2. Backup da Tabela de Partições (GPT/MBR)
# ------------------------------------------------------------------------------
log_info "1/6. Salvando tabela de partições..."
if command -v sgdisk >/dev/null 2>&1; then
    sgdisk --backup="$BACKUP_DIR/gpt-table.bin" "$DISK" 2>/dev/null || log_warn "sgdisk reportou aviso ao salvar gpt-table.bin"
fi

if command -v sfdisk >/dev/null 2>&1; then
    sfdisk -d "$DISK" > "$BACKUP_DIR/partitions.sfdisk" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 3. Backup dos Primeiros 2 MiB (MBR + Cabeçalho GPT Primário)
# ------------------------------------------------------------------------------
log_info "2/6. Copiando primeiros 2 MiB do disco físico..."
dd if="$DISK" of="$BACKUP_DIR/mbr-e-gpt-header-2M.bin" bs=1M count=2 conv=fsync status=none

# ------------------------------------------------------------------------------
# 4. Backup da Partição ESP (/boot/efi)
# ------------------------------------------------------------------------------
log_info "3/6. Compactando conteúdo da ESP (/boot/efi)..."
if [ -d "/boot/efi" ] && [ "$(ls -A /boot/efi 2>/dev/null)" ]; then
    tar -czf "$BACKUP_DIR/esp-bootloader.tar.gz" -C /boot efi
else
    log_warn "Diretório /boot/efi vazio ou não montado. Procurando partição ESP em $DISK..."
    ESP_PART=$(lsblk -no PATH,PARTTYPE,FSTYPE "$DISK" 2>/dev/null | grep -E "vfat|c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | awk '{print $1}' | head -n 1 || true)
    if [ -n "$ESP_PART" ] && [ -b "$ESP_PART" ]; then
        TMP_ESP=$(mktemp -d /tmp/esp-backup.XXXXXX)
        mount -o ro "$ESP_PART" "$TMP_ESP" 2>/dev/null || mount "$ESP_PART" "$TMP_ESP"
        tar -czf "$BACKUP_DIR/esp-bootloader.tar.gz" -C "$TMP_ESP" .
        umount "$TMP_ESP"
        rmdir "$TMP_ESP"
        log_info "ESP montada temporariamente e copiada com sucesso."
    else
        log_warn "Nenhuma partição ESP localizada para backup."
    fi
fi

# ------------------------------------------------------------------------------
# 5. Backup de /etc
# ------------------------------------------------------------------------------
log_info "4/6. Compactando configurações de sistema (/etc)..."
tar -czf "$BACKUP_DIR/etc.tar.gz" -C / etc --exclude='etc/udev/rules.d/70-persistent-net.rules' 2>/dev/null || true

# ------------------------------------------------------------------------------
# 6. Backup de /home
# ------------------------------------------------------------------------------
log_info "5/6. Compactando arquivos de usuários (/home)..."
tar -czf "$BACKUP_DIR/home.tar.gz" -C / home 2>/dev/null || true

# ------------------------------------------------------------------------------
# 7. Inventário de Pacotes Instalados
# ------------------------------------------------------------------------------
log_info "6/6. Registrando inventário de pacotes do sistema atual..."
if command -v xbps-query >/dev/null 2>&1; then
    xbps-query -l > "$BACKUP_DIR/pacotes-xbps.txt" 2>/dev/null || true
fi

if command -v dpkg >/dev/null 2>&1; then
    dpkg --get-selections > "$BACKUP_DIR/pacotes-dpkg.txt" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 8. Checksum dos Arquivos Gerados
# ------------------------------------------------------------------------------
log_info "Gerando lista de integridade SHA-256..."
(
    cd "$BACKUP_DIR"
    sha256sum * > SHA256SUMS 2>/dev/null || true
)

log_succ "======================================================================"
log_succ "Backup concluído com sucesso!"
log_succ "Local: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"
log_succ "======================================================================"
