# riOS — O que ainda falta na frente P2

Resumo curto das lacunas depois da revisão do daemon/CLI (ver
[`revisao-p2.md`](revisao-p2.md)). A suíte passa com adb/scrcpy simulados
(141 casos), mas isso **não** equivale a validar no aparelho real.

---

## 1. O que já está pronto

- `runtime/rios-session` e `runtime/rios-launch` revisados e corrigidos.
- Fallbacks A/B/C exercitados (A→B, A e B→C, e falha total).
- Máquina de estados, hotplug simulado, config e CLI cobertos por teste.
- `docs/OPERATOR.md`, `docs/TROUBLESHOOTING.md` e `docs/revisao-p2.md`.
- 7 commits locais; nada enviado ao `origin`.

---

## 2. Lacunas de validação (dependem do Galaxy)

| Item | Por que falta | Quem / onde |
|---|---|---|
| T3 — detecção, autorização e tela bloqueada | `dumpsys window` real varia por One UI | Larissa + Galaxy |
| T4 — DeX em display virtual | Confirmar `--new-display` e barra de tarefas no S24 | Larissa + Galaxy |
| T5 — teclado ABNT2 e trackpad | Só o hardware real prova | Larissa + Galaxy |
| T6/T7 — hotplug e fallback reais | Unplug físico e falha real de método | Larissa + Galaxy |
| T11/T12 — latência, FPS, CPU, RAM, energia | Exige medição no netbook | bancada |
| T14 — sessão longa / estabilidade | Exige tempo de uso real | bancada |

Roteiro detalhado em [`revisao-p2.md`](revisao-p2.md) §5 e matriz em
[`../tests/PENDING-HARDWARE.md`](../tests/PENDING-HARDWARE.md).

---

## 3. Lacunas de código e empacotamento

1. **Instalação do runtime na imagem (P3).**
   `build/post-install.sh` cria o autostart com `Exec=rios-session`, mas
   `build/build-rios.sh` não copia `runtime/` nem `etc/rios/config` para a
   imagem. Sem isso, a unidade sobe apontando para um binário inexistente.
2. **Tela de espera e atalho Alt+T.**
   As mensagens existem no daemon, mas a instalação do visualizador/atalho na
   imagem ainda não foi feita.
3. **Serviço e logs no Debian.**
   Falta a unidade systemd e a rotação via `svlogd` (o M1 usa runit).
4. **Presets `PROFILE`.**
   O `PLAN.md` prevê perfis de resolução/FPS; o daemon ainda não os aplica.
5. **Checagem de versão do scrcpy.**
   O fallback A depende de `--new-display`; falta validar a versão mínima antes
   de tentar o método e avisar cedo.
6. **Detecção de imagem preta.**
   O watchdog vê processo vivo, não pixels (limitação L1). Se a bancada mostrar
   travamento com processo de pé, será preciso capturar a janela (`xdotool`).
7. **Testes faltantes.**
   Sem cobertura para preset `PROFILE`, checagem de versão do scrcpy,
   instalação/desinstalação do serviço e recuperação de log corrompido.

---

## 4. Lacuna do artigo

A **Seção 3** (atribuição e descrição da frente P2) ainda não foi escrita. O
repositório não tem `.tex` nem `.bib`; o texto do artigo está fora dele.

---

## 5. Ordem sugerida

1. Bancada T3–T7 com a Larissa (desbloqueia as demais decisões).
2. Corrigir o que a bancada revelar (L1/L2 e versão do scrcpy).
3. Fechar o empacotamento P3: runtime + config na imagem, systemd, `svlogd`.
4. Escrever a Seção 3 do artigo com os resultados de T3–T7.
5. Reavaliar presets `PROFILE` e completar os testes faltantes.
