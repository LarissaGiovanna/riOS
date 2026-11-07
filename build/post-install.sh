#!/usr/bin/env bash
# ==============================================================================
# riOS — Script de Pós-Instalação (Executado dentro do chroot)
# Configura pacotes, usuários, serviços, display manager e kiosk do riOS
# ==============================================================================
set -euo pipefail

# Cores ANSI para saída de log
CLR_RESET="\033[0m"
CLR_INFO="\033[1;34m"
CLR_WARN="\033[1;33m"
CLR_ERR="\033[1;31m"
CLR_SUCC="\033[1;32m"

log_info() { echo -e "${CLR_INFO}[INFO]${CLR_RESET} $*"; }
log_warn() { echo -e "${CLR_WARN}[AVISO]${CLR_RESET} $*"; }
log_err()  { echo -e "${CLR_ERR}[ERRO]${CLR_RESET} $*" >&2; }
log_succ() { echo -e "${CLR_SUCC}[SUCESSO]${CLR_RESET} $*"; }

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

OVERLAY_DIR="${1:-/tmp/overlay}"
VERSIONS_FILE="${2:-/tmp/VERSIONS.lock}"

log_info "Iniciando post-install do riOS no chroot..."

# ------------------------------------------------------------------------------
# 1. Carregar versões fixadas
# ------------------------------------------------------------------------------
if [ -f "$VERSIONS_FILE" ]; then
    log_info "Carregando definições de $VERSIONS_FILE..."
    # shellcheck disable=SC1090
    source "$VERSIONS_FILE"
else
    log_warn "Arquivo de versões não encontrado em $VERSIONS_FILE. Usando padrões."
fi

SCRCPY_VERSION="${SCRCPY_VERSION:-5.0}"
SCRCPY_SHA256="${SCRCPY_SHA256:-placeholder}"
KERNEL_PACKAGE="${KERNEL_PACKAGE:-linux-image-amd64}"
ADB_PACKAGE="${ADB_PACKAGE:-adb}"

# ------------------------------------------------------------------------------
# 2. Configurar Locale e Hostname
# ------------------------------------------------------------------------------
log_info "Configurando locale pt_BR.UTF-8 e hostname rios..."

echo "pt_BR.UTF-8 UTF-8" > /etc/locale.gen
if command -v locale-gen >/dev/null 2>&1; then
    locale-gen pt_BR.UTF-8
fi

echo "LANG=pt_BR.UTF-8" > /etc/default/locale
echo "rios" > /etc/hostname

cat > /etc/hosts <<'EOF'
127.0.0.1   localhost
127.0.1.1   rios
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

# ------------------------------------------------------------------------------
# 3. Atualizar APT e Instalar Pacotes Essenciais
# ------------------------------------------------------------------------------
log_info "Atualizando repositórios APT..."
apt-get update

PKGS=(
    "$KERNEL_PACKAGE"
    systemd-sysv
    lxqt
    sddm
    "$ADB_PACKAGE"
    xdg-utils
    xbindkeys
    x11-xserver-utils
    xserver-xorg-video-radeon
    firmware-amd-graphics
    systemd-zram-generator
    wget
    ca-certificates
    chrony
    locales
)

log_info "Instalando pacotes base: ${PKGS[*]}..."
apt-get install -y --no-install-recommends "${PKGS[@]}"

# Garantir explicitamente que firmware-brcm80211 NÃO está instalado
# (o netbook 1015BX usa Atheros AR9285 via ath9k, sem firmware proprietário)
if dpkg -s firmware-brcm80211 >/dev/null 2>&1; then
    log_warn "Removendo firmware-brcm80211 desnecessário..."
    apt-get purge -y firmware-brcm80211 || true
fi

# ------------------------------------------------------------------------------
# 4. Instalar scrcpy
# ------------------------------------------------------------------------------
log_info "Configurando scrcpy versão ${SCRCPY_VERSION}..."
SCRCPY_INSTALLED=false
SCRCPY_TARBALL="/tmp/scrcpy-linux-x86_64-v${SCRCPY_VERSION}.tar.gz"
SCRCPY_URL="https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}/scrcpy-linux-x86_64-v${SCRCPY_VERSION}.tar.gz"

log_info "Tentando baixar scrcpy oficial de: $SCRCPY_URL"
if wget --timeout=15 --tries=2 -q "$SCRCPY_URL" -O "$SCRCPY_TARBALL"; then
    log_info "Download concluído. Verificando SHA-256..."
    if [ "$SCRCPY_SHA256" != "placeholder" ] && [ -n "$SCRCPY_SHA256" ]; then
        CALCULATED_SHA=$(sha256sum "$SCRCPY_TARBALL" | awk '{print $1}')
        if [ "$CALCULATED_SHA" = "$SCRCPY_SHA256" ]; then
            log_succ "SHA-256 conferido com sucesso: $CALCULATED_SHA"
        else
            log_err "Divergência de SHA-256! Esperado: $SCRCPY_SHA256, Obtido: $CALCULATED_SHA"
            exit 1
        fi
    else
        log_warn "SCRCPY_SHA256 está marcado como placeholder. Pulando validação estrita."
    fi

    mkdir -p /opt/scrcpy
    tar -xzf "$SCRCPY_TARBALL" -C /opt/scrcpy --strip-components=1 2>/dev/null || tar -xzf "$SCRCPY_TARBALL" -C /opt/scrcpy
    if [ -f /opt/scrcpy/scrcpy ]; then
        ln -sf /opt/scrcpy/scrcpy /usr/local/bin/scrcpy
        chmod +x /opt/scrcpy/scrcpy
        SCRCPY_INSTALLED=true
        log_succ "scrcpy instalado em /opt/scrcpy com link em /usr/local/bin/scrcpy"
    fi
    rm -f "$SCRCPY_TARBALL"
fi

if [ "$SCRCPY_INSTALLED" = false ]; then
    log_warn "Não foi possível instalar scrcpy via tarball oficial. Instalando via apt..."
    apt-get install -y scrcpy || log_warn "Aviso: pacote scrcpy não disponível via apt no momento."
fi

# ------------------------------------------------------------------------------
# 5. Criação do Usuário dex
# ------------------------------------------------------------------------------
log_info "Configurando usuário 'dex' (uid 1000)..."

for grp in audio video plugdev input netdev; do
    groupadd -f "$grp"
done

if ! id "dex" >/dev/null 2>&1; then
    useradd -m -u 1000 -s /bin/bash dex
fi

usermod -aG audio,video,plugdev,input,netdev dex

# ------------------------------------------------------------------------------
# 6. SDDM Autologin
# ------------------------------------------------------------------------------
log_info "Configurando autologin no SDDM para o usuário dex..."
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-autologin.conf <<'EOF'
[Autologin]
User=dex
Session=lxqt.desktop
Relogin=false
EOF

# ------------------------------------------------------------------------------
# 7. Autostart do Kiosk (rios.desktop)
# ------------------------------------------------------------------------------
log_info "Configurando autostart da sessão rios-session..."
mkdir -p /home/dex/.config/autostart
cat > /home/dex/.config/autostart/rios.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=riOS Session
Comment=Kiosk riOS DeX Client
Exec=rios-session
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# ------------------------------------------------------------------------------
# 8. LXQt sem Compositor (economia de CPU/RAM na APU C-60)
# ------------------------------------------------------------------------------
log_info "Configurando LXQt com compositor desativado..."
mkdir -p /home/dex/.config/lxqt
cat > /home/dex/.config/lxqt/lxqt.conf <<'EOF'
[General]
__userfile__=true

[Compositor]
enabled=false
EOF

chown -R dex:dex /home/dex

# ------------------------------------------------------------------------------
# 9. Configuração de ZRAM
# ------------------------------------------------------------------------------
log_info "Configurando systemd-zram-generator..."
mkdir -p /etc/systemd
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 1024)
compression-algorithm = zstd
EOF

# ------------------------------------------------------------------------------
# 10. Desabilitar Serviços Desnecessários
# ------------------------------------------------------------------------------
log_info "Desabilitando serviços não essenciais..."
SERVICES_TO_DISABLE=(
    cups
    avahi-daemon
    modemmanager
    packagekit
    apt-daily.timer
    apt-daily-upgrade.timer
    fstrim.timer
)

for srv in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable "$srv" 2>/dev/null || true
    systemctl mask "$srv" 2>/dev/null || true
done

# ------------------------------------------------------------------------------
# 11. Serviço de Limpeza (rios-cleanup.service)
# ------------------------------------------------------------------------------
log_info "Configurando serviço rios-cleanup.service..."
mkdir -p /usr/local/lib/rios
if [ ! -f /usr/local/lib/rios/cleanup.sh ]; then
    cat > /usr/local/lib/rios/cleanup.sh <<'EOF'
#!/usr/bin/env bash
# riOS — Script de limpeza no encerramento/desconexão
set -euo pipefail
killall -q scrcpy || true
if command -v adb >/dev/null 2>&1; then
    adb shell settings delete global overlay_display_devices 2>/dev/null || true
fi
exit 0
EOF
    chmod +x /usr/local/lib/rios/cleanup.sh
fi

cat > /etc/systemd/system/rios-cleanup.service <<'EOF'
[Unit]
Description=riOS Session Cleanup
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/usr/local/lib/rios/cleanup.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl enable rios-cleanup.service 2>/dev/null || true

# ------------------------------------------------------------------------------
# 12. Aplicar Overlay na Raiz
# ------------------------------------------------------------------------------
if [ -d "$OVERLAY_DIR" ]; then
    log_info "Aplicando arquivos de overlay de $OVERLAY_DIR na raiz..."
    cp -a "$OVERLAY_DIR/." /
    log_succ "Overlay aplicado com sucesso."
else
    log_warn "Diretório de overlay $OVERLAY_DIR não encontrado."
fi

# Salvar cópia do VERSIONS.lock para referência do sistema instalado
mkdir -p /etc/rios
if [ -f "$VERSIONS_FILE" ]; then
    cp "$VERSIONS_FILE" /etc/rios/VERSIONS.lock
fi

# ------------------------------------------------------------------------------
# 13. Limpeza do APT
# ------------------------------------------------------------------------------
log_info "Limpando caches do APT..."
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/*

log_succ "Post-install do riOS concluído com sucesso!"
