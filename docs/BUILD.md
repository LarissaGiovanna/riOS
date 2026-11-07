# riOS — Manual de Construção da Imagem e Gravação

Este documento detalha o processo de compilação da imagem do **riOS** (`rios.img`), a conferência de integridade com SHA-256 e os procedimentos para criação do **Live USB** e **Instalação no HD** do netbook alvo (**Asus Eee PC 1015BX**).

---

## 1. Visão Geral da Arquitetura de Build

O build da imagem **não deve ser executado no netbook alvo** (o Eee PC 1015BX possui CPU AMD C-60 lenta, 1,5 GiB de RAM e HDD de 5400 rpm). A imagem é construída em um computador de desenvolvimento (host x86_64 rodando Debian, Ubuntu ou Linux Mint).

```
Host de Bancada (x86_64 / Linux Mint, Debian ou Ubuntu)
  │
  ├── 1. build/build-rios.sh (fallocate + losetup + parted GPT)
  ├── 2. debootstrap trixie (main, contrib, non-free-firmware)
  ├── 3. chroot + build/post-install.sh (LXQt, SDDM, adb, scrcpy, zram)
  ├── 4. grub-install UEFI (x86_64-efi, --removable, bootloader-id=rios)
  └── 5. rios.img (~3 GB) + SHA256SUMS
```

A partir do mesmo artefato (`rios.img`), suportam-se duas formas de implantação:
- **Variante A — Live USB**: gravada em pendrive via [`scripts/make-live-usb.sh`](../scripts/make-live-usb.sh), permitindo validação com o HD interno 100% intocado.
- **Variante B — Instalação no HD**: gravada no disco rígido do netbook via [`scripts/install-on-disk.sh`](../scripts/install-on-disk.sh), com backup automático da tabela GPT e ESP anterior.

---

## 2. Pré-requisitos no Host de Build

### 2.1 Hardware e Sistema Operacional
- Arquitetura: `x86_64` (amd64).
- Sistema Operacional: Debian 12/13, Ubuntu 22.04/24.04, Linux Mint 21/22 ou compatível.
- Espaço em disco livre: mínimo de **10 GB** livres na partição de trabalho.
- Conexão com a internet para download dos pacotes Debian via APT e binários oficiais.
- Acesso como `root` (via `sudo`).

### 2.2 Pacotes Necessários no Host
Instale as ferramentas necessárias executando no host:

```bash
sudo apt update
sudo apt install -y \
    debootstrap \
    parted \
    grub-efi-amd64 \
    dosfstools \
    e2fsprogs \
    util-linux \
    wget \
    ca-certificates \
    rsync
```

---

## 3. Passo a Passo para Gerar a Imagem (`rios.img`)

### 3.1 Clonar o Repositório e Navegar até a Raiz
Certifique-se de estar na raiz do projeto:

```bash
cd /caminho/para/dex-station
```

### 3.2 Verificar Versões Fixadas
O arquivo [`build/VERSIONS.lock`](../build/VERSIONS.lock) contém as versões de kernel, adb e scrcpy:

```bash
cat build/VERSIONS.lock
```

Se desejar atualizar ou fixar o SHA-256 do scrcpy oficial, edite a variável `SCRCPY_SHA256` no arquivo.

### 3.3 Executar o Script de Build
Execute o script principal com privilégios de superusuário:

```bash
sudo ./build/build-rios.sh
```

#### O que o script realiza automaticamente:
1. **Verificação de ambiente**: valida ferramentas (`debootstrap`, `parted`, `losetup`, `mkfs.fat`, etc.) e arquitetura x86_64.
2. **Criação da imagem esparsa**: aloca `rios.img` com 3072 MiB (~3 GB).
3. **Mapeamento em loop device**: cria `/dev/loopX` com suporte a partições (`-P`).
4. **Particionamento GPT**:
   - Partição 1: `ESP` (512 MiB, FAT32, flags `boot, esp`).
   - Partição 2: `root` (restante do espaço, ext4).
5. **Debootstrap**: baixa e descompacta a base Debian `trixie` (repositórios `main`, `contrib`, `non-free-firmware`).
6. **Configuração via chroot**: executa [`build/post-install.sh`](../build/post-install.sh):
   - Instala kernel `linux-image-amd64`, LXQt, SDDM com autologin para `dex`.
   - Baixa e instala o `scrcpy` e o Android Debug Bridge (`adb`).
   - Habilita `systemd-zram-generator` (1 GB de swap comprimido em RAM).
   - Desativa serviços dispensáveis (`cups`, `avahi-daemon`, `modemmanager`, etc.).
   - Aplica os arquivos do diretório [`build/overlay/`](../build/overlay/).
7. **Bootloader GRUB UEFI**:
   - Instalação via `grub-install --target=x86_64-efi --removable --no-nvram --bootloader-id=rios`.
   - Gera `grub.cfg` com detecção do kernel instalado.
8. **Finalização**: desmonta todos os sistemas de arquivos, fecha o dispositivo loop e gera o hash no arquivo `SHA256SUMS`.

---

## 4. Como Verificar o SHA-256

Após o término do build, o checksum SHA-256 é registrado em `SHA256SUMS`. Para validar a integridade da imagem:

```bash
sha256sum -c SHA256SUMS
```

Saída esperada:
```text
rios.img: SUCESSO
```

Caso queira calcular manualmente:
```bash
sha256sum rios.img
cat SHA256SUMS
```

---

## 5. Como Gravar o Live USB

O Live USB permite inicializar o netbook pelo pendrive mantendo o disco rígido interno totalmente intocado (critério de aceite T8).

### 5.1 Identificar o Pendrive
Conecte um pendrive de no mínimo 4 GB (recomendado 8 GB+) e identifique o dispositivo:

```bash
lsblk -o NAME,SIZE,TYPE,MODEL,TRAN
```
*Exemplo: `/dev/sdb`*. **Certifique-se de selecionar o pendrive e não seu disco de trabalho!**

### 5.2 Gravar com `make-live-usb.sh`
Execute:

```bash
sudo ./scripts/make-live-usb.sh /dev/sdX rios.img
```
*(Substitua `/dev/sdX` pelo dispositivo correto, por exemplo `/dev/sdb`)*.

O script:
- Recusa se houver partições montadas no dispositivo;
- Exibe o resumo do alvo e exige confirmação digitando `SIM`;
- Grava via `dd bs=4M conv=fsync status=progress`;
- Executa `sync` e lê os dados gravados para comparar o SHA-256 com a imagem original.

---

## 6. Como Instalar no HD Interno do Netbook

Para transformar o Eee PC 1015BX em uma estação riOS dedicada e permanente:

```bash
sudo ./scripts/install-on-disk.sh /dev/sda rios.img
```

### Mecanismos de Proteção e Etapas:
1. **Verificação de disco inteiro**: rejeita se for passada uma partição (ex: `/dev/sda1`).
2. **Confirmação dupla**: exige digitação de `APAGAR` em duas etapas consecutivas.
3. **Backup preventivo**:
   - Salva a tabela GPT atual com `sgdisk` e `sfdisk`;
   - Salva os primeiros 2 MiB do disco físico (`dd`);
   - Compacta o conteúdo da partição ESP atual (`/boot/efi`);
   - Compacta `/etc` e `/home` atuais para salvaguarda em `backups/backup-pre-install-<timestamp>/`.
4. **Particionamento e Cópia**:
   - Recria tabela GPT com ESP de 512 MiB e root ext4;
   - Transfere o rootfs da imagem via `rsync -aHAX`;
   - Atualiza `/etc/fstab` com os novos UUIDs do disco;
   - Instala o GRUB UEFI com `bootloader-id=rios` e `--removable`.

---

## 7. Como Reproduzir o Build em Outro Host

Para compilar a imagem em qualquer outra máquina Linux x86_64:

1. Instale o Git e clone este repositório:
   ```bash
   git clone <URL_DO_REPOSITORIO> rios
   cd rios
   ```
2. Instale as dependências:
   ```bash
   sudo apt update && sudo apt install -y debootstrap parted grub-efi-amd64 dosfstools e2fsprogs util-linux wget ca-certificates rsync
   ```
3. Inicie o processo:
   ```bash
   sudo ./build/build-rios.sh
   ```

O processo é automatizado e gera exatamente a mesma estrutura de particionamento e configuração da estação riOS.
