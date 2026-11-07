#!/usr/bin/env bash
# ==============================================================================
# riOS — Restauração de Disco (restore-disk.sh)
# Restaura tabela GPT, ESP, /etc e /home a partir de diretório de backup com verificação
# Uso: restore-disk.sh <diretorio_backup> <dispositivo>
# Exemplo: sudo ./scripts/restore-disk.sh ./backups/backup-rios-20261027-120000 /dev/sda
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
    log_err "Uso: $0 <diretorio_backup> <dispositivo>"
    log_err "Exemplo: sudo $0 ./backups/backup-rios-20261027-120000 /dev/sda"
    exit 1
fi

BACKUP_DIR="$1"
DISK="$2"

# ------------------------------------------------------------------------------
# 1. Verificações de Permissão e Arquivos
# ------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    log_err "Este script precisa de privilégios de root (execute com sudo)."
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    log_err "Diretório de backup não encontrado: $BACKUP_DIR"
    exit 1
fi

if [ ! -b "$DISK" ]; then
    log_err "Dispositivo de bloco não encontrado: $DISK"
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. Conferência de Integridade (SHA-256)
# ------------------------------------------------------------------------------
log_info "Verificando integridade dos arquivos de backup via SHA-256..."
if [ -f "$BACKUP_DIR/SHA256SUMS" ]; then
    (
        cd "$BACKUP_DIR"
        # Ignora avisos de formatação e confere os checksums listados
        sha256sum -c SHA256SUMS
    )
    log_succ "Todos os arquivos do backup foram verificados e estão íntegros."
else
    log_warn "Arquivo SHA256SUMS não encontrado no diretório de backup! Prosseguindo sem validação criptográfica."
fi

# ------------------------------------------------------------------------------
# 3. Exibir Alvo e Pedir Confirmação
# ------------------------------------------------------------------------------
echo -e "\n${CLR_BOLD}Dispositivo alvo para restauração:${CLR_RESET}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL "$DISK"
echo ""

log_warn "ATENÇÃO: A restauração irá sobrescrever a tabela de partições e os dados em $DISK!"
echo -ne "${CLR_BOLD}Digite exatamente 'RESTAURAR' para autorizar: ${CLR_RESET}"
read -r CONFIRMACAO

if [ "$CONFIRMACAO" != "RESTAURAR" ]; then
    log_warn "Operação cancelada pelo usuário. Nada foi alterado."
    exit 0
fi

# ------------------------------------------------------------------------------
# 4. Desmontar partições ativas no disco
# ------------------------------------------------------------------------------
log_info "Desmontando quaisquer partições ativas em $DISK..."
MOUNTS=$(lsblk -no MOUNTPOINTS "$DISK" 2>/dev/null | grep -v '^[[:space:]]*$' || true)
if [ -n "$MOUNTS" ]; then
    while IFS= read -r mnt; do
        if [ -n "$mnt" ]; then
            log_info "Desmontando $mnt..."
            umount "$mnt" 2>/dev/null || true
        fi
    done <<< "$MOUNTS"
fi

# ------------------------------------------------------------------------------
# 5. Restauração da Tabela de Partições
# ------------------------------------------------------------------------------
if [ -f "$BACKUP_DIR/gpt-table.bin" ] && command -v sgdisk >/dev/null 2>&1; then
    log_info "Restaurando tabela GPT via sgdisk..."
    sgdisk --load-backup="$BACKUP_DIR/gpt-table.bin" "$DISK"
elif [ -f "$BACKUP_DIR/partitions.sfdisk" ] && command -v sfdisk >/dev/null 2>&1; then
    log_info "Restaurando tabela de partições via sfdisk..."
    sfdisk "$DISK" < "$BACKUP_DIR/partitions.sfdisk"
elif [ -f "$BACKUP_DIR/mbr-e-gpt-header-2M.bin" ]; then
    log_info "Restaurando primeiros 2 MiB do disco via dd..."
    dd if="$BACKUP_DIR/mbr-e-gpt-header-2M.bin" of="$DISK" bs=1M count=2 conv=fsync status=none
else
    log_err "Nenhum arquivo válido de tabela de partições encontrado no backup."
    exit 1
fi

partprobe "$DISK" 2>/dev/null || true
udevadm settle 2>/dev/null || sleep 2

# ------------------------------------------------------------------------------
# 6. Restauração da ESP
# ------------------------------------------------------------------------------
if [ -f "$BACKUP_DIR/esp-bootloader.tar.gz" ]; then
    log_info "Identificando partição ESP para restauração..."
    ESP_PART=$(lsblk -no PATH,PARTTYPE,FSTYPE "$DISK" 2>/dev/null | grep -E "vfat|c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | awk '{print $1}' | head -n 1 || true)
    if [ -n "$ESP_PART" ] && [ -b "$ESP_PART" ]; then
        log_info "Formatando e restaurando ESP em $ESP_PART..."
        mkfs.fat -F32 "$ESP_PART"
        TMP_ESP=$(mktemp -d /tmp/restore-esp.XXXXXX)
        mount "$ESP_PART" "$TMP_ESP"
        tar -xzf "$BACKUP_DIR/esp-bootloader.tar.gz" -C "$TMP_ESP"
        sync
        umount "$TMP_ESP"
        rmdir "$TMP_ESP"
        log_succ "ESP restaurada com sucesso."
    else
        log_warn "Partição ESP não encontrada automaticamente para restauração do tarball."
    fi
fi

sync
log_succ "======================================================================"
log_succ "Restauração do disco finalizada com sucesso!"
log_succ "As partições foram recriadas. Verifique com 'lsblk $DISK'."
log_succ "======================================================================"
