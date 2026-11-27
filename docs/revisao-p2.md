# riOS — Revisão e validação do código do daemon/CLI (P2)

Registro da supervisão do código de `runtime/rios-session` e
`runtime/rios-launch` antes da validação na bancada. O objetivo é duplo:
**entender e validar** o que foi gerado (requisito do artigo) e deixar rastro
do que foi corrigido, do que foi testado e do que ainda depende do celular real.

> **Nomes:** o documento de divisão de tarefas chama o daemon de
> `dex-station-session`. O repositório já usa `rios-session`/`rios-launch` em
> `PLAN.md`, `README.md`, `build/` e `etc/`. Os nomes foram mantidos para não
> quebrar os caminhos de instalação; o papel é o mesmo.

---

## 1. Escopo revisado

| Arquivo | O que foi revisado |
|---|---|
| `runtime/rios-session` | loop de detecção, estados, parsing do config, settings do Android, resolução, scrcpy, fallbacks A/B/C, watchdog, cleanup, logs, CLI |
| `runtime/rios-launch` | detecção de init, start/stop/restart, status, logs, shell, modo direto |
| `tests/mock/adb` | fidelidade mínima do `adb devices`, `getprop`, `settings`, `dumpsys` |
| `tests/mock/scrcpy` | ciclo de vida, falha imediata e falha nas N primeiras execuções |
| `tests/test-*.sh` | cobertura de config, estados, fallbacks e CLI |
| `etc/rios/config` | coerência com os defaults do daemon |

Fora do escopo desta revisão: `build/` (P3), `scripts/` de gravação e a
validação no aparelho real (P1/Larissa).

---

## 2. Como validar

O ensaio original da revisão rodou no **host Linux Mint**, com o daemon e a
CLI executados fora do alvo. Isso não exercitava o stack da imagem
(Debian/systemd/LXQt) nem o `scrcpy` 5.0 instalado no alvo; a resolução da
sessão também podia ser confundida com a tela do host.

Esta rodada repetiu a validação **dentro da VM Debian 13**, que é o ambiente
mais próximo do 1015BX disponível sem o Galaxy. Todos os testes continuam
usando os mocks em `tests/mock/`; não há celular nem root.

| Item | Host original (Mint) | Alvo desta rodada (VM) |
|---|---|---|
| Sistema | Linux Mint, x86_64 | **Debian GNU/Linux 13.7 (trixie)**, kernel 6.12.117 |
| Init | systemd | **systemd 257** |
| Sessão gráfica | desktop normal | **LXQt 2.1 + SDDM**, X11 (`Virtual-1`) |
| Resolução | tela do host | **1280×800** na VM; config força **1024×600** |
| Bash | 5.x | **5.2.37** |
| adb | não exercitado de verdade | **34.0.5-debian**, sem aparelho |
| scrcpy | não exercitado de verdade | **5.0** em `/usr/local/bin/scrcpy` |
| Usuário | comum | **`rios` (uid 1000), sem root** |

```sh
tests/run-tests.sh
```

Resultado da repetição no Debian (a suíte original no Mint tinha **141 casos**;
os casos novos abaixo vieram das rodadas seguintes):

| Arquivo de teste | Casos | Resultado no Debian 13 |
|---|---:|---|
| `test-config.sh` | 48 | ✅ |
| `test-state-machine.sh` | 20 | ✅ |
| `test-fallback.sh` | 29 | ✅ |
| `test-device-states.sh` | 25 | ✅ |
| `test-cli.sh` | 28 | ✅ |
| `test-coleta-desempenho.sh` | 30 | ✅ |
| `test-service.sh` | 57 | ✅ |
| **Total** | **237** | **✅ 0 falhas** |

Além da suíte, foram feitas execuções repetidas do teste de máquina de estados
(10×) e três execuções completas da suíte na VM (≈17 s cada) para verificar se
havia corrida entre log e status. A validação do `scrcpy` real foi limitada ao
que não depende do Galaxy:

```sh
scrcpy --help | grep -E -- '--new-display|--max-fps|--video-bit-rate|--render-driver'
scrcpy --new-display=1024x600/160 --video-codec=h264 --video-bit-rate=4M \
       --max-fps=15 --render-driver=software --turn-screen-off --keep-active \
       --mouse=sdk --keyboard=sdk --no-audio --fullscreen
# código 1 com "Could not find any ADB device": as flags foram aceitas;
# falta apenas o aparelho para provar a imagem (T4).
```

Também foram exercitados na VM, sem serviço de init instalado (a unit é P3):
`--check-config` no template, `--once` sem aparelho, `--max-cycles` sem
aparelho e a CLI `start/status/logs/restart/stop` em modo direto.


---

## 3. Achados e correções

Legenda de severidade: **A** = impedia o uso; **M** = podia causar falha
intermitente ou diagnóstico errado; **B** = robustez/polimento.

| # | Sev. | Achado | Correção |
|---|---|---|---|
| 1 | **A** | Todos os scripts, mocks e testes estavam versionados como `100644`. Qualquer execução direta falhava com `Permissão negada` (código 126) | `chmod +x` em runtime, mocks, testes, build e scripts; modo `100755` versionado |
| 2 | **A** | `--once` travava para sempre quando não havia aparelho ou o `prepare` falhava: o contador só subia após uma sessão bem-sucedida (`--max-cycles` tinha o mesmo problema; ver achado 14) | Flag `ONCE` explícita; `wait_for_device` encerra após uma detecção |
| 3 | **M** | O log anunciava `estado=RUNNING` antes de o arquivo de status ser atualizado; a CLI podia ler o estado anterior | `status_write` passou a rodar **antes** do `log` em `set_state` |
| 4 | **M** | No modo direto da CLI, o `stderr` do daemon ia para o mesmo arquivo de log, duplicando cada linha | `nohup … >/dev/null 2>&1`; o daemon já grava no próprio log |
| 5 | **M** | Inteiros com zero à esquerda (`015`, `02`) eram aceitos e interpretados como **octal** pela aritmética do Bash | Normalização com `10#` no parsing do config e em `--max-cycles` |
| 6 | **B** | `BITRATE=0` era aceito e produziria um scrcpy inválido | Validação exige valor numérico maior que zero |
| 7 | **B** | `scrcpy` ausente só era descoberto depois de aplicar settings e tentar três métodos | Pré-checagem no `prepare_device`, com mensagem específica na tela de espera |
| 8 | **B** | Linhas de ruído do `adb` (`* daemon started`, `adb server version…`) podiam confundir o parser de `adb devices` | Parser ignora `List`, `*` e `adb` |
| 9 | **B** | `rios-launch shell` ignorava o serial do aparelho em uso | Usa `SERIAL` do arquivo de status quando presente |
| 10 | **B** | `cleanup` rodava duas vezes na saída normal (loop + trap), repetindo `settings delete` | `on_exit` só limpa se ainda houver estado/sessão pendente |
| 11 | **M** | A suíte de fallback só testava o caso “todos falham”; não provava que B ou C **assumem** a sessão | Cenários novos: só A falha → B; A e B falham → C |
| 12 | **M** | Não havia teste da CLI nem das mensagens de tela de espera | `test-cli.sh` e `test-device-states.sh` |
| 13 | **B** | Não havia um comando único para rodar a suíte | `tests/run-tests.sh` com resumo e filtro |
| 14 | **M** | O `--max-cycles` ainda travava sem aparelho: só o `--once` encerrava, porque o contador só subia depois de uma sessão | Cada espera sem aparelho também conta um ciclo; `--max-cycles N` encerra em N detecções (documentado na ajuda e coberto por teste) |
| 15 | **M** | O `rios-launch status` mostrava a resolução do **monitor do host** via `xrandr` (1920×1080 no Mint, 1280×800 na VM), não a resolução da sessão DeX (1024×600) | O status lê `RESOLUTION` do arquivo do daemon e só usa `xrandr` quando nunca houve sessão |
| 16 | **B** | O parser de `adb devices` da CLI não ignorava as linhas de ruído (`* daemon started`, `adb server version...`); o daemon já ignorava | Mesmo filtro do daemon (`List`, `*`, `adb`), com cenário de ruído no mock e na CLI |
| 17 | **B** | O status mostrava o init **detectado** pela CLI (`systemd`), mesmo quando o daemon tinha sido iniciado em modo direto | Com daemon ativo, o init vem do arquivo de status, que registra o modo real |

### Achados que ficaram como limitação (não são bugs de código)

| # | Limitação | Por que ficou | Próximo passo |
|---|---|---|---|
| L1 | O watchdog detecta **processo vivo**, não **imagem preta** | Detectar pixels exigiria inspecionar a janela/X11 ou o fluxo do scrcpy; o comportamento varia com o driver | Medir na bancada (T4/T7) e, se necessário, usar `xdotool`/captura de janela na v2 |
| L2 | A detecção de bloqueio é heurística (`dumpsys window`) | O texto do keyguard muda entre One UI/Android | Validar no Galaxy (T3) e ajustar o padrão se necessário |
| L3 | A limpeza do `overlay_display_devices` não consegue falar com o celular depois do unplug físico | O adb não tem mais transporte; o próximo ciclo sobrescreve/apaga | Documentado em `TROUBLESHOOTING.md` §6 |
| L4 | Sem validação no aparelho real | Depende da Larissa e do Galaxy | Sessão de bancada com o roteiro da seção 5 |

---

## 4. O que os testes provam (e o que não provam)

**Provam, com adb/scrcpy simulados:**

- o parsing do config, defaults, valores inválidos e normalização;
- as transições `IDLE → PREPARING → RUNNING → cleanup → IDLE`;
- o hotplug (unplug durante a sessão encerra o scrcpy e limpa o overlay);
- a cadeia `A → B → C` e a permanência em B ou C quando o método anterior falha;
- as mensagens de tela de espera para sem aparelho, não autorizado, offline,
  bloqueado e adb ausente;
- os três settings globais aplicados;
- a CLI `start/status/logs/restart/stop/shell` e o modo direto;
- o encerramento determinístico de `--once` e de `--max-cycles`, inclusive
  sem aparelho;
- que o status reporta a resolução e o init da sessão, não os do host;
- que as linhas de ruído do `adb` não viram nome de aparelho na CLI.

**Provam também, na VM Debian 13 (o alvo mais próximo):**

- que a suíte inteira e a CLI em modo direto funcionam no stack
  Debian/systemd/LXQt, com Bash 5.2 e `adb` real instalado (sem aparelho);
- que o `scrcpy` 5.0 do alvo aceita todas as flags dos métodos A/B/C; a
  execução sem Galaxy para em “Could not find any ADB device”, como esperado;
- que o status não confunde mais a tela `Virtual-1` 1280×800 da VM com a
  sessão 1024×600.

**Não provam:**

- que o One UI 8 aceita `--new-display` no Galaxy S24 (T4);
- que o DeX aparece com barra de tarefas e janelas redimensionáveis (T4);
- que teclado ABNT2 e trackpad funcionam como esperado (T5);
- o comportamento real de `dumpsys window` com a tela bloqueada (T3);
- latência, FPS, CPU, RAM e energia (T11/T12);
- a limpeza do overlay após um unplug físico (T6/T7).

Esses itens são a pauta da bancada.

---

## 5. Roteiro curto para a sessão de bancada (T3–T7)

Levar o netbook já com o daemon instalado e a suíte passando. Na sessão:

1. **T3 — detecção e autorização**
   - `adb devices` antes e depois do cabo;
   - conferir a mensagem de autorização na tela de espera;
   - aceitar a chave RSA e ver o estado mudar para `PREPARING`/`RUNNING`.
2. **T4 — DeX virtual**
   - `rios-launch status` deve mostrar `METHOD=A`;
   - confirmar barra de tarefas e janela redimensionável;
   - guardar captura de tela e versão do One UI.
3. **T5 — entrada**
   - digitar acentos e `ç`; testar clique, arrasto e rolagem;
   - se o layout falhar, repetir com `KEYBOARD=sdk` e registrar a diferença.
4. **T6 — hotplug**
   - desconectar o cabo durante a sessão;
   - conferir `rios-launch status` em `IDLE`, scrcpy encerrado e
     `overlay_display_devices` = `null`;
   - reconectar e confirmar sessão nova.
5. **T7 — fallback**
   - forçar `METHOD=new-display` e simular falha (ex.: versão de scrcpy sem a
     flag) para ver B; depois forçar B para ver C;
   - registrar qual método exibiu imagem e por quanto tempo.

Em cada passo: anotar data, versão do One UI, versão do scrcpy, método, e anexar
`/var/log/rios/rios-session.log` e `/var/log/rios/scrcpy.log`.

---

## 6. Critérios de aceite da revisão

- [x] `tests/run-tests.sh` passa inteiro sem root, celular ou rede.
- [x] A suíte e a CLI passam dentro da VM **Debian 13** (systemd/LXQt), não só
      no host Mint.
- [x] `rios-session --check-config` aceita o template `etc/rios/config`.
- [x] `--once` encerra em todos os estados (inclusive sem aparelho).
- [x] `--max-cycles N` encerra sem aparelho depois de N detecções.
- [x] Fallbacks A, B e C são exercitados com sucesso e com falha.
- [x] CLI cobre start/status/logs/restart/stop/shell e ruído do `adb`.
- [x] `status` mostra a resolução/init da sessão e o `scrcpy` 5.0 aceita as
      flags reais do alvo.
- [x] `OPERATOR.md` e `TROUBLESHOOTING.md` publicados.
- [ ] T3–T7 validados no Galaxy real (P1).
- [ ] Limitações L1/L2 reavaliadas após a bancada.

---

## 7. Comandos úteis da revisão

```sh
# suíte completa
tests/run-tests.sh

# só um arquivo
tests/run-tests.sh fallback

# daemon em modo de inspeção
runtime/rios-session --check-config
runtime/rios-session --dump-config

# um ciclo só, com diretórios temporários
RIOS_LOG_DIR=/tmp/rios-log RIOS_STATE_DIR=/tmp/rios-run \
  runtime/rios-session --once

# duas detecções e encerra, mesmo sem aparelho
RIOS_LOG_DIR=/tmp/rios-log RIOS_STATE_DIR=/tmp/rios-run \
  runtime/rios-session --max-cycles 2

# repetir a suíte no alvo Debian 13 (VM)
bash tests/run-tests.sh

# CLI em modo direto (sem systemd/runit)
RIOS_INIT=direct runtime/rios-launch start
RIOS_INIT=direct runtime/rios-launch status
RIOS_INIT=direct runtime/rios-launch stop
```
