#!/usr/bin/env bash
# =============================================================================
# tests/run-tests.sh — executa toda a suíte automatizada do riOS
#
# Não precisa de celular, netbook, root nem adb/scrcpy reais: os testes usam
# os mocks em tests/mock/ e rodam em qualquer Linux com Bash.
#
# Uso:
#   tests/run-tests.sh            # roda todos os testes
#   tests/run-tests.sh fallback   # roda só os arquivos que casam com o filtro
# =============================================================================
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${1:-}"
TOTAL=0
FAILED=0

printf 'riOS — suíte de testes automatizados\n\n'

for test in "$ROOT"/tests/test-*.sh; do
  [[ -f "$test" ]] || continue
  name="$(basename -- "$test")"
  if [[ -n "$FILTER" && "$name" != *"$FILTER"* ]]; then
    continue
  fi
  TOTAL=$(( TOTAL + 1 ))
  printf '▶ %s\n' "$name"
  if bash "$test"; then
    printf '✔ %s passou\n\n' "$name"
  else
    printf '✘ %s FALHOU\n\n' "$name"
    FAILED=$(( FAILED + 1 ))
  fi
done

if (( TOTAL == 0 )); then
  printf 'nenhum teste encontrado para o filtro "%s"\n' "$FILTER" >&2
  exit 1
fi

printf '────────────────────────────────────────────\n'
if (( FAILED == 0 )); then
  printf '%d arquivo(s) de teste, tudo passou.\n' "$TOTAL"
  exit 0
fi
printf '%d de %d arquivo(s) de teste falharam.\n' "$FAILED" "$TOTAL"
exit 1
