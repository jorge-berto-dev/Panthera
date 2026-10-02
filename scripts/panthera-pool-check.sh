#!/bin/bash
# /usr/share/panthera-src/panthera-pool-check.sh <pool_dir>
# Confere se o pool de .deb instala sozinho, sem rede.
#
# Isolado num script proprio (e nao dentro do hook) por um motivo concreto: a
# v1.1.2 reprovou o build com o pool COMPLETO na mao, porque a checagem tratava
# a lista "Inst" do apt como falha. "Inst" sao os pacotes que o apt instalaria,
# ou seja o resultado esperado. Isolado aqui, da para testar a guarda com um
# apt de mentira antes de gastar 8 minutos de build.
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

# (a) todo pacote que o apt instalaria tem de estar no pool
FALTA=""
for p in $(apt-get install -s "${DEBS[@]}" 2>/dev/null | awk '/^Inst /{print $2}' | sort -u); do
  ls "$POOL/$p"_*.deb >/dev/null 2>&1 || FALTA="$FALTA $p"
done

# (b) o apt nao pode pedir qualquer coisa pela rede
ERROS=$(apt-get install -s --no-download "${DEBS[@]}" 2>&1 \
        | grep -E "^(E:|Unable to (fetch|acquire)|Err:)" || true)

if [ -n "$FALTA" ] || [ -n "$ERROS" ]; then
  echo "o pool nao instala sozinho, sem internet" >&2
  [ -n "$FALTA" ] && echo "$FALTA" | tr ' ' '\n' | sed 's/^/  fora do pool: /' >&2
  [ -n "$ERROS" ] && echo "$ERROS" | sed 's/^/  apt: /' >&2
  exit 1
fi
exit 0
