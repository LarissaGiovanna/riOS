# riOS — Solução de Problemas

Guia de **sintoma → causa provável → solução** para a estação DeX. Comece
sempre pela coleta de evidências da seção 1; ela evita trocar cabo, serviço e
configuração ao mesmo tempo.

Para o uso normal, veja [`OPERATOR.md`](OPERATOR.md). Para a arquitetura e os
testes de hardware, veja [`PLAN.md`](../PLAN.md) §11.

---

## 1. Coleta de evidências (30 segundos)

Rode na ordem e guarde a saída:

```sh
rios-launch status
rios-launch logs
adb version
scrcpy --version
adb devices -l
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk
adb shell dumpsys window | grep -E 'mDreamingLockscreen|mShowingLockscreen|mKeyguardShowing'
adb shell settings get global overlay_display_devices
```

No netbook, também ajudam:

```sh
uname -a
xrandr --current
free -m
ps -o pid,pcpu,pmem,cmd -C scrcpy
tail -n 100 /var/log/rios/scrcpy.log
dmesg | tail -n 30
lsusb
```

> **Privacidade:** `adb shell` pode expor dados do celular. Antes de publicar
> logs ou capturas, remova serial, IP, nome do aparelho e conteúdo de tela.

> **Caminhos de log:** as linhas acima usam `/var/log/rios` (daemon como root ou
> serviço). Rodando como usuário comum, o padrão é
> `~/.local/state/rios/log`; o status fica em `$XDG_RUNTIME_DIR/rios` (ou
> `/tmp/rios-$UID`). Veja `OPERATOR.md` §7.2.

---

## 2. O daemon não inicia

| Sintoma | Causa provável | Solução |
|---|---|---|
| `rios-launch start` → “daemon não encontrado ou sem permissão” | Arquivo sem bit de execução ou fora do `PATH` | `chmod +x runtime/rios-session`; instale em `/usr/local/bin` (seção 7 do `OPERATOR.md`) |
| `Permissão negada` ao rodar testes ou o daemon | O repositório foi clonado sem os bits de execução | `chmod +x runtime/rios-session runtime/rios-launch tests/mock/* tests/test-*.sh tests/run-tests.sh` |
| Daemon encerra logo após iniciar | Configuração inválida ou dependência ausente | `rios-session --check-config`; `rios-launch logs` |
| `systemctl`/`sv` diz que o serviço não existe | Serviço não instalado | Use o autostart do `OPERATOR.md` §7.4 ou crie o serviço runit do §7.5 |
| Dois daemons brigando pelo mesmo celular | Autostart **e** serviço de init ativos | Escolha um dos dois e desligue o outro |

Verificação direta, sem gerenciador de serviços:

```sh
RIOS_INIT=direct rios-launch start
rios-launch status
RIOS_INIT=direct rios-launch stop
```

---

## 3. Problemas de conexão USB / adb

| Sintoma na tela | Causa provável | Solução |
|---|---|---|
| **Conecte o celular Samsung por USB** | Cabo só de carga, porta ruim ou aparelho não autorizado | Troque o cabo por um de **dados**; teste outra porta; rode `adb devices` |
| **Autorize a depuração USB no celular** | Chave RSA não aceita | Desbloqueie o celular e aceite o aviso; se não aparecer, revogue as autorizações em *Opções do desenvolvedor → Revogar autorizações de depuração USB* |
| **Celular offline** | adb travado, cabo ruim ou tela de bloqueio | `adb kill-server && adb start-server`; reconecte; troque o cabo |
| **adb não encontrado** | Pacote não instalado ou fora do `PATH` | Void: `sudo xbps-install -S android-tools`; Debian: `sudo apt install adb` |
| Aparelho aparece como `no permissions` | Regras udev ausentes (comum fora do Debian) | Instale as regras do pacote `android-tools`/`adb` ou copie `51-android.rules`; confira `lsusb` |
| `adb devices` mostra o aparelho, mas `adb shell` falha | Autorização revogada ou aparelho bloqueado | Desbloqueie e reautorize |

Teste rápido sem o daemon:

```sh
adb devices
adb shell echo ok
```

Se `adb shell echo ok` não imprimir `ok`, o problema é **antes** do riOS.

---

## 4. O DeX não abre

| Sintoma | Causa provável | Solução |
|---|---|---|
| Tela de espera some, mas nada aparece | Método A falhou e o B/C ainda está tentando | Espere `BLACKOUT_TIMEOUT`; veja `rios-launch logs` |
| **Desbloqueie o celular** | Tela bloqueada | Desbloqueie; o DeX não sobe com o keyguard ativo |
| **Atualize o Android para 15+** | Versão antiga | O display virtual do One UI 8 exige Android 15+ |
| `scrcpy: unrecognized option '--new-display'` | scrcpy < 3.0 | Atualize para scrcpy 3.x |
| `scrcpy não encontrado` | Pacote ausente | Instale o scrcpy |
| Só o método C funciona (espelho) | O celular não aceita display virtual | Normal em alguns builds; o espelho é o plano C. Registre a versão do One UI |
| Nenhum método funciona | Veja `scrcpy.log` | As causas mais comuns estão na seção 5 |

Forçar um método para isolar o problema:

```ini
# /etc/rios/config
METHOD=mirror
```

Depois: `rios-launch restart`.

---

## 5. scrcpy falha ou fecha

```sh
tail -n 100 /var/log/rios/scrcpy.log
```

| Mensagem no `scrcpy.log` | Causa provável | Solução |
|---|---|---|
| `Could not find any ADB device` | Aparelho desconectado ou não autorizado | Seção 3 |
| `ERROR: Could not open video stream` | Codec/bitrate incompatível | Teste `VIDEO_CODEC=h264` e `BITRATE=2M` |
| `ERROR: Demuxer error` | Fluxo de vídeo interrompido | Reconecte; teste outro cabo/porta |
| `SDL_Init` / `Could not initialize SDL` | `DISPLAY`/`XAUTHORITY` errados no serviço | Use autostart na sessão gráfica ou ajuste o serviço (seção 7.5 do `OPERATOR.md`) |
| `Failed to create renderer` | Driver OpenGL instável no Radeon HD 6290 | Use `RENDER_DRIVER=software` |
| `Audio capture` / `Could not start audio` | Áudio ligado sem suporte | Use `AUDIO=off` |
| Processo morre sem mensagem | Memória ou CPU esgotadas | Veja seção 8; reduza `FPS`/`BITRATE`; desligue áudio |

---

## 6. Display virtual órfão / tela duplicada no celular

Sintoma: o celular continua com um display extra ou uma tela preta depois de
desconectar.

Causa: o `overlay_display_devices` ficou aplicado (método B interrompido).

```sh
adb shell settings delete global overlay_display_devices
adb shell settings get global overlay_display_devices   # deve responder null
```

O daemon já faz essa limpeza no caminho normal; se o cabo foi arrancado no meio
da sessão, o celular pode ficar com o overlay até a próxima conexão. O próximo
ciclo (método B/C) sobrescreve ou apaga o valor.

Se a tela do celular ficar preta após o uso, pressione o botão de energia ou
reinicie a interface:

```sh
adb shell wm size reset
adb shell wm density reset
```

> `wm size`/`wm density` só são necessários se algum teste manual tiver mudado
> esses valores; o riOS não os altera.

---

## 7. Entrada (teclado e trackpad)

| Sintoma | Causa provável | Solução |
|---|---|---|
| Acentos e `ç` saem errados | Layout do teclado físico no celular | *Ajustes → Sistema → Idiomas e entrada → Teclado físico → Português (Brasil)*; ou use `KEYBOARD=sdk` |
| Trackpad “pula” ou vai para o canto | Modo absoluto do `sdk` | Teste `MOUSE=uhid`; compare a sensação |
| Clique/arrasto não funciona | Modo de injeção inadequado | Teste `MOUSE=sdk` (padrão) e `MOUSE=uhid` |
| Atalhos do netbook (Alt+T) não chegam ao DeX | O atalho é capturado pelo LXQt | Use o terminal no netbook para manutenção; o DeX recebe o restante |

---

## 8. Desempenho, memória e energia

| Sintoma | Causa provável | Solução |
|---|---|---|
| Interface lenta, FPS baixo | Decodificação por software no C-60 | `FPS=15`, `BITRATE=4M`, `VIDEO_CODEC=h264`, `RENDER_DRIVER=software` |
| CPU perto de 100% | Bitrate/FPS altos ou áudio ligado | Reduza `FPS` e `BITRATE`; `AUDIO=off` |
| RAM estourada / OOM | LXQt + scrcpy + áudio em 1,5 GiB | Feche abas/apps locais; `AUDIO=off`; considere zram (imagem) ou `zramen` (Void) |
| Netbook descarrega rápido | Porta USB 2.0 entrega ~500 mA | Hub alimentado; ver `OPERATOR.md` §9 |
| Celular descarrega durante o uso | Consumo do DeX maior que a carga | Carregador no celular ou hub alimentado |
| Superaquecimento / throttle | C-60 de 9 W com cooler de netbook | Limpe o cooler, não bloqueie as saídas de ar, use sessões mais curtas |
| Imagem “borrada” ou escalonada | Resolução diferente de 1024×600 | `RESOLUTION=1024x600` e confira `xrandr` |

Perfil conservador para o 1015BX:

```ini
RESOLUTION=1024x600
DPI=160
FPS=15
BITRATE=4M
VIDEO_CODEC=h264
RENDER_DRIVER=software
AUDIO=off
WINDOW_MODE=fullscreen
```

---

## 9. Logs, status e rotação

| Sintoma | Causa provável | Solução |
|---|---|---|
| `rios-launch logs` → “nenhum log encontrado” | Daemon nunca iniciou ou `RIOS_LOG_DIR` diferente | Rode `rios-launch start`; confira `/var/log/rios/` (root/serviço) ou `~/.local/state/rios/log/` (usuário) |
| Log cresce sem parar | `LOG_MAX_BYTES`/`LOG_KEEP` inadequados | Ajuste no config; a rotação é automática |
| `status` mostra “parado” com processo vivo | PID file velho ou daemon iniciado fora da CLI | `rios-launch restart`; confira `pgrep -af rios-session` |
| `status` mostra método vazio | Nenhuma sessão ativa (IDLE) | Normal na tela de espera |
| Permissão negada em `/var/log/rios` | Diretório criado por outro usuário | `sudo chown -R USUARIO /var/log/rios`, use `RIOS_LOG_DIR` ou deixe o padrão de usuário |

---

## 10. Sair do kiosk e recuperar o controle

1. **TTY de manutenção:** `Ctrl+Alt+F2`.
2. Entre com o usuário da sessão.
3. Pare o daemon:

   ```sh
   rios-launch stop
   # ou, se o serviço estiver no init:
   sudo sv stop rios-session          # runit
   sudo systemctl stop rios-session   # systemd
   ```

4. Se a interface gráfica estiver travada:

   ```sh
   pkill -f scrcpy
   rios-launch restart
   ```

5. Se nada responder, reinicie com `sudo reboot` (ou segure o botão de energia).
   O daemon limpa a sessão na saída normal; após um desligamento abrupto, rode a
   limpeza manual da seção 6.

Para **sair do kiosk de propósito** (manutenção longa), desative o autostart ou
o serviço, e não apenas mate o processo — senão ele volta no próximo login.

---

## 11. Testes e validação

Antes de culpar o hardware, rode a suíte simulada:

```sh
tests/run-tests.sh
```

Ela cobre:

| Arquivo | O que valida |
|---|---|
| `test-config.sh` | parsing, defaults, valores inválidos, zeros à esquerda |
| `test-state-machine.sh` | IDLE → PREPARING → RUNNING → cleanup → IDLE, hotplug |
| `test-fallback.sh` | A→B→C com falha total, B assumindo e C assumindo |
| `test-device-states.sh` | mensagens de sem aparelho, não autorizado, offline, bloqueado e sem adb |
| `test-cli.sh` | start/status/logs/restart/stop/shell da CLI |

Se a suíte passa mas o aparelho real falha, o problema está na combinação
celular/One UI/scrcpy — registre versões e o `scrcpy.log` para a bancada.

---

## 12. Limitações conhecidas do diagnóstico

- **Sem detecção de imagem preta:** o watchdog observa o processo do scrcpy, não
  os pixels. Uma janela preta com processo vivo não dispara fallback.
- **Detecção de bloqueio heurística:** depende do `dumpsys window` da versão do
  One UI. Pode falhar silenciosamente.
- **Sem teste no Galaxy real ainda:** T3–T7, T11, T12 e T14 do `PLAN.md` §11
  continuam pendentes de bancada.
- **`adb`/`scrcpy` mudam de comportamento entre versões.** Registre as versões
  medidas em [`build/VERSIONS.lock`](../build/VERSIONS.lock) e no diário de
  experimentos.
