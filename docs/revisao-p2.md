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

Ambiente usado: Linux x86_64, Bash 5, sem celular, sem root, sem `adb`/`scrcpy`
reais. Todos os testes usam os mocks em `tests/mock/`.

```sh
tests/run-tests.sh
```

Resultado da revisão:

| Arquivo de teste | Casos | Resultado |
|---|---:|---|
| `test-config.sh` | 45 | ✅ |
| `test-state-machine.sh` | 20 | ✅ |
| `test-fallback.sh` | 29 | ✅ |
| `test-device-states.sh` | 25 | ✅ |
| `test-cli.sh` | 22 | ✅ |
| **Total** | **141** | **✅ 0 falhas** |

Além da suíte, foram feitas execuções repetidas do teste de máquina de estados
(10×) para verificar se havia corrida entre log e status.

---

## 3. Achados e correções

Legenda de severidade: **A** = impedia o uso; **M** = podia causar falha
intermitente ou diagnóstico errado; **B** = robustez/polimento.

| # | Sev. | Achado | Correção |
|---|---|---|---|
| 1 | **A** | Todos os scripts, mocks e testes estavam versionados como `100644`. Qualquer execução direta falhava com `Permissão negada` (código 126) | `chmod +x` em runtime, mocks, testes, build e scripts; modo `100755` versionado |
| 2 | **A** | `--once`/`--max-cycles` travavam para sempre quando não havia aparelho ou o `prepare` falhava: o contador só subia após uma sessão bem-sucedida | Flag `ONCE` explícita; `wait_for_device` encerra após uma detecção; o ciclo é contado mesmo sem sessão |
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

### Achados que ficaram como limitação (não são bugs de código)

| # | Limitação | Por que ficou | Próximo passo |
|---|---|---|---|
| L1 | O watchdog detecta **processo vivo**, não **imagem preta** | Detectar pixels exigiria inspecionar a janela/X11 ou o fluxo do scrcpy; o comportamento varia com o driver | Medir na bancada (T4/T7) e, se necessário, usar `xdotool`/captura de janela na v2 |
| L2 | A detecção de bloqueio é heurística (`dumpsys window`) | O texto do keyguard muda entre One UI/Android | Validar no Galaxy (T3) e ajustar o padrão se necessário |
| L3 | `--max-cycles N` conta sessões, não tentativas de detecção | Semântica documentada; `--once` cobre o uso de diagnóstico | Reavaliar se a bancada precisar de “N polls” |
| L4 | A limpeza do `overlay_display_devices` não consegue falar com o celular depois do unplug físico | O adb não tem mais transporte; o próximo ciclo sobrescreve/apaga | Documentado em `TROUBLESHOOTING.md` §6 |
| L5 | Sem validação no aparelho real | Depende da Larissa e do Galaxy | Sessão de bancada com o roteiro da seção 5 |

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
- o encerramento determinístico de `--once`, inclusive sem aparelho.

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
- [x] `rios-session --check-config` aceita o template `etc/rios/config`.
- [x] `--once` encerra em todos os estados (inclusive sem aparelho).
- [x] Fallbacks A, B e C são exercitados com sucesso e com falha.
- [x] CLI cobre start/status/logs/restart/stop/shell.
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

# CLI em modo direto (sem systemd/runit)
RIOS_INIT=direct runtime/rios-launch start
RIOS_INIT=direct runtime/rios-launch status
RIOS_INIT=direct runtime/rios-launch stop
```
