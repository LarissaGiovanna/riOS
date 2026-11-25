# Medições — dados brutos

Séries temporais geradas por [`scripts/coleta-desempenho.sh`](../../scripts/coleta-desempenho.sh),
seguindo o protocolo em [`docs/protocolo-medicoes.md`](../protocolo-medicoes.md).

## Nomes

```
20261125-143000-C0-r1.csv        série: <AAAAMMDD-HHMMSS>-<condição>-r<repetição>
20261125-143000-C0-r1.meta.md    contexto, conformidade, resumo e pendências da rodada
indice.csv                       uma linha por rodada (append-only)
```

## Regras

- **Dados brutos são versionados.** O T11/T12 e o ART-05 precisam citar os arquivos; não
  reescreva nem "limpe" um CSV já commitado.
- **Corrigir uma rodada = refazer a medição**, com outra repetição, e registrar o motivo no
  `.meta.md`. O `indice.csv` é append-only.
- Campo vazio no CSV significa **não disponível**, nunca zero.
- `_teste/` (modo `--rapido`) é ignorado pelo git: são dados de 2 segundos, não medição.
- Os arquivos são públicos. Não há IP nem MAC neles, mas o `.meta.md` traz o `hostname` da
  máquina — se isso for problema, use `--saida` fora do repositório para essa rodada.
