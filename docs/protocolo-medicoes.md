# Protocolo de medição de desempenho e energia

> Tarefa **M6-01** ([issue #19](https://github.com/LarissaGiovanna/riOS/issues/19)) · alimenta
> **M6-02** (T11, #20), **M6-03** (T12, #21) e a seção de resultados do artigo (**ART-05**, #28).
> Script de coleta: [`scripts/coleta-desempenho.sh`](../scripts/coleta-desempenho.sh).
> Critérios de aprovação: [`PLAN.md`](../PLAN.md) §11 (matriz de testes) e §12 (riscos).

Este documento define **o que** é medido, **em que condições**, **por quanto tempo** e **o que
invalida uma rodada**. Sem isso, dois números de dias diferentes não são comparáveis, e a
comparação bancada × imagem — que é o argumento central do artigo — perde o sentido.

---

## 1. Escopo

**Mede-se** consumo de CPU e RAM em repouso, uso de swap/zram, temperatura, energia
(bateria e consumo) e, quando há sessão ativa, fps e latência de entrada.

**Não se mede** aqui: fps de decodificação sob carga pesada de jogos, desempenho de GPU
(a APU não é usada pelo scrcpy), ruído, ou desempenho com o celular fazendo outra tarefa.
Também não se mede a imagem "no papel": toda rodada de C1 é na VM com a mesma imagem que vai
para o pendrive/HD.

---

## 2. Condições

As duas condições existem porque o projeto tem **dois stacks** (ver [`README.md`](../README.md)):
a bancada onde o daemon foi desenvolvido e a imagem que vai ser entregue. A diferença entre
elas (swap em disco × zram, Xfce × LXQt) é justamente o que o T11 precisa responder.

| Item | **C0** — bancada | **C1** — imagem |
|---|---|---|
| Máquina | Eee PC 1015BX físico | VM (VirtualBox/`scripts/vm-virtualbox.sh`) ou o netbook com a imagem |
| Distribuição | Void Linux | Debian (imagem `rios.img`) |
| Init | runit | systemd |
| Desktop | Xfce 4.20 | LXQt |
| Gerenciador de display | lightdm | SDDM **ou** lightdm |
| Swap | partição em disco (~7,8 GB), **sem zram** | **zram** (1 GB), sem swap em disco |
| Celular | presente, DeX ativo | **ausente** |
| Resolução | 1024×600 | 1024×600 |
| RAM visível | 1,5 GiB | 1,5 GiB (RAM da VM = 1536 MB) |
| Para que serve | mede o T11 "de verdade", com DeX | mede o custo do stack da imagem, sem celular |

C1 roda **sem celular** por decisão da #20: a imagem em VM não tem dispositivo USB real
repassado, e o objetivo é isolar o custo do sistema. A medição de C1 **com DeX ativo** só
acontece se o M4-02 (#15) tiver produzido sessão; caso contrário registra-se "não coletado"
— nunca se inventa o número.

---

## 3. Métricas

| Métrica | Unidade | Como é coletada | Teste | Limiar / uso |
|---|---|---|---|---|
| CPU | % (média e máxima) | `/proc/stat`, delta entre amostras | T11 | **< 60%** em repouso |
| RAM usada | MB | `MemTotal − MemAvailable` (`/proc/meminfo`) | T11 | **< 450 MB** em repouso (orçamento ≤ 500 MB) |
| RAM disponível | MB | `MemAvailable` | T11 | contexto do pico |
| Swap usada | MB | `SwapTotal − SwapFree` | T11 | evidência de pressão de memória |
| zram usada | MB | soma de `orig_data_size` em `/sys/block/zram*/mm_stat` | T11 | comparação C0 × C1 |
| Load average (1 min) | adimensional | `/proc/loadavg` | contexto | distingue "repouso" de "ocupado" |
| Temperatura | °C | maior `thermal_zone*/temp`; se não houver, `sensors` | T12 | estabilidade (sem tendência de alta) |
| Bateria do netbook | % | `/sys/class/power_supply/BAT*/capacity` | T12 | ~86% de saúde, 29% de carga inicial |
| Consumo do netbook | W | `power_now`, ou `current_now × voltage_now` | T12 | comparação com e sem hub |
| Bateria do celular | % e °C | `adb shell dumpsys battery` | T12 | se carrega ou descarrega via USB |
| FPS | fps | `--print-fps` do scrcpy, lido do log | T11 | alvo 15 fps a 1024×600 |
| Latência de entrada | ms | **manual**, câmera em slow motion (§5) | T11 qualitativo | alvo "usável"; reportar mediana de 10 |

O script coleta tudo o que é automático. **FPS observado, latência e temperatura ambiente são
manuais** e entram no `.meta.md` (e no índice) por `--fps-medido`, `--latencia-ms` e
`--temp-ambiente`.

---

## 4. Protocolo temporal

Cada rodada tem três fases, sempre nesta ordem:

```
aquecimento 5 min  →  repouso 30 min  →  vídeo/rolagem 10 min
   (descartado)        (é o T11)          (sob carga de sessão)
```

- **Aquecimento (5 min).** Aquece o HDD de 5400 rpm e estabiliza o zram/swap. Dados desta fase
  ficam no CSV marcados como `aquecimento` e **não entram na análise**. Não pule: a primeira
  medição "a frio" é sempre pior e contaminaria a média.
- **Repouso (30 min).** Tela na tela de espera, sem celular interagindo, sem build, sem
  atualização de pacote, sem navegador. É a janela que decide o T11: **30 min é o mínimo** para
  o zram ter tempo de estabilizar e para um pico isolado não virar a média.
- **Vídeo/rolagem (10 min).** Com sessão ativa (scrcpy): rolagem contínua, um vídeo curto em
  loop, janela sendo arrastada. Em C1 sem sessão, use `--duracao-carga 0`.

**Repetições: 3 por condição, no mesmo dia e sem reiniciar a máquina entre elas.** Reporte a
**média das três** e o desvio; se uma rodada destoar mais de 10% das outras duas, investigue
antes de descartar — descarte só com motivo registrado (§6).

Amplitude de amostragem: **1 amostra a cada 5 s** (360 amostras por rodada de 30 min). Ajuste
com `--intervalo` só se o CSV ficar grande demais para o repositório.

---

## 5. Contexto obrigatório de cada rodada

Sem estes campos, a rodada não é reproduzível e não entra no artigo:

- data e hora (com fuso) — **sincronize o relógio antes** (o netbook já foi visto sem NTP);
- condição (C0/C1), **repetição** (r1..r3) e **método** de abertura do DeX (A/B/C/auto);
- versão do **scrcpy** (e do `adb`, para referência);
- **resolução**, **fps alvo**, **bitrate**, **codec**, **áudio** e **render** (o script puxa de
  `etc/rios/config` quando não forem passados por flag);
- temperatura ambiente e se havia hub alimentado;
- latência de entrada e fps observado.

O script grava tudo isso em `<CSV>.meta.md`, incluindo o hardware detectado (distro, kernel,
init, desktop, display manager, swap, zram, bateria, celular).

### Como medir a latência de entrada

Método barato e defensável: gravar com o celular em **slow motion (120–240 fps)** o trackpad e
a tela na mesma cena; contar os quadros entre o toque e a mudança de pixel; repetir **10 vezes**,
registrar a **mediana**. Em 240 fps cada quadro vale ~4 ms. Filmar a tela com o próprio celular
evita depender de relógio de software na máquina medida.

---

## 6. Conformidade e invalidação

O script **verifica** o ambiente e registra divergências no `.meta.md`:

| Verificação | C0 espera | C1 espera |
|---|---|---|
| Init | runit | systemd |
| zram | **ausente** | **presente** |
| Swap | em disco (não zram) | zram |
| Desktop | Xfce | LXQt |
| Celular | conectado | ausente |
| Relógio | sincronizado (aviso se não) | idem |

Divergência **não aborta** a coleta — mas precisa ser explicada nas observações, senão a rodada
é descartada. **Descarte** a rodada quando:

1. o aquecimento foi pulado ou a fase de repouso durou menos de 30 min;
2. houve build, instalação de pacote ou outra carga não prevista durante o repouso;
3. a sessão scrcpy foi reiniciada no meio da rodada;
4. o celular estava carregando pelo netbook **sem** hub alimentado (muda o T12);
5. a temperatura ambiente variou mais de 5 °C em relação às outras rodadas do conjunto;
6. o relógio estava dessincronizado e a data do CSV ficou errada;
7. a conformidade divergiu e não há explicação registrada.

Descartes vão para as observações do `.meta.md` com o motivo — e o descarte também é resultado:
se o T11 falha sempre que o zram está ativo, isso é achado, não erro de medição.

---

## 7. Como executar

Na bancada (C0), com a sessão já rodando e o celular conectado:

```sh
# o fps do scrcpy vem do log; inicie o scrcpy com --print-fps e guarde o stderr
scrcpy --print-fps ... 2> /tmp/scrcpy-fps.log &

# r1, r2, r3 — a mesma máquina, sem reiniciar entre elas
scripts/coleta-desempenho.sh --condicao C0 --metodo A --repeticao 1 \
    --log-scrcpy /tmp/scrcpy-fps.log --temp-ambiente 26
scripts/coleta-desempenho.sh --condicao C0 --metodo A --repeticao 2 \
    --log-scrcpy /tmp/scrcpy-fps.log --temp-ambiente 26
scripts/coleta-desempenho.sh --condicao C0 --metodo A --repeticao 3 \
    --log-scrcpy /tmp/scrcpy-fps.log --temp-ambiente 26
```

Na imagem/VM (C1), sem celular e sem fase de carga:

```sh
scripts/coleta-desempenho.sh --condicao C1 --repeticao 1 --duracao-carga 0 --temp-ambiente 26
```

Ao terminar, complete no `.meta.md` o que é manual (latência, fps observado) e confira o
checklist final do arquivo. Para testar o script sem medir nada de verdade:

```sh
scripts/coleta-desempenho.sh --condicao C0 --rapido   # 3 s, grava em docs/medicoes/_teste/
```

### Saída

```
docs/medicoes/20261125-143000-C0-r1.csv       série temporal (1 linha por amostra)
docs/medicoes/20261125-143000-C0-r1.meta.md   contexto, conformidade, resumo, pendências
docs/medicoes/indice.csv                      uma linha por rodada (consolidação)
```

O CSV tem 19 colunas, sempre na mesma ordem:

`amostra, ts_seg, ts_iso, fase, cpu_pct, load1, ram_usada_mb, ram_disp_mb, ram_total_mb,
swap_usada_mb, swap_total_mb, zram_usada_mb, temp_c, bat_pct, bat_w, bat_status, cel_pct,
cel_temp_c, fps_scrcpy`

Campo **vazio significa "não disponível"**, nunca zero: `cel_pct` fica vazio nas amostras em
que o celular não foi lido (a leitura é a cada 60 s, para o `adb` não contaminar a CPU).

---

## 8. Consolidação (entrada do M6-02 e do ART-05)

1. Confira o `indice.csv`: ele já traz, por rodada, `cpu_media`, `cpu_max`, `ram_media_mb`,
   `ram_max_mb`, `swap_media_mb` e `temp_max_c`, calculados sobre a fase de repouso.
2. Média das 3 repetições **por condição**. Reporte média e amplitude (mín–máx), não só a média.
3. Compare C0 × C1 explicando a diferença de stack — não trate como benchmark de hardware.
4. Preencha a tabela do T11 com **passa/não passa** e a causa de cada desvio; idem T12 para
   energia. O veredito é da #20/#21, não deste protocolo.
5. Gráficos para o artigo: série de CPU e RAM ao longo do tempo (uma linha por condição) e
   barras de média/máximo por condição. Os CSVs abrem direto em planilha.

O `indice.csv` é **append-only**: não edite linhas antigas. Se precisar corrigir uma rodada,
refaça a medição com outra repetição e registre o motivo.

---

## 9. Limitações conhecidas

- **Sem instrumentação elétrica.** A energia vem do `power_now` da bateria, que é estimativa do
  firmware (~±5%), não de um medidor USB. O artigo deve declarar isso.
- **`adb shell` custa CPU.** Por isso a leitura do celular é espaçada (60 s) e não entra na
  média de CPU das amostras vizinhas.
- **O HDD de 5400 rpm varia.** É a maior fonte de ruído entre rodadas; daí o aquecimento e as
  3 repetições.
- **C1 em VM não vê o hardware real** (Radeon, HDD, USB 2.0). A comparação C0 × C1 mede o
  **stack**, não o netbook.
- **FPS do scrcpy depende do formato do log.** Se a extração automática não casar com a versão
  instalada, use `--fps-medido` e registre no `.meta.md`.

---

## 10. Aceite do M6-01

- [x] Condições C0 e C1 definidas, com hardware, stack, swap/zram e presença de celular
- [x] Métricas definidas, com unidade, forma de coleta e limiar
- [x] Protocolo temporal definido (5/30/10 min, 3 repetições, amostragem de 5 s)
- [x] Contexto obrigatório de cada rodada definido (data, scrcpy, método, resolução, fps,
      bitrate, render)
- [x] `scripts/coleta-desempenho.sh` gera CSV em `docs/medicoes/`, com metadados e índice
- [x] Protocolo documentado (este arquivo), ligado no README e em `docs/ambiente-de-testes.md`
- [x] Teste automatizado do script em `tests/test-coleta-desempenho.sh`
- [ ] **Rodar as 3 repetições de C0 e as 3 de C1** — isso é M6-02 (#20), não M6-01
