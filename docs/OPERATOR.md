# riOS — Manual do Operador

Este é o guia de quem usa a estação no dia a dia: o que fazer antes de conectar
o celular, o que cada mensagem da tela de espera significa, como sair do kiosk
quando algo dá errado e como diagnosticar sem depender de um técnico.

Para a visão de arquitetura e o plano completo, veja [`PLAN.md`](../PLAN.md).
Para sintoma → causa → solução, veja [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

---

## 1. O que a estação faz

O netbook **não roda os aplicativos**. Ele é um terminal do celular:

```
Samsung Galaxy (DeX) ──cabo USB──► Eee PC 1015BX
   processa e renderiza              exibe a imagem, envia teclado e trackpad
```

O daemon `rios-session` fica em segundo plano consultando o USB a cada 2 s.
Quando encontra um celular autorizado e desbloqueado, ele abre o DeX em tela
cheia. Ao desconectar o cabo, encerra a sessão e volta para a tela de espera.

---

## 2. Antes de conectar o celular (uma vez só)

No Samsung:

1. **Ajustes → Sobre o telefone → Número da build** (7 toques) para liberar as
   opções de desenvolvedor.
2. **Ajustes → Opções do desenvolvedor → Depuração USB** = ligada.
3. Conecte o cabo e aceite o aviso **“Permitir depuração USB?”**, marcando
   *Sempre permitir para este computador*.
4. Se for usar `KEYBOARD=uhid`, configure o teclado físico como **Português
   (Brasil)** em *Ajustes → Sistema → Idiomas e entrada → Teclado físico*.
5. Mantenha o celular **desbloqueado** durante o uso. Com a tela bloqueada, o
   DeX não sobe.

> A autorização da chave RSA é por máquina. Se o netbook for reinstalado, o
> aviso aparece de novo.

---

## 3. Uso diário

1. Ligue o netbook e espere a tela de espera.
2. Conecte o cabo USB entre o celular e o netbook.
3. Desbloqueie o celular.
4. Autorize a depuração, se o aviso aparecer.
5. Aguarde alguns segundos: o DeX abre em tela cheia.
6. Para terminar, desconecte o cabo (ou use `rios-launch stop`). O netbook volta
   sozinho para a tela de espera.

O celular pode ficar com a tela apagada: o daemon usa `--turn-screen-off` para
economizar bateria. O DeX continua rodando.

---

## 4. Mensagens da tela de espera

| Mensagem | Significado | O que fazer |
|---|---|---|
| **Conecte o celular Samsung por USB** | Nenhum aparelho autorizado foi encontrado | Conecte o cabo; verifique se ele é de dados |
| **Autorize a depuração USB no celular** | O celular apareceu, mas a chave RSA não foi aceita | Desbloqueie e aceite o aviso no celular |
| **Celular offline — reconecte o cabo USB** | O adb vê o aparelho, mas não consegue falar com ele | Troque o cabo/porta e reconecte |
| **Desbloqueie o celular** | Aparelho autorizado, tela bloqueada | Desbloqueie o celular |
| **Atualize o Android para a versão 15 ou superior** | O DeX em display virtual exige Android 15+ | Atualize o celular ou use outro aparelho |
| **adb não encontrado — instale o pacote android-tools/adb** | O daemon não achou o `adb` no `PATH` | Instale o pacote (`xbps-install -S android-tools` no Void; `apt install adb` no Debian) |
| **scrcpy não encontrado — instale o pacote scrcpy** | O daemon não achou o `scrcpy` no `PATH` | Instale o scrcpy 3.0 ou superior |

---

## 5. Atalhos e comandos

### Na sessão gráfica

| Atalho | Ação |
|---|---|
| **Alt+T** | Abre o terminal de manutenção (LXQt Global Shortcuts ou `xbindkeys`) |
| **Ctrl+Alt+F2** | Troca para um TTY de texto, mesmo com a interface travada |
| **Ctrl+Alt+F7** (ou F1) | Volta para a sessão gráfica |

### CLI `rios-launch`

```sh
rios-launch status          # aparelho, resolução, método, PID do scrcpy, CPU e RAM
rios-launch logs            # últimas 100 linhas do log
rios-launch logs -f         # acompanha em tempo real
rios-launch start           # inicia o daemon (systemd, runit ou modo direto)
rios-launch stop            # encerra o daemon e limpa a sessão
rios-launch restart         # stop + start
rios-launch shell           # shell adb no celular conectado
rios-launch shell getprop ro.build.version.release   # comando único
```

O `status` mostra o **método em uso**:

| Método | O que é |
|---|---|
| **A — display virtual** | `scrcpy --new-display=1024x600/160`. É o DeX completo, com barra de tarefas e janelas. Preferido. |
| **B — overlay + espelho** | `settings put global overlay_display_devices` seguido de espelho. Plano B quando o A não produz imagem. |
| **C — espelho simples** | Espelha a tela do celular sem display virtual. Último recurso; não é o DeX completo. |

A cadeia `A → B → C` é automática quando `METHOD=auto` (padrão).

---

## 6. Configuração

Arquivo: **`/etc/rios/config`** (formato `KEY=VALUE`). O template do repositório
está em [`etc/rios/config`](../etc/rios/config).

| Chave | Padrão | Para que serve |
|---|---|---|
| `METHOD` | `auto` | `auto`, `new-display` (só A), `overlay` (só B) ou `mirror` (só C) |
| `RESOLUTION` | `auto` | `auto` lê a tela com `xrandr`; ou force `1024x600` |
| `DPI` | `160` | Densidade lógica; 160 casa 1:1 com o painel |
| `FPS` | `15` | Teto de quadros por segundo |
| `BITRATE` | `4M` | Bitrate do vídeo |
| `VIDEO_CODEC` | `h264` | `h264`, `h265` ou `av1` |
| `AUDIO` | `off` | `on` liga o áudio (mais RAM e CPU) |
| `RENDER_DRIVER` | `software` | `software` ou `opengl` |
| `KEYBOARD` / `MOUSE` | `sdk` | `sdk` ou `uhid` |
| `WINDOW_MODE` | `fullscreen` | `fullscreen` ou `window` |
| `BLACKOUT_TIMEOUT` | `15` | Segundos sem imagem até considerar o método falho |
| `ADB_TIMEOUT` | `4` | Timeout de cada chamada ao adb |
| `POLL_INTERVAL` | `2` | Intervalo entre consultas ao adb |
| `SERIAL` | vazio | Serial fixo quando há mais de um celular |
| `LOG_MAX_BYTES` | `1048576` | Tamanho do log antes da rotação |
| `LOG_KEEP` | `5` | Quantas cópias rotacionadas manter |

Depois de editar:

```sh
rios-session --check-config          # valida sem iniciar
rios-launch restart                  # aplica
```

Valores inválidos **não derrubam** o daemon: geram aviso no log e o padrão é
mantido.

---

## 7. Instalação na bancada (M1 — Void Linux + runit)

A fase M1 roda na instalação que já existe no netbook, sem trocar o sistema.
A imagem final (Debian + systemd) é assunto do [`BUILD.md`](BUILD.md).

### 7.1 Dependências

```sh
sudo xbps-install -S android-tools scrcpy
```

Confira as versões:

```sh
adb version
scrcpy --version      # precisa ser 3.0 ou superior para --new-display
```

### 7.2 Arquivos

```sh
sudo install -m 0755 runtime/rios-session /usr/local/bin/rios-session
sudo install -m 0755 runtime/rios-launch  /usr/local/bin/rios-launch
sudo install -d /etc/rios /var/log/rios
sudo install -m 0644 etc/rios/config /etc/rios/config
```

A tela de espera (`runtime/rios-wait-screen/`) é procurada ao lado do executável
(`/usr/local/bin/rios-wait-screen/`). Se você a mantiver em outro lugar, defina
`RIOS_WAIT_SCREEN_DIR=/caminho/para/rios-wait-screen` no serviço/autostart. Se o
`setup.sh` não for encontrado, o daemon continua funcionando e apenas não troca
o papel de parede.

### 7.3 Primeiro teste, sem serviço

```sh
rios-session --check-config
RIOS_INIT=direct rios-launch start
rios-launch status
rios-launch logs -f
```

Para parar: `RIOS_INIT=direct rios-launch stop`.

### 7.4 Autostart na sessão gráfica (recomendado no M1)

Crie `~/.config/autostart/rios.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=riOS
Comment=Sessão DeX automática
Exec=rios-session
X-GNOME-Autostart-enabled=true
```

Isso inicia o daemon junto com o LXQt, com o `DISPLAY` e o `XAUTHORITY` da
sessão já corretos — que é o que o `scrcpy` precisa.

### 7.5 Serviço runit (alternativa)

O serviço de runit roda como `root`; por isso ele precisa apontar para o
usuário e o display da sessão gráfica:

```sh
sudo mkdir -p /etc/sv/rios-session
sudo tee /etc/sv/rios-session/run >/dev/null <<'EOF'
#!/bin/sh
exec 2>&1
export DISPLAY=:0
export XAUTHORITY=/home/SEU_USUARIO/.Xauthority
exec chpst -u SEU_USUARIO /usr/local/bin/rios-session
EOF
sudo chmod +x /etc/sv/rios-session/run
sudo ln -s /etc/sv/rios-session /var/service/
```

Troque `SEU_USUARIO` pelo usuário da sessão. **Não** use autostart e serviço
runit ao mesmo tempo: seriam dois daemons disputando o mesmo celular.

### 7.6 Testes automatizados (sem celular)

```sh
tests/run-tests.sh
```

Os testes usam `adb` e `scrcpy` simulados em [`tests/mock/`](../tests/mock/) e
não precisam de root, celular ou netbook.

---

## 8. Diagnóstico rápido

```sh
rios-launch status
rios-launch logs
adb devices
adb shell getprop ro.build.version.release
adb shell settings get global overlay_display_devices
```

O log fica em `/var/log/rios/rios-session.log` e o log do scrcpy em
`/var/log/rios/scrcpy.log`. O status corrente fica em `/run/rios/status`.

Se `rios-launch status` disser **parado** mas o processo existir, o arquivo de
PID pode estar velho; `rios-launch restart` resolve. Se o problema persistir,
veja [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

---

## 9. Energia

A porta USB 2.0 do 1015BX entrega **~500 mA**, menos do que um Galaxy em uso com
DeX consome. A bateria do netbook também está degradada (~86% da capacidade).

Ordem de preferência:

1. **Hub USB alimentado** com fonte própria.
2. Carregador ligado direto no celular + cabo de dados para o netbook.
3. Uso curto, com o netbook na tomada, aceitando a descarga.

O daemon já apaga a tela do celular (`--turn-screen-off`) e impede que ele durma
(`--keep-active`), mas isso não resolve a limitação elétrica da porta.

---

## 10. Limitações conhecidas

- **A detecção de “sem imagem” é por processo vivo, não por pixels.** Se o
  scrcpy continuar rodando com a janela preta, o daemon não cai sozinho para o
  fallback. Use `rios-launch restart` ou ajuste o método no config.
- **A detecção de tela bloqueada é heurística** (`dumpsys window`). Em algumas
  versões do One UI a mensagem pode demorar ou não aparecer; o sintoma real é o
  DeX não abrir.
- **Sem validação no aparelho real ainda.** Os testes atuais cobrem o daemon, a
  CLI, os fallbacks e os estados com adb simulado. T3–T7, T11, T12 e T14 da
  matriz do `PLAN.md` dependem da bancada com o Galaxy.
- **Sem persistência no Live USB.** Cada boot começa do zero.
- **Sem áudio por padrão**, para preservar os 1,5 GiB de RAM útil.
