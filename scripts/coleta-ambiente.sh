#!/usr/bin/env bash
# coleta-ambiente.sh — coleta o ambiente de testes (tarefa S1-P1-01)
#
# Uso:
#   ./coleta-ambiente.sh              # gera ./ambiente-de-testes.md
#   ./coleta-ambiente.sh saida.md    # nome/arquivo alternativo
#
# Roda sem root. Se você quiser os dados que só o root lê (dmidecode, lshw),
# execute com sudo. O script detecta sozinho:
#   - rodando como root  → usa root direto;
#   - sudo sem senha     → usa "sudo -n";
#   - sem nenhum dos dois → apenas marca a seção como "precisa de root".
# Não usa "set -e" de propósito: comando ausente não pode abortar a coleta.

set -uo pipefail

MASCARAR="${MASCARAR:-0}"
if [ "${1:-}" = "--mascarar" ]; then MASCARAR=1; shift; fi

OUT="${1:-ambiente-de-testes.md}"
DATA_ISO="$(date -Iseconds)"
HOST="$(hostname 2>/dev/null || echo desconhecido)"
DONO_ORIGINAL="${SUDO_USER:-}"

# ---------------------------------------------------------------- utilitários

run() {
    # run "descrição" 'comando a executar'
    local desc="$1" cmd="$2"
    printf '\n**%s**\n\n```\n$ %s\n' "$desc" "$cmd"
    if bash -c "$cmd" >/tmp/coleta.$$ 2>&1; then
        cat /tmp/coleta.$$
    else
        local rc=$?
        cat /tmp/coleta.$$
        printf '\n(saída com código %s)\n' "$rc"
    fi
    rm -f /tmp/coleta.$$
    printf '```\n'
}

run_root() {
    local desc="$1" cmd="$2"
    printf '\n**%s (root)**\n\n```\n# %s\n' "$desc" "$cmd"
    if como_root "$cmd" >/tmp/coleta.$$ 2>&1; then
        cat /tmp/coleta.$$
    else
        local rc=$?
        cat /tmp/coleta.$$
        printf '\n(saída com código %s)\n' "$rc"
    fi
    rm -f /tmp/coleta.$$
    printf '```\n'
}

tem() { command -v "$1" >/dev/null 2>&1; }

# Descobre o gerenciador de serviços — o netbook pode não ser systemd (Void usa runit).
init_sistema() {
    if tem systemctl && [ -d /run/systemd/system ]; then echo systemd
    elif [ -d /etc/sv ] && tem sv; then echo runit
    elif tem rc-service; then echo openrc
    else echo desconhecido
    fi
}

servico_ativo() { # servico_ativo ssh|sshd
    local s="$1"
    case "$(init_sistema)" in
        systemd) systemctl is-active --quiet "$s" 2>/dev/null && echo ativo || echo inativo ;;
        runit)   sv status "$s" 2>/dev/null | grep -q '^run:' && echo ativo || echo inativo ;;
        openrc)  rc-service "$s" status >/dev/null 2>&1 && echo ativo || echo inativo ;;
        *)       echo 'n/d' ;;
    esac
}

pacotes_instalados() {
    if tem dpkg; then dpkg -l 2>/dev/null | grep -c '^ii'
    elif tem xbps-query; then xbps-query -l 2>/dev/null | grep -c '^ii'
    elif tem pacman; then pacman -Q 2>/dev/null | wc -l
    elif tem rpm; then rpm -qa 2>/dev/null | wc -l
    else echo 'n/d'; fi
}

# como_root "comando" — executa com privilégio quando possível, sem travar esperando senha.
# Assim, um script rodado por SSH nunca fica parado num prompt invisível.
como_root() {
    local cmd="$1"
    if [ "$(id -u)" -eq 0 ]; then
        bash -c "$cmd"
    elif sudo -n true 2>/dev/null; then
        sudo -n bash -c "$cmd"
    else
        printf '(sem privilégio: rode com "sudo bash %s" ou libere sudo sem senha para este comando)\n' \
            "$(basename "$0")"
        return 0
    fi
}

valor_debian() { # valor_debian ARQUIVO CHAVE
    [ -r "$1" ] || { echo ""; return; }
    sed -n "s/^$2=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$1" | head -1
}

# ---------------------------------------------------------------- cabeçalho

{
    echo "# Ambiente de testes — DeX Station"
    echo
    echo "> Gerado automaticamente por \`scripts/coleta-ambiente.sh\` em $DATA_ISO"
    echo "> Host: \`$HOST\`"
    echo
    echo "## Resumo"
    echo
    local_distro="$(valor_debian /etc/os-release PRETTY_NAME)"
    local_kernel="$(uname -r 2>/dev/null)"
    local_cpu="$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1)"
    local_ram="$(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null)"
    local_model="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)"
    local_vendor="$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null)"
    echo "| Campo | Valor |"
    echo "|---|---|"
    echo "| Modelo | ${local_vendor:-?} ${local_model:-?} |"
    echo "| Distribuição | ${local_distro:-?} |"
    echo "| Kernel | ${local_kernel:-?} |"
    echo "| Arquitetura | $(uname -m 2>/dev/null) |"
    echo "| CPU | ${local_cpu:-?} |"
    echo "| RAM total | ${local_ram:-?} |"
} > "$OUT"

# ---------------------------------------------------------------- 1. máquina

{
    echo
    echo "---"
    echo
    echo "## 1. Identificação da máquina"
} >> "$OUT"

run "Data e hora" "date -Iseconds" >> "$OUT"
run "Modelo / fabricante (DMI)" "cat /sys/devices/virtual/dmi/id/sys_vendor /sys/devices/virtual/dmi/id/product_name /sys/devices/virtual/dmi/id/product_version 2>/dev/null" >> "$OUT"
run "Modelo (DMI, sem root)" "cat /sys/devices/virtual/dmi/id/product_name" >> "$OUT"
run_root "Modelo (dmidecode)" "dmidecode -s system-product-name" >> "$OUT"
run "Número de série" "echo 'não coletado de propósito (dado identificável, sem valor para o artigo)'" >> "$OUT"
run_root "Slots e módulos de memória" "dmidecode -t memory | grep -E 'Size|Speed|Type:|Locator|Maximum Capacity' | grep -v 'No Module'" >> "$OUT"
run "Resumo de hardware (lshw, se instalado)" "lshw -short 2>/dev/null || echo 'lshw não instalado (opcional)'" >> "$OUT"run "Tempo ligado" "uptime -p 2>/dev/null || uptime" >> "$OUT"

# ---------------------------------------------------------------- 2. CPU e RAM

{
    echo
    echo "## 2. CPU e memória"
} >> "$OUT"

run "lscpu" "lscpu" >> "$OUT"
run "Memória (free -h)" "free -h" >> "$OUT"
run "Memória útil (MemAvailable)" "grep -E 'MemTotal|MemAvailable|SwapTotal' /proc/meminfo" >> "$OUT"
run "Swap / zram" "swapon --show 2>/dev/null || echo 'nenhum swap ativo'" >> "$OUT"
run "zram configurado?" "ls -1 /sys/block/ 2>/dev/null | grep -i zram || echo 'sem zram'" >> "$OUT"

# ---------------------------------------------------------------- 3. sistema

{
    echo
    echo "## 3. Sistema operacional"
} >> "$OUT"

run "Distribuição (/etc/os-release)" "cat /etc/os-release" >> "$OUT"
run "Init / gerenciador de serviços" "if [ -d /run/systemd/system ]; then echo systemd; elif [ -d /etc/sv ]; then echo runit; elif command -v rc-service >/dev/null 2>&1; then echo openrc; else echo 'desconhecido'; fi" >> "$OUT"
run "Kernel e arquitetura" "uname -a" >> "$OUT"
run "Versão detalhada" "cat /etc/debian_version 2>/dev/null || cat /etc/lsb-release 2>/dev/null || echo 'n/d'" >> "$OUT"
run "Serviços com falha" "case \"\$(command -v systemctl)\" in '') if [ -d /etc/sv ]; then sv -a status 2>/dev/null | grep -v '^run:' || echo 'todos os serviços rodando'; else echo 'init não reconhecido'; fi ;; *) systemctl --failed --no-pager 2>/dev/null ;; esac" >> "$OUT"
run "Pacotes instalados (contagem)" "if command -v dpkg >/dev/null; then dpkg -l | grep -c '^ii'; elif command -v xbps-query >/dev/null; then xbps-query -l | grep -c '^ii'; elif command -v pacman >/dev/null; then pacman -Q | wc -l; else echo 'n/d'; fi" >> "$OUT"

# ---------------------------------------------------------------- 4. vídeo

{
    echo
    echo "## 4. Vídeo e tela"
} >> "$OUT"

run "Resolução / saídas (xrandr)" "if command -v xrandr >/dev/null 2>&1 && xrandr >/dev/null 2>&1; then xrandr; else echo 'xrandr indisponível (sessão gráfica não está rodando)'; echo; echo '--- modos suportados pelo kernel (DRM) ---'; for m in /sys/class/drm/card*/modes; do [ -s \"\$m\" ] && { echo \"\$m:\"; head -5 \"\$m\"; }; done; echo '--- status das saídas ---'; for s in /sys/class/drm/card*-\*/status; do [ -s \"\$s\" ] && printf '%s: %s\n' \"\$s\" \"\$(cat \"\$s\")\"; done; fi" >> "$OUT"
run "Driver em uso" "lspci -nnk 2>/dev/null | grep -A3 -i 'vga\|display' || echo 'lspci indisponível'" >> "$OUT"
run "Módulos de vídeo carregados" "lsmod 2>/dev/null | grep -E 'radeon|amdgpu|i915|drm' || echo 'nenhum'" >> "$OUT"
run "Aceleração GL (se houver)" "glxinfo -B 2>/dev/null | head -20 || echo 'glxinfo indisponível'" >> "$OUT"

# ---------------------------------------------------------------- 5. USB

{
    echo
    echo "## 5. USB"
} >> "$OUT"

run "Dispositivos USB (lsusb)" "lsusb 2>/dev/null || echo 'lsusb indisponível (apt install usbutils)'" >> "$OUT"
run "Árvore USB (lsusb -t)" "lsusb -t 2>/dev/null || echo 'n/d'" >> "$OUT"
run "Versão do USB (lspci)" "lspci 2>/dev/null | grep -i usb || echo 'n/d'" >> "$OUT"

# ---------------------------------------------------------------- 6. disco

{
    echo
    echo "## 6. Armazenamento"
} >> "$OUT"

run "Discos e partições (lsblk)" "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL" >> "$OUT"
run "Uso de espaço (df -h)" "df -h -x tmpfs -x devtmpfs" >> "$OUT"
run "Modelo do disco" "lsblk -dno MODEL 2>/dev/null" >> "$OUT"

# ---------------------------------------------------------------- 7. rede

{
    echo
    echo "## 7. Rede"
} >> "$OUT"

run "Endereços IP" "ip -4 addr show 2>/dev/null | grep -E 'inet |^[0-9]' || ifconfig 2>/dev/null" >> "$OUT"
run "Rota padrão" "ip route 2>/dev/null | head -5" >> "$OUT"
run "Wi-Fi / firmware" "lspci -nnk 2>/dev/null | grep -A3 -i 'network\|wireless' || echo 'n/d'" >> "$OUT"
run "Conectividade (ping curto)" "ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && echo 'internet OK' || echo 'sem internet'" >> "$OUT"
run "SSH ativo? (porta 22)" "ss -ltn 2>/dev/null | grep -q ':22 ' && echo 'sshd escutando na porta 22' || echo 'porta 22 fechada'" >> "$OUT"

# ---------------------------------------------------------------- 8. ferramentas

{
    echo
    echo "## 8. Ferramentas do projeto"
} >> "$OUT"

run "adb" "adb version 2>/dev/null || echo 'adb não instalado'" >> "$OUT"
run "scrcpy" "scrcpy --version 2>/dev/null || echo 'scrcpy não instalado'" >> "$OUT"
run "ffmpeg" "ffmpeg -version 2>/dev/null | head -1 || echo 'ffmpeg não instalado'" >> "$OUT"
run "Python" "python3 --version 2>/dev/null || echo 'n/d'" >> "$OUT"
run "Localização dos binários" "command -v adb scrcpy ffmpeg python3 2>/dev/null || echo 'n/d'" >> "$OUT"

# ---------------------------------------------------------------- 9. energia

{
    echo
    echo "## 9. Energia"
} >> "$OUT"

run "Bateria" "f=0; for b in /sys/class/power_supply/BAT*; do [ -d \"\$b\" ] || continue; f=1; echo \"\$b\"; cat \"\$b/status\" \"\$b/energy_now\" \"\$b/energy_full\" 2>/dev/null; cat \"\$b/charge_now\" \"\$b/charge_full\" 2>/dev/null; done; [ \$f -eq 1 ] || echo 'sem bateria detectada'" >> "$OUT"
run "Temperatura (se disponível)" "sensors 2>/dev/null | head -20 || echo 'lm-sensors não instalado'" >> "$OUT"

# ---------------------------------------------------------------- 10. celular

{
    echo
    echo "## 10. Celular conectado"
    echo
    echo "> Preenchido apenas se o Galaxy estiver plugado e autorizado."
} >> "$OUT"

if tem adb; then
    ESTADO="$(adb devices 2>/dev/null | sed -n '2p')"
    if printf '%s' "$ESTADO" | grep -q 'device$'; then
        {
            run "Modelo" "adb shell getprop ro.product.model" 
            run "Fabricante" "adb shell getprop ro.product.manufacturer"
            run "Android (versão)" "adb shell getprop ro.build.version.release"
            run "Nível de API (SDK)" "adb shell getprop ro.build.version.sdk"
            run "One UI" "adb shell getprop ro.build.version.oneui"
            run "Build" "adb shell getprop ro.build.display.id"
            run "Resolução da tela" "adb shell wm size"
            run "Densidade (DPI)" "adb shell wm density"
            run "Idioma / layout" "adb shell getprop persist.sys.locale; adb shell settings get secure default_input_method"
        } >> "$OUT"
    else
        {
            echo
            echo "Nenhum aparelho no estado \`device\`."
            echo
            echo '```'
            echo "\$ adb devices"
            adb devices 2>&1
            echo '```'
        } >> "$OUT"
    fi
else
    printf '\n`adb` não instalado — seção deixada para preenchimento manual.\n' >> "$OUT"
fi

# ---------------------------------------------------------------- 11. fotos

cat >> "$OUT" <<'FIM'

---

## 11. Fotos do setup (anexar no repositório)

Guardar em `docs/fotos/` com estes nomes:

- [ ] `01-netbook-fechado.jpg` — etiqueta do modelo embaixo
- [ ] `02-portas-laterais.jpg` — USB, HDMI, VGA, P2 e leitor de SD visíveis
- [ ] `03-bancada.jpg` — netbook + celular + cabo/hub na posição de uso
- [ ] `04-cabo-hub.jpg` — detalhe do hub/carregador usado
- [ ] `05-tela-ligada.jpg` — resolução e sistema em execução

## 12. Observações

- Hub / carregador usado:
- Cabo USB (modelo, comprimento):
- Estado da bateria do netbook (% e saúde):
- Distro de origem (antes de qualquer instalação):
- Algo fora do padrão:

## 13. Conferência (P4)

- [ ] Todas as seções acima preenchidas
- [ ] Fotos anexadas em `docs/fotos/`
- [ ] Versões de `adb`/`scrcpy` batem com `build/VERSIONS.lock`
- [ ] Nenhum "n/d" sem justificativa
FIM

# ---------------------------------------------------------------- anonimização

# Mascara o que não deve ir para um repositório público: IPs privados e MACs.
# Use com --mascarar (ou MASCARAR=1) quando o documento for publicado.
if [ "$MASCARAR" = "1" ]; then
    sed -i -E \
        -e 's/(^|[^0-9.])192\.168\.[0-9]{1,3}\.[0-9]{1,3}/\1192.168.x.x/g' \
        -e 's/(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/\110.x.x.x/g' \
        -e 's/(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}/\1172.16-31.x.x/g' \
        -e 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/xx:xx:xx:xx:xx:xx/g' \
        "$OUT"
    {
        echo
        echo "> IPs privados e endereços MAC foram mascarados (\`--mascarar\`) antes da publicação."
    } >> "$OUT"
    printf 'IPs privados e MACs mascarados em %s.\n' "$OUT"
fi

# Se foi rodado com "sudo bash ...", devolve o arquivo para o usuário — senão ele fica
# com dono root e o git (rodando como usuário) não consegue nem ler.
if [ -n "$DONO_ORIGINAL" ] && [ "$(id -u)" -eq 0 ]; then
    chown "$DONO_ORIGINAL": "$OUT" 2>/dev/null && \
        printf 'Propriedade do arquivo devolvida para %s.\n' "$DONO_ORIGINAL"
fi

if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    printf '\nObservação: seções "(root)" ficaram vazias.\n'
    printf 'Para preenchê-las, rode: sudo bash %s %s\n' "$(basename "$0")" "$OUT"
fi

printf '\nArquivo gerado: %s\n' "$OUT"
printf 'Próximo passo: revisar, anexar as fotos e commitar em docs/.\n'
