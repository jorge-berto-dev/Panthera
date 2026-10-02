#!/bin/bash
# /usr/share/panthera-src/panthera-pool-check.sh [--lista] <pool_dir>
# Confere se o pool de .deb instala sozinho, sem rede.
# Com --lista, imprime so as URLs que o apt ainda buscaria e sai 0 sempre:
# e o modo que o 0250-pool usa para Baixar o que falta e tentar de novo.
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
# NAO use "apt-get install -s --no-download" para isto. Em quatro versoes ele
# respondeu "E: Unable to fetch some archives" com o pool COMPLETO na mao: o
# --no-download manda o apt recusar qualquer fetch, e o apt reporta isso como
# erro mesmo quando nao ha nada para buscar. Era falso positivo meu custando um
# ciclo de build por vez (v1.1.1, v1.1.3, v1.1.5, v1.1.6).
#
# Sai 0 se o pool resolve. Sai 1 e diz o que falta caso contrario.
set -u
LISTA=0
if [ "${1:-}" = "--lista" ]; then LISTA=1; shift; fi
POOL="${1:-/var/cache/panthera-pool}"

[ -d "$POOL" ] || { echo "pool inexistente: $POOL" >&2; exit 1; }
shopt -s nullglob
DEBS=("$POOL"/*.deb)
shopt -u nullglob
if [ "${#DEBS[@]}" -eq 0 ]; then
  echo "pool sem nenhum .deb: $POOL" >&2
  exit 1
fi

# (a) o que o apt ainda buscaria pela rede: se houver algo, o pool nao basta.
# Captura o stderr tambem, para distinguir "nao falta nada" de "o apt falhou".
SAIDA_PRINT=$(apt-get install -s --print-uris "${DEBS[@]}" 2>&1) || {
  echo "o apt-get --print-uris falhou; nao da para confiar na verificacao:" >&2
  printf '%s\n' "$SAIDA_PRINT" | sed 's/^/  apt: /' >&2
  exit 1
}
QUER_BUSCAR=$(printf '%s\n' "$SAIDA_PRINT" | grep "^'" || true)

# Modo --lista: so as URLs, para o hook baixar e repetir.
if [ "$LISTA" -eq 1 ]; then
  [ -n "$QUER_BUSCAR" ] || exit 0
  echo "$QUER_BUSCAR" | while read -r l; do
    echo "$l" | awk '{gsub(/\x27/, ""); print $1}'
  done
  exit 0
fi

# (b) rede de seguranca: todo pacote que o apt instalaria tem de estar no pool.
# O ":amd64" e removido porque o apt pode imprimir o nome qualificado por
# arquitetura, e o .deb no disco nao tem esse sufixo.
FALTA=""
for p in $(printf '%s\n' "$SAIDA_PRINT" | awk '/^Inst /{print $2}' | sed 's/:[a-z0-9]*$//' | sort -u); do
  ls "$POOL/$p"_*.deb >/dev/null 2>&1 || FALTA="$FALTA $p"
done

if [ -n "$QUER_BUSCAR" ] || [ -n "$FALTA" ]; then
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
  exit 1
fi
exit 0
