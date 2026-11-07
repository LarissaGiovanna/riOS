# riOS

Transforma um netbook antigo — o **Asus Eee PC 1015BX** — numa **estação DeX dedicada**.
O celular Samsung faz todo o processamento; o netbook serve apenas como **tela, teclado e
trackpad**, ligados por um único cabo USB.

Em outras palavras: o netbook **não vira um PC**. Ele vira um **terminal** do celular.

```
Samsung Galaxy (One UI 8 / Android 16)  ──cabo USB──►  Eee PC 1015BX
   (processa, roda o DeX de verdade)                   (só exibe imagem e envia teclado/mouse)
```

## Hardware alvo

| Item | Especificação |
|---|---|
| Modelo | Asus Eee PC 1015BX |
| Processador | AMD C-60 — 2 núcleos, 1,0 GHz (turbo até 1,33 GHz), x86-64 (64 bits) |
| Vídeo | APU AMD Radeon HD 6290 (Wrestler, driver `radeon`, sem memória dedicada) |
| Memória RAM | 2 GB DDR3 — **1,5 GiB visíveis**, o resto é reserva de vídeo da APU |
| Tela | 10,1", 1024×600 (proporção 5:3), painel fosco |
| Disco | Seagate ST9320325AS, 320 GB, 5400 rpm |
| Portas | 3× USB 2.0, **HDMI** e **VGA** (ambas somente saída), Ethernet 10/100, leitor de cartão SD, P2 de áudio (fone/microfone) |
| Rede | Ethernet + Wi-Fi Atheros AR9285 (`ath9k`, **sem firmware proprietário**) |
| Firmware | **UEFI** (GPT + ESP), com CSM legado disponível — boot por USB com **Esc**, setup com **F2** |
| Bateria | 6 células, ~86% da capacidade (3.766 de 4.400 mAh) |
| Teclado | ABNT2 nos modelos vendidos no Brasil |

Consequências práticas desse hardware:

- **1,5 GiB é o piso, não a folga.** O sistema é montado para caber num orçamento de
  ~450–500 MB em repouso.
- **Não existe entrada de vídeo.** O 1015BX tem HDMI e VGA, mas as duas são **saídas**:
  servem para mandar a imagem do netbook para um monitor/TV, não para receber a imagem do
  celular. Por isso o caminho de vídeo é USB (veja [`PLAN.md`](PLAN.md) §3).
- **A CPU é de 2011.** O alvo é 15 fps em 1024×600, com decodificação por software.
- **A porta USB 2.0 entrega ~500 mA**, menos do que um Galaxy moderno consome em uso.
- **As saídas HDMI e VGA são um bônus:** o netbook pode espelhar ou estender a sessão para
  uma TV/monitor maior. A resolução do DeX continua 1024×600 — a imagem é ampliada, não
  ganha detalhe.
- **O P2 de áudio é a saída natural para som**, caso o áudio seja ligado (padrão é desligado).
- **Bateria degradada (~86%) e já vista com pouca carga**, o hub alimentado deixa de ser
  opcional.

## Estado atual da máquina (medido em 21/10/2026)

| Item | Valor |
|---|---|
| Distribuição | **Void Linux**, kernel 6.18.56_1, x86_64 |
| Init | **runit** (não é systemd) |
| Pacotes | `xbps`; `adb` 36.0.1 e `scrcpy` 5.0 instalados; `ffmpeg` e Python 3.14 presentes |
| Memória | 1,5 GiB total, ~1,1 GiB disponível, 470 MiB em uso |
| Swap | 7,8 GB em partição do HDD, **sem zram** |
| Sessão gráfica | `lightdm` (não SDDM), painel `LVDS` em 1024×600 |
| Relógio | **sem NTP; atrasado 6 dias** — corrigir antes de qualquer medição datada |
| Boot | UEFI com ESP de 256 MB em `/boot/efi` |

O inventário completo (com as saídas de `lscpu`, `free`, `lsusb`, `lsblk`, `lspci`…) está em
[`docs/ambiente-de-testes.md`](docs/ambiente-de-testes.md). Ele é gerado por
`scripts/coleta-ambiente.sh` — use `--mascarar` antes de publicar.

Consequência direta: o **M1 roda em Void/runit**, então os comandos da fase de bancada são
`xbps-install` + `sv`, enquanto a imagem final (M3 em diante) usa Debian/systemd. O plano
mantém os dois caminhos separados (ver [`PLAN.md`](PLAN.md) §9.1.1).

## Status

| Fase | Conteúdo | Estado |
|---|---|---|
| M0 | Plano de desenvolvimento | ✅ [`PLAN.md`](PLAN.md) |
| M1 | Daemon do kiosk rodando no Void/runit atual do netbook | 🔄 Em andamento — daemon/CLI validados com adb simulado; falta a bancada |
| M2 | Validação no aparelho real (DeX + teclado/trackpad) | ⬜ |
| M3 | Build da imagem (`rios.img`) | ⬜ |
| M4 | Live USB | ⬜ |
| M5 | Instalação no HD | ⬜ |
| M6 | Calibração de performance + documentação | ⬜ |
| M7 | Estabilização e release v1.0 | ⬜ |

## Por onde começar

1. Ler [`PLAN.md`](PLAN.md) — arquitetura, riscos, matriz de testes e roadmap.
2. **M1**: implementar `runtime/rios-session` e rodar **no Void Linux que já está
   instalado no netbook** (`xbps-install -S android-tools scrcpy`, serviço em `/etc/sv`).
   O ciclo de teste cai de horas (build de imagem) para minutos.
3. **M2**: repetir com o celular conectado de verdade.

## Documentação de operação

- [`docs/OPERATOR.md`](docs/OPERATOR.md) — uso diário, atalhos, configuração e
  instalação na bancada (Void/runit).
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — sintoma → causa → solução.
- [`docs/revisao-p2.md`](docs/revisao-p2.md) — revisão do daemon/CLI, achados,
  correções e roteiro de validação no aparelho real.
- [`docs/pendencias-p2.md`](docs/pendencias-p2.md) — resumo do que ainda falta na
  frente P2 (validação, empacotamento e artigo).
- [`docs/BUILD.md`](docs/BUILD.md) — construção da imagem e gravação.

## Testes sem celular

A suíte usa `adb` e `scrcpy` simulados e roda em qualquer Linux com Bash:

```sh
tests/run-tests.sh
```

Cobre config, máquina de estados, fallbacks A/B/C, estados de conexão e a CLI.
Os testes que dependem do Galaxy real estão em
[`tests/PENDING-HARDWARE.md`](tests/PENDING-HARDWARE.md).

## Variantes de entrega

As duas variantes usam **a mesma** `rios.img`. Muda só o destino da gravação:

- **Live USB** — `scripts/make-live-usb.sh`: grava a imagem num pendrive. O HD do netbook
  não é tocado, nada é instalado. É o modo recomendado para testar.
- **Instalação no HD** — `scripts/install-on-disk.sh`: faz backup (incluindo a ESP atual),
  grava a imagem em **GPT com ESP** e instala o GRUB UEFI (`--removable`). Sistema dedicado
  e permanente.

Detalhes de cada procedimento em [`PLAN.md`](PLAN.md) §7 e §8.

## Requisitos do celular

1. One UI 8 / Android 16 (é a versão em que o DeX passou a rodar em *display virtual*).
2. **Depuração USB** habilitada e a chave RSA deste netbook autorizada.
3. Celular **desbloqueado** durante o uso — com a tela bloqueada, o DeX não inicia.
4. Celular com bateria suficiente ou ligado a um carregador (veja o aviso abaixo).
5. Se usar `--keyboard=uhid`: Ajustes → Sistema → Idiomas e entrada → Teclado físico →
   **Português (Brasil)**.

## Aviso importante sobre energia

A porta USB 2.0 do 1015BX oferece **~500 mA**. Um Galaxy em uso com DeX consome mais do que
isso, então **a bateria do netbook vai ser drenada** e o celular pode até descarregar
devagar. A bateria deste netbook já está com **55% da capacidade original**, o que encurta
ainda mais a autonomia. Soluções, em ordem de preferência:

1. **Hub USB alimentado** (com fonte própria) — o netbook só transporta dados.
2. Carregador ligado direto no celular + cabo de dados para o netbook.
3. Uso curto, com o netbook na tomada, aceitando a descarga.

## Limitações conhecidas

- Sem aceleração de vídeo no scrcpy: a decodificação é feita pela CPU (a APU tem decoder
  UVD3, mas o scrcpy não o utiliza). Por isso o teto de 15 fps.
- Sem áudio por padrão é a escolha mais segura para 1,5 GiB de RAM (decisão em aberto no plano).
- O pendrive do modo Live **não guarda nada** entre boots — é descartável por projeto.
- O estado atual usa **swap em disco e nenhum zram**, o oposto do que a imagem vai entregar:
  comparações de desempenho entre bancada e imagem precisam registrar essa diferença.
