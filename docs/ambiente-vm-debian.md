# Ambiente de testes — VM Debian 13

> Gerado automaticamente por `scripts/coleta-ambiente.sh` em 2026-11-26T22:30:52-03:00
> Host: `rios`
>
> Esta é a coleta da **VM de validação** (Debian 13 + systemd + SDDM/LXQt), não do
> netbook. O retrato do Void/netbook continua em
> [`ambiente-de-testes.md`](ambiente-de-testes.md).
>
> **Divergências em relação ao alvo:**
> - a tela da VM é `Virtual-1` em **1280×800**; para o ensaio do DeX, force
>   `RESOLUTION=1024x600` no `/etc/rios/config`;
> - `adb` da VM é **34.0.5-debian** (a bancada usava 36.0.1);
> - `scrcpy` é **5.0**.
>
> **Nota sobre a data:** é a **data do relógio, não confiável**. Se a máquina estiver
> sem NTP, o valor pode estar atrasado; refazer a coleta depois de sincronizar o
> relógio (chrony do M1-01).

## Resumo

| Campo | Valor |
|---|---|
| Modelo | innotek GmbH VirtualBox |
| Distribuição | Debian GNU/Linux 13 (trixie) |
| Kernel | 6.12.117+deb13-amd64 |
| Arquitetura | x86_64 |
| CPU | 13th Gen Intel(R) Core(TM) i5-13450HX |
| RAM total | 1,4 GB |
| Virtualização | VirtualBox (innotek GmbH) |
| Init | systemd 257.13 |
| Sessão gráfica | SDDM + LXQt, X11 |
| Tela | `Virtual-1` 1280×800 |
| adb | 34.0.5-debian |
| scrcpy | 5.0 |

---

## 1. Identificação da máquina

**Data e hora**

```
$ date -Iseconds
2026-11-26T22:30:52-03:00
```

**Modelo / fabricante (DMI)**

```
$ cat /sys/devices/virtual/dmi/id/sys_vendor /sys/devices/virtual/dmi/id/product_name /sys/devices/virtual/dmi/id/product_version 2>/dev/null
innotek GmbH
VirtualBox
1.2
```

**Modelo (DMI, sem root)**

```
$ cat /sys/devices/virtual/dmi/id/product_name
VirtualBox
```

**Modelo (dmidecode) (root)**

```
# dmidecode -s system-product-name
(sem privilégio: rode com "sudo bash coleta-ambiente.sh" ou libere sudo sem senha para este comando)
```

**Número de série**

```
$ echo 'não coletado de propósito (dado identificável, sem valor para o artigo)'
não coletado de propósito (dado identificável, sem valor para o artigo)
```

**Slots e módulos de memória (root)**

```
# dmidecode -t memory | grep -E 'Size|Speed|Type:|Locator|Maximum Capacity' | grep -v 'No Module'
(sem privilégio: rode com "sudo bash coleta-ambiente.sh" ou libere sudo sem senha para este comando)
```

**Resumo de hardware (lshw, se instalado)**

```
$ lshw -short 2>/dev/null || echo 'lshw não instalado (opcional)'
lshw não instalado (opcional)
```

**Tempo ligado**

```
$ uptime -p 2>/dev/null || uptime
up 22 minutes
```

## 2. CPU e memória

**lscpu**

```
$ lscpu
Arquitetura:                               x86_64
Modo(s) operacional da CPU:                32-bit, 64-bit
Tamanhos de endereço:                      39 bits physical, 48 bits virtual
Ordem dos bytes:                           Little Endian
CPU(s):                                    2
Lista de CPU(s) on-line:                   0,1
ID de fornecedor:                          GenuineIntel
Nome do modelo:                            13th Gen Intel(R) Core(TM) i5-13450HX
Família da CPU:                            6
Modelo:                                    183
Thread(s) per núcleo:                      1
Núcleo(s) por soquete:                     2
Soquete(s):                                1
Step:                                      1
BogoMIPS:                                  5222,40
Opções:                                    fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx rdtscp lm constant_tsc rep_good nopl xtopology nonstop_tsc cpuid tsc_known_freq pni pclmulqdq ssse3 fma cx16 pcid sse4_1 sse4_2 x2apic movbe popcnt aes xsave avx f16c rdrand hypervisor lahf_lm abm 3dnowprefetch fsgsbase bmi1 avx2 bmi2 invpcid rdseed adx clflushopt sha_ni arat md_clear flush_l1d arch_capabilities
Fabricante do hipervisor:                  KVM
Tipo de virtualização:                     completo
cache de L1d:                              96 KiB (2 instâncias)
cache de L1i:                              64 KiB (2 instâncias)
cache de L2:                               2,5 MiB (2 instâncias)
cache de L3:                               40 MiB (2 instâncias)
Nó(s) de NUMA:                             1
CPU(s) de nó0 NUMA:                        0,1
Vulnerabilidade Gather data sampling:      Not affected
Vulnerabilidade Indirect target selection: Mitigation; Aligned branch/return thunks
Vulnerabilidade Itlb multihit:             Not affected
Vulnerabilidade L1tf:                      Not affected
Vulnerabilidade Mds:                       Not affected
Vulnerabilidade Meltdown:                  Not affected
Vulnerabilidade Mmio stale data:           Not affected
Vulnerabilidade Reg file data sampling:    Mitigation; Clear Register File
Vulnerabilidade Retbleed:                  Not affected
Vulnerabilidade Spec rstack overflow:      Not affected
Vulnerabilidade Spec store bypass:         Vulnerable
Vulnerabilidade Spectre v1:                Mitigation; usercopy/swapgs barriers and __user pointer sanitization
Vulnerabilidade Spectre v2:                Mitigation; Retpolines; STIBP disabled; RSB filling; PBRSB-eIBRS Not affected; BHI SW loop, KVM SW loop
Vulnerabilidade Srbds:                     Not affected
Vulnerabilidade Tsa:                       Not affected
Vulnerabilidade Tsx async abort:           Not affected
Vulnerabilidade Vmscape:                   Not affected
```

**Memória (free -h)**

```
$ free -h
               total       usada       livre    compart.  buff/cache  disponível
Mem.:          1,4Gi       1,2Gi        88Mi        27Mi       291Mi       215Mi
Swap:          2,2Gi       488Mi       1,7Gi
```

**Memória útil (MemAvailable)**

```
$ grep -E 'MemTotal|MemAvailable|SwapTotal' /proc/meminfo
MemTotal:        1485660 kB
MemAvailable:     220668 kB
SwapTotal:       2294776 kB
```

**Swap / zram**

```
$ swapon --show 2>/dev/null || echo 'nenhum swap ativo'
nenhum swap ativo
```

**zram configurado?**

```
$ ls -1 /sys/block/ 2>/dev/null | grep -i zram || echo 'sem zram'
zram0
```

## 3. Sistema operacional

**Distribuição (/etc/os-release)**

```
$ cat /etc/os-release
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
NAME="Debian GNU/Linux"
VERSION_ID="13"
VERSION="13 (trixie)"
VERSION_CODENAME=trixie
DEBIAN_VERSION_FULL=13.7
ID=debian
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"
```

**Init / gerenciador de serviços**

```
$ if [ -d /run/systemd/system ]; then echo systemd; elif [ -d /etc/sv ]; then echo runit; elif command -v rc-service >/dev/null 2>&1; then echo openrc; else echo 'desconhecido'; fi
systemd
```

**Kernel e arquitetura**

```
$ uname -a
Linux rios 6.12.117+deb13-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.12.117-1 (2026-11-12) x86_64 GNU/Linux
```

**Versão detalhada**

```
$ cat /etc/debian_version 2>/dev/null || cat /etc/lsb-release 2>/dev/null || echo 'n/d'
13.7
```

**Serviços com falha**

```
$ case "$(command -v systemctl)" in '') if [ -d /etc/sv ]; then sv -a status 2>/dev/null | grep -v '^run:' || echo 'todos os serviços rodando'; else echo 'init não reconhecido'; fi ;; *) systemctl --failed --no-pager 2>/dev/null ;; esac
  UNIT LOAD ACTIVE SUB DESCRIPTION

0 loaded units listed.
```

**Pacotes instalados (contagem)**

```
$ if command -v dpkg >/dev/null; then dpkg -l | grep -c '^ii'; elif command -v xbps-query >/dev/null; then xbps-query -l | grep -c '^ii'; elif command -v pacman >/dev/null; then pacman -Q | wc -l; else echo 'n/d'; fi
830
```

**Sessão gráfica e serviço**

```
$ echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-} XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-} DISPLAY=${DISPLAY:-}"
XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=LXQt DISPLAY=:0

$ systemctl get-default
graphical.target

$ loginctl show-session 3 -p Service -p Type -p Desktop -p TTY
Service=sddm
Type=x11
Desktop=LXQt
TTY=tty2

$ systemd --version | head -1
systemd 257 (257.13-1~deb13u1)
```

A unidade `rios-session.service` ainda não está instalada nesta coleta; a
validação do serviço e do boot será registrada no fechamento da M1-02.

## 4. Vídeo e tela

**Resolução / saídas (xrandr)**

```
$ if command -v xrandr >/dev/null 2>&1 && xrandr >/dev/null 2>&1; then xrandr; else echo 'xrandr indisponível (sessão gráfica não está rodando)'; echo; echo '--- modos suportados pelo kernel (DRM) ---'; for m in /sys/class/drm/card*/modes; do [ -s "$m" ] && { echo "$m:"; head -5 "$m"; }; done; echo '--- status das saídas ---'; for s in /sys/class/drm/card*-\*/status; do [ -s "$s" ] && printf '%s: %s\n' "$s" "$(cat "$s")"; done; fi
Screen 0: minimum 320 x 200, current 1280 x 800, maximum 16384 x 16384
Virtual-1 connected primary 1280x800+0+0 (normal left inverted right x axis y axis) 0mm x 0mm
   1280x800      60.00*+  59.81    59.91  
   4096x2160     60.00    59.94  
   2560x1600     59.99    59.97  
   1920x1440     60.00  
   1856x1392     60.00  
   1792x1344     60.00  
   2048x1152     60.00  
   1920x1200     59.88    59.95  
   1920x1080     60.00  
   1600x1200     60.00  
   1680x1050     59.95    59.88  
   1400x1050     59.98    59.95  
   1600x900      60.00  
   1280x1024     60.02  
   1440x900      59.89    59.90  
   1280x960      60.00  
   1366x768      59.79    60.00  
   1360x768      60.02  
   1280x768      59.87    59.99  
   1280x720      60.00  
   1024x768      60.00  
   800x600       60.32    56.25  
   848x480       60.00  
   640x480       59.94  
Virtual-2 disconnected (normal left inverted right x axis y axis)
Virtual-3 disconnected (normal left inverted right x axis y axis)
Virtual-4 disconnected (normal left inverted right x axis y axis)
Virtual-5 disconnected (normal left inverted right x axis y axis)
Virtual-6 disconnected (normal left inverted right x axis y axis)
Virtual-7 disconnected (normal left inverted right x axis y axis)
Virtual-8 disconnected
```

**Driver em uso**

```
$ lspci -nnk 2>/dev/null | grep -A3 -i 'vga\|display' || echo 'lspci indisponível'
00:02.0 VGA compatible controller [0300]: VMware SVGA II Adapter [15ad:0405]
	Subsystem: VMware SVGA II Adapter [15ad:0405]
	Kernel driver in use: vmwgfx
	Kernel modules: vmwgfx
00:03.0 Ethernet controller [0200]: Intel Corporation 82540EM Gigabit Ethernet Controller [8086:100e] (rev 02)
```

**Módulos de vídeo carregados**

```
$ lsmod 2>/dev/null | grep -E 'radeon|amdgpu|i915|drm' || echo 'nenhum'
drm_ttm_helper         16384  2 vmwgfx
ttm                   102400  2 vmwgfx,drm_ttm_helper
drm_kms_helper        253952  2 vmwgfx,drm_ttm_helper
drm                   774144  7 vmwgfx,drm_kms_helper,drm_ttm_helper,ttm
```

**Aceleração GL (se houver)**

```
$ glxinfo -B 2>/dev/null | head -20 || echo 'glxinfo indisponível'
```

## 5. USB

**Dispositivos USB (lsusb)**

```
$ lsusb 2>/dev/null || echo 'lsusb indisponível (apt install usbutils)'
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 001 Device 002: ID 04e8:6860 Samsung Electronics Co., Ltd Galaxy series, misc. (MTP mode)
Bus 002 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 002 Device 002: ID 80ee:0021 VirtualBox USB Tablet
```

**Árvore USB (lsusb -t)**

```
$ lsusb -t 2>/dev/null || echo 'n/d'
/:  Bus 001.Port 001: Dev 001, Class=root_hub, Driver=ehci-pci/12p, 480M
    |__ Port 001: Dev 002, If 0, Class=Imaging, Driver=[none], 480M
    |__ Port 001: Dev 002, If 1, Class=Communications, Driver=cdc_acm, 480M
    |__ Port 001: Dev 002, If 2, Class=CDC Data, Driver=cdc_acm, 480M
/:  Bus 002.Port 001: Dev 001, Class=root_hub, Driver=ohci-pci/12p, 12M
    |__ Port 001: Dev 002, If 0, Class=Human Interface Device, Driver=usbhid, 12M
```

**Versão do USB (lspci)**

```
$ lspci 2>/dev/null | grep -i usb || echo 'n/d'
00:06.0 USB controller: Apple Inc. KeyLargo/Intrepid USB
00:0b.0 USB controller: Intel Corporation 82801FB/FBM/FR/FW/FRW (ICH6 Family) USB2 EHCI Controller
```

## 6. Armazenamento

**Discos e partições (lsblk)**

```
$ lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
NAME    SIZE TYPE FSTYPE MOUNTPOINT MODEL
sda      40G disk                   VBOX HARDDISK
├─sda1  976M part vfat   /boot/efi  
├─sda2 37,6G part ext4   /          
└─sda3  1,5G part swap   [SWAP]     
sr0    1024M rom                    VBOX CD-ROM
zram0   725M disk swap   [SWAP]     
```

**Uso de espaço (df -h)**

```
$ df -h -x tmpfs -x devtmpfs
Sist. Arq.      Tam. Usado Disp. Uso% Montado em
/dev/sda2        37G  4,1G   31G  12% /
efivarfs        256K   50K  202K  20% /sys/firmware/efi/efivars
/dev/sda1       975M  9,1M  966M   1% /boot/efi
```

**Modelo do disco**

```
$ lsblk -dno MODEL 2>/dev/null
VBOX HARDDISK
VBOX CD-ROM

```

## 7. Rede

**Endereços IP**

```
$ ip -4 addr show 2>/dev/null | grep -E 'inet |^[0-9]' || ifconfig 2>/dev/null
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    inet 127.0.0.1/8 scope host lo
2: enp0s3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    inet 10.x.x.x/24 brd 10.x.x.x scope global dynamic noprefixroute enp0s3
```

**Rota padrão**

```
$ ip route 2>/dev/null | head -5
default via 10.x.x.x dev enp0s3 proto dhcp src 10.x.x.x metric 1002 
10.x.x.x/24 dev enp0s3 proto dhcp scope link src 10.x.x.x metric 1002 
```

**Wi-Fi / firmware**

```
$ lspci -nnk 2>/dev/null | grep -A3 -i 'network\|wireless' || echo 'n/d'
n/d
```

**Conectividade (ping curto)**

```
$ ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && echo 'internet OK' || echo 'sem internet'
internet OK
```

**SSH ativo? (porta 22)**

```
$ ss -ltn 2>/dev/null | grep -q ':22 ' && echo 'sshd escutando na porta 22' || echo 'porta 22 fechada'
sshd escutando na porta 22
```

## 8. Ferramentas do projeto

**adb**

```
$ adb version 2>/dev/null || echo 'adb não instalado'
Android Debug Bridge version 1.0.41
Version 34.0.5-debian
Installed as /usr/lib/android-sdk/platform-tools/adb
Running on Linux 6.12.117+deb13-amd64 (x86_64)
```

**scrcpy**

```
$ scrcpy --version 2>/dev/null || echo 'scrcpy não instalado'
scrcpy 5.0 <https://github.com/Genymobile/scrcpy>

Dependencies (compiled / linked):
 - SDL: 3.4.18 / 3.4.18
 - libavcodec: 63.1.102 / 63.1.102
 - libavformat: 63.1.102 / 63.1.102
 - libavutil: 61.1.102 / 61.1.102
 - libavdevice: 63.1.102 / 63.1.102
 - libusb: - / 1.0.30
```

**ffmpeg**

```
$ ffmpeg -version 2>/dev/null | head -1 || echo 'ffmpeg não instalado'
```

**Python**

```
$ python3 --version 2>/dev/null || echo 'n/d'
Python 3.13.5
```

**Localização dos binários**

```
$ command -v adb scrcpy ffmpeg python3 2>/dev/null || echo 'n/d'
/usr/bin/adb
/usr/local/bin/scrcpy
/usr/bin/python3
```

## 9. Energia

**Bateria**

```
$ f=0; for b in /sys/class/power_supply/BAT*; do [ -d "$b" ] || continue; f=1; echo "$b"; cat "$b/status" "$b/energy_now" "$b/energy_full" 2>/dev/null; cat "$b/charge_now" "$b/charge_full" 2>/dev/null; done; [ $f -eq 1 ] || echo 'sem bateria detectada'
/sys/class/power_supply/BAT0
Not charging
49500000
50000000
```

**Temperatura (se disponível)**

```
$ sensors 2>/dev/null | head -20 || echo 'lm-sensors não instalado'
```

## 10. Celular conectado

> Preenchido apenas se o Galaxy estiver plugado e autorizado.

Nenhum aparelho no estado `device`.

```
$ adb devices
List of devices attached

```

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

> IPs privados e endereços MAC foram mascarados (`--mascarar`) antes da publicação.
