#!/bin/bash
# /usr/share/panthera-src/panthera-pool-check.sh <pool_dir>
# Confere se o pool de .deb instala sozinho, sem rede.
#
# Isolado num script proprio (e nao dentro do hook) por dois motivos concretos:
#  - a v1.1.2 reprovou o build com o pool COMPLETO na mao, porque a checagem
#    tratava a lista "Inst" do apt como falha. "Inst" sao os pacotes que o apt
#    instalaria, ou seja o resultado esperado. Isolado, da para testar a guarda
#    com um apt de mentira antes de gastar 8 minutos de build.
#  - o hook chamava a guarda com "| tee -a log", e o status do pipeline e o do
#    tee, que sempre da sucesso. A falha da guarda era engolida e a ISO saia
#    prometendo offline sem entregar. Ver tests/test-pool-check.sh.
#
# O teste autoritativo e o --print-uris: ele lista as URLs que o apt AINDA
# buscaria pela rede. Vazio significa que o pool basta. Quando nao esta vazio,
# o nome do arquivo na URL diz exatamente qual pacote falta.
#
# Sai 0 se o pool resolve. Sai 1 e diz o que falta caso contrario.
set -u
POOL="${1:-/var/cache/panthera-pool}"

[ -d "$POOL" ] || { echo "pool inexistente: $POOL" >&2; exit 1; }
shopt -s nullglob
DEBS=("$POOL"/*.deb)
shopt -u nullglob
if [ "${#DEBS[@]}" -eq 0 ]; then
  echo "pool sem nenhum .deb: $POOL" >&2
  exit 1
fi

# (a) o que o apt ainda buscaria pela rede: se houver algo, o pool nao basta
QUER_BUSCAR=$(apt-get install -s --print-uris "${DEBS[@]}" 2>/dev/null | grep "^'" || true)

# (b) todo pacote que o apt instalaria tem de estar no pool
FALTA=""
for p in $(apt-get install -s "${DEBS[@]}" 2>/dev/null | awk '/^Inst /{print $2}' | sort -u); do
  ls "$POOL/$p"_*.deb >/dev/null 2>&1 || FALTA="$FALTA $p"
done

# (c) o apt nao pode reclamar de erro de fetch
ERROS=$(apt-get install -s --no-download "${DEBS[@]}" 2>&1 \
        | grep -E "^(E:|Unable to (fetch|acquire)|Err:)" || true)

if [ -n "$QUER_BUSCAR" ] || [ -n "$FALTA" ] || [ -n "$ERROS" ]; then
  echo "o pool NAO instala sozinho, sem internet" >&2
  if [ -n "$QUER_BUSCAR" ]; then
    echo "  o apt ainda buscaria estes pacotes na rede:" >&2
    echo "$QUER_BUSCAR" | while read -r l; do
      # "'<url>' <arquivo> <bytes> ..." -> nome do arquivo
      f=$(echo "$l" | awk '{print $2}')
      echo "    ${f}" >&2
    done
  fi
  [ -n "$FALTA" ] && echo "$FALTA" | tr ' ' '\n' | sed 's/^/  fora do pool: /' >&2
  [ -n "$ERROS" ] && echo "$ERROS" | sed 's/^/  apt: /' >&2
  exit 1
fi
exit 0
