#!/usr/bin/env bash
# =============================================================================
# tests/test-coleta-desempenho.sh — testa scripts/coleta-desempenho.sh (M6-01)
#
# Roda o coletor em modo --rapido (2 s por rodada) dentro de um diretório
# temporário e valida o contrato de saída: CSV, .meta.md e índice. Não escreve
# em docs/medicoes e não depende de celular, netbook, adb, zram nem /sys.
# =============================================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/coleta-desempenho.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rios-test-med.XXXXXX")"
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ok()  { PASS=$(( PASS + 1 )); printf '  ok   %s\n' "$*"; }
bad() { FAIL=$(( FAIL + 1 )); printf '  FALHA %s\n' "$*"; }

printf 'test-coleta-desempenho\n'

# ---------------------------------------------------------------------------
# 1. Interface: ajuda e recusa de argumento inválido.
# ---------------------------------------------------------------------------
if "$SCRIPT" --ajuda >"$TMP/ajuda" 2>&1; then
  ok "--ajuda termina com 0"
else
  bad "--ajuda retornou erro"
fi
if grep -q -- '--condicao' "$TMP/ajuda"; then
  ok "--ajuda documenta --condicao"
else
  bad "--ajuda não cita --condicao"
fi

if "$SCRIPT" >"$TMP/sem.out" 2>"$TMP/sem.err"; then
  bad "aceitou rodar sem --condicao"
else
  ok "rejeita execução sem --condicao"
fi
if grep -q -- '--condicao' "$TMP/sem.err"; then
  ok "mensagem de erro cita --condicao"
else
  bad "mensagem de erro não explica o que faltou"
fi

if "$SCRIPT" --condicao X9 >"$TMP/x9.out" 2>"$TMP/x9.err"; then
  bad "aceitou --condicao X9"
else
  ok "rejeita --condicao fora de C0/C1"
fi
if grep -q 'C0 ou C1' "$TMP/x9.err"; then
  ok "erro de condição explica os valores válidos"
else
  bad "erro de condição não explica os valores válidos"
fi

if "$SCRIPT" --condicao C0 --repeticao abc >"$TMP/rep.out" 2>/dev/null; then
  bad "aceitou --repeticao não numérica"
else
  ok "rejeita --repeticao não numérica"
fi

if [ -x "$SCRIPT" ]; then
  ok "script é executável (bit +x)"
else
  bad "script sem bit de execução (git mode 100755)"
fi

# ---------------------------------------------------------------------------
# 2. Rodada C0 em modo rápido: CSV, metadados e índice.
# ---------------------------------------------------------------------------
SAIDA="$TMP/med"
if "$SCRIPT" --condicao C0 --rapido --saida "$SAIDA" --metodo A \
        --nota "nota com vírgula, e acentuação" >"$TMP/run.out" 2>"$TMP/run.err"; then
  ok "rodada C0 --rapido termina com 0"
else
  bad "rodada C0 --rapido falhou"
  cat "$TMP/run.err" >&2 || true
  cat "$TMP/run.out" >&2 || true
fi

CSV="$(ls "$SAIDA"/*-C0-r1.csv 2>/dev/null | head -1 || true)"
if [ -n "${CSV:-}" ] && [ -f "$CSV" ]; then
  ok "CSV criado: $(basename "$CSV")"

  if head -1 "$CSV" | grep -q '^amostra,ts_seg,ts_iso,fase,'; then
    ok "cabeçalho do CSV no formato esperado"
  else
    bad "cabeçalho inesperado: $(head -1 "$CSV")"
  fi

  COLUNAS="$(head -1 "$CSV" | awk -F, '{print NF}')"
  if [ "$COLUNAS" -eq 19 ]; then
    ok "CSV com 19 colunas"
  else
    bad "CSV com $COLUNAS colunas (esperado 19)"
  fi

  if awk -F, 'NR==1 {n=NF; next} NF != n {exit 1}' "$CSV"; then
    ok "todas as linhas têm o mesmo número de campos"
  else
    bad "há linha com número de campos diferente do cabeçalho"
  fi

  AMOSTRAS=$(( $(wc -l <"$CSV") - 1 ))
  if [ "$AMOSTRAS" -ge 2 ]; then
    ok "gerou $AMOSTRAS amostras"
  else
    bad "gerou só $AMOSTRAS amostra(s)"
  fi

  if grep -q ',repouso,' "$CSV"; then
    ok "fase de repouso registrada no CSV"
  else
    bad "nenhuma amostra marcada como repouso"
  fi

  if grep -q ',aquecimento,' "$CSV"; then
    bad "--rapido deveria desligar a fase de aquecimento"
  else
    ok "--rapido desliga o aquecimento"
  fi

  META="${CSV%.csv}.meta.md"
  if [ -f "$META" ]; then
    ok "metadados criados: $(basename "$META")"
    if grep -q '| Condição | C0 |' "$META"; then
      ok "metadados registram a condição"
    else
      bad "metadados não registram a condição"
    fi
    if grep -q 'MODO TESTE' "$META"; then
      ok "metadados avisam que é modo teste"
    else
      bad "metadados não avisam que é modo teste"
    fi
    if grep -q 'Conformidade com C0' "$META"; then
      ok "metadados trazem a seção de conformidade"
    else
      bad "metadados sem seção de conformidade"
    fi
  else
    bad "metadados ausentes ($META)"
  fi
else
  bad "CSV não foi criado em $SAIDA"
fi

IND="$SAIDA/indice.csv"
if [ -f "$IND" ]; then
  ok "índice criado"
  if grep -q '^arquivo,data_iso,host,condicao' "$IND"; then
    ok "índice com cabeçalho"
  else
    bad "índice sem cabeçalho esperado"
  fi
  if [ "$(wc -l <"$IND")" -eq 2 ]; then
    ok "índice com 1 rodada"
  else
    bad "índice com $(wc -l <"$IND") linha(s) (esperado 2)"
  fi
  if grep -q 'nota com vírgula, e acentuação' "$IND"; then
    ok "nota com vírgula preservada entre aspas"
  else
    bad "nota com vírgula perdida ou quebrou o CSV do índice"
  fi
else
  bad "indice.csv não foi criado"
fi

# ---------------------------------------------------------------------------
# 3. Segunda rodada: acumula no índice sem duplicar cabeçalho.
# ---------------------------------------------------------------------------
if "$SCRIPT" --condicao C0 --rapido --saida "$SAIDA" --repeticao 2 >/dev/null 2>&1; then
  ok "segunda rodada (r2) termina com 0"
else
  bad "segunda rodada (r2) falhou"
fi
if [ -f "$IND" ]; then
  if [ "$(wc -l <"$IND")" -eq 3 ]; then
    ok "índice acumula rodadas"
  else
    bad "índice com $(wc -l <"$IND") linha(s) após a segunda rodada"
  fi
  if [ "$(grep -c '^arquivo,' "$IND")" -eq 1 ]; then
    ok "cabeçalho do índice não duplicou"
  else
    bad "cabeçalho do índice duplicado"
  fi
fi

# ---------------------------------------------------------------------------
# 4. A condição C1 é aceita e gera sua própria série.
# ---------------------------------------------------------------------------
if "$SCRIPT" --condicao C1 --rapido --saida "$SAIDA" >/dev/null 2>&1; then
  ok "rodada C1 termina com 0"
else
  bad "rodada C1 falhou"
fi
if ls "$SAIDA"/*-C1-r1.csv >/dev/null 2>&1; then
  ok "CSV da condição C1 criado"
else
  bad "CSV da condição C1 ausente"
fi

# ---------------------------------------------------------------------------
# 5. As durações longas são recusadas como não numéricas, e não há efeito
#    colateral em docs/medicoes quando --saida aponta para fora do repo.
# ---------------------------------------------------------------------------
if [ -d "$ROOT/docs/medicoes/_teste" ]; then
  bad "o teste deixou lixo em docs/medicoes/_teste"
else
  ok "não escreveu em docs/medicoes durante o teste"
fi

printf '\n%d ok, %d falha(s)\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
