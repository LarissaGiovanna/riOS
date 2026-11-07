# riOS — testes pendentes de hardware

Tabela de acompanhamento da matriz de testes do [`PLAN.md`](../PLAN.md) §11.
A coluna **Testável em VM?** indica se o teste pode ser executado na máquina
virtual (VirtualBox — ver [`docs/virtualbox-simulacao.md`](../docs/virtualbox-simulacao.md))
sem o Samsung e sem o Eee PC 1015BX. Os demais exigem a bancada real.

| ID | Descrição | Testável em VM? | Status |
|---|---|---|---|
| T0 | Build repetível: `sha256sum` registrado; dois builds seguidos sem erro | PODE RODAR EM VM | ⬜ Pendente (depende de `build/`) |
| T1 | Chroot coerente: nenhum serviço falhando; `systemd-analyze` sem caminho crítico | PODE RODAR EM VM | ⬜ Pendente (depende de `build/`) |
| T2 | Boot completo: autologin → LXQt → tela de espera em < 90 s | PODE RODAR EM VM | ⬜ Pendente |
| T3 | Detecção: celular plugado é detectado; mensagem de autorização aparece | SÓ HARDWARE | 🟡 Mock cobre os estados; falta o Galaxy |
| T4 | DeX virtual: barra de tarefas + janela redimensionável no display virtual | SÓ HARDWARE | ⬜ Pendente |
| T5 | Entrada: clique, arrasto, rolagem e digitação ABNT2 (acentos, ç) | SÓ HARDWARE | ⬜ Pendente |
| T6 | Hotplug: unplug → limpeza sem display órfão; replug → sessão nova | SÓ HARDWARE | 🟡 Mock cobre o ciclo; falta o Galaxy |
| T7 | Fallback: método A forçado a falhar → B → C, cada um exibindo imagem | PODE RODAR EM VM | 🟡 Automatizado em `tests/test-fallback.sh` (A→B→C, B e C assumindo) |
| T8 | Live USB: boot pelo pendrive; **HD intocado** (tabela e checksums inalterados) | PODE RODAR EM VM | ⬜ Pendente |
| T9 | Rede: dados trafegam pelo USB; internet via tethering opcional | SÓ HARDWARE | ⬜ Pendente |
| T10 | Instalação HD: backup gerado; imagem gravada; GRUB instalado; boot pelo HD | PODE RODAR EM VM | ⬜ Pendente (depende de `build/` e `scripts/`) |
| T11 | Performance: CPU < 60% e RAM < 450 MB em repouso por 30 min; sem travamento | SÓ HARDWARE | ⬜ Pendente |
| T12 | Energia: celular carregando via hub alimentado; temperatura estável | SÓ HARDWARE | ⬜ Pendente |
| T13 | Recuperação: `Ctrl+Alt+F2` → TTY; `rios-launch restart`; saída de emergência | PODE RODAR EM VM | 🟡 `test-cli.sh` cobre restart/stop; falta o TTY |
| T14 | Autonomia: sem celular, não trava, não reinicia; tela de espera persistente | SÓ HARDWARE | ⬜ Pendente |

## Testes automatizados disponíveis hoje

Os testes abaixo rodam sem celular, sem root e sem o netbook (usam os mocks em
`tests/mock/`):

```sh
tests/run-tests.sh          # roda a suíte inteira e resume os resultados
tests/test-config.sh        # parsing, defaults, valores inválidos, zeros à esquerda
tests/test-state-machine.sh # IDLE → PREPARING → RUNNING → cleanup → IDLE
tests/test-fallback.sh      # A→B→C com falha total; B e C assumindo a sessão
tests/test-device-states.sh # sem aparelho, não autorizado, offline, bloqueado, sem adb
tests/test-cli.sh           # start/status/logs/restart/stop/shell da rios-launch
```

A suíte completa tem **141 casos** e roda sem root, celular ou rede. O detalhe
da revisão e o roteiro de bancada estão em
[`docs/revisao-p2.md`](../docs/revisao-p2.md).

Os testes que dependem do celular real (T3–T6, T9, T11, T12, T14) devem ser
executados na bancada, com o aparelho desbloqueado e a depuração USB autorizada.
