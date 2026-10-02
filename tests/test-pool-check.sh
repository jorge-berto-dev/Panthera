#!/bin/bash
# tests/test-pool-check.sh - testa a guarda do pool offline com um apt de mentira
# Uso: ./tests/test-pool-check.sh
#
# Dois bugs reais de build custaram um ciclo de 8 minutos cada, e os dois vivem
# aqui dentro:
#  - a guarda tratava a lista "Inst" do apt como falha, sendo que "Inst" sao os
#    pacotes que o apt instalaria (v1.1.2, reprovou com o pool completo)
#  - o hook chamava a guarda com "| tee", e o status do pipeline e o do tee, que
#    sempre da sucesso: a falha foi engolida e a ISO saiu prometendo offline
#    (v1.1.3)
# A guarda e testada contra saidas controladas do apt, sem build e sem rede.
# Os cenarios nao sao inventados: cada um ja aconteceu.
set -e
GUARDA=scripts/panthera-pool-check.sh
HOOK=hooks/live/0250-pool.hook.chroot
FAIL=0
ok() { echo "[OK] $1"; }
bad() { echo "[FALHA] $1"; FAIL=1; }

[ -x "$GUARDA" ] || { echo "$GUARDA ausente ou sem +x"; exit 1; }
bash -n "$GUARDA" || exit 1

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
STUB="$T/bin"
mkdir -p "$STUB"

# apt de mentira: responde conforme a flag, porque a guarda usa tres modos
# (-s, --print-uris e --no-download) e cada um precisa de uma resposta.
cat > "$STUB/apt-get" <<'STUB'
#!/bin/bash
for a in "$@"; do
  case "$a" in
    --print-uris) cat "$APTX_URIS"; exit 0 ;;
    --no-download) cat "$APTX_NODL"; exit 0 ;;
  esac
done
cat "$APTX_INST"
STUB
chmod +x "$STUB/apt-get"

POOL="$T/pool"
mkdir -p "$POOL"
# O pool tem exatamente os 3 .deb que o apt resolve para firefox-esr no bookworm
# (medido no indice). Qualquer pacote fora desta lista e o que a guarda acusa.
touch "$POOL/firefox-esr_1_amd64.deb" \
      "$POOL/firefox-esr-l10n-pt-br_1_all.deb" \
      "$POOL/libevent-2.1-7_1_amd64.deb"

caso() {
  local nome="$1" inst="$2" uris="$3" nodl="$4" esperado="$5"
  printf '%s\n' "$inst" > "$T/inst"
  printf '%s\n' "$uris" > "$T/uris"
  printf '%s\n' "$nodl"  > "$T/nodl"
  if APTX_INST="$T/inst" APTX_URIS="$T/uris" APTX_NODL="$T/nodl" \
     PATH="$STUB:$PATH" bash "$GUARDA" "$POOL" > "$T/saida" 2>&1; then
    r=0
  else
    r=1
  fi
  if [ "$r" -eq "$esperado" ]; then
    ok "$nome"
  else
    bad "$nome (saida $r, esperado $esperado)"
    sed 's/^/        /' "$T/saida"
  fi
}

INST_OK='Inst firefox-esr [270.7MB] (Debian:12.6/stable)
Inst firefox-esr-l10n-pt-br (Debian:12.6/stable)
Inst libevent-2.1-7 (Debian:12.6/stable)
Conf firefox-esr (Debian:12.6/stable)'

echo "== o pool completo tem que PASSAR =="
# Cenario real da v1.1.2: o apt instalaria exatamente os 3 do pool, e o
# --print-uris NAO deve listar nada para buscar. Se aparecer uma URL aqui, o
# pool esta incompleto.
caso "pool completo: Inst lista os 3 e nada a buscar => OK" \
  "$INST_OK" "" "" 0

echo ""
echo "== mas tem que REPROVAR quando o apt ainda buscaria algo =="
# Cenario real da v1.1.3: os 3 estavam no pool e mesmo assim o apt dizia
# "Unable to fetch". O --print-uris e o teste autoritativo: a URL traz o nome
# do pacote que falta.
caso "apt ainda buscaria libavahi-common3 => FALHA nomeando" \
  "$INST_OK
Inst libavahi-common3 (Debian:12.6/stable)" \
  "'http://deb.debian.org/debian/pool/main/a/avahi/libavahi-common3_0.8-10_amd64.deb' libavahi-common3_0.8-10_amd64.deb 21504 SHA256:abc" \
  "" 1

caso "Inst de pacote ausente, sem URL => FALHA" \
  "$INST_OK
Inst libavahi-common3 (Debian:12.6/stable)" "" "" 1

caso "apt reclamando de fetch => FALHA" \
  "$INST_OK" "" \
  "E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?" 1

echo ""
echo "== o diagnostico precisa NOMEAR o pacote que falta =="
printf '%s\n' "$INST_OK" > "$T/inst"
printf "'http://deb.debian.org/debian/pool/main/a/avahi/libavahi-common3_0.8-10_amd64.deb' libavahi-common3_0.8-10_amd64.deb 21504 SHA256:abc\n" > "$T/uris"
: > "$T/nodl"
if APTX_INST="$T/inst" APTX_URIS="$T/uris" APTX_NODL="$T/nodl" PATH="$STUB:$PATH" \
   bash "$GUARDA" "$POOL" 2>&1 | grep -q "libavahi-common3_0.8-10_amd64.deb"; then
  ok "a saida nomeia o .deb que o apt ainda buscaria"
else
  bad "a saida nao diz qual pacote falta: erro sem diagnostico"
fi

echo ""
echo "== caso de borda =="
if bash "$GUARDA" "$T/nao-existe" >/dev/null 2>&1; then bad "pool inexistente passou"; else ok "pool inexistente reprova"; fi
mkdir -p "$T/vazio"
if bash "$GUARDA" "$T/vazio" >/dev/null 2>&1; then bad "pool vazio passou"; else ok "pool vazio reprova"; fi

echo ""
echo "== o hook usa a guarda E escuta a saida dela =="
grep -q "panthera-pool-check.sh" "$HOOK" \
  && ok "0250-pool chama a guarda testada" \
  || bad "0250-pool tem logica propria: pode divergir da guarda testada"
# Regressao do bug do pipe: o status de "guarda | tee" e o do tee.
# So interessa a INVOCACAO da guarda dentro de um if. Um "echo ... | tee" nao
# engole nada e nao deve contar aqui.
if grep -E '^[[:space:]]*if .*panthera-pool-check\.sh.*\|' "$HOOK" >/dev/null 2>&1; then
  bad "o hook chama a guarda com | tee: o status do pipeline e o do tee e a falha e engolida"
  grep -nE '^[[:space:]]*if .*panthera-pool-check\.sh.*\|' "$HOOK" | sed 's/^/        /'
else
  ok "o hook nao engole a falha da guarda com pipe para tee"
fi
grep -q "panthera-pool-check.sh" build-iso.sh \
  && ok "a guarda e entregue no chroot" \
  || bad "a guarda nao e entregue no chroot: o 0250 reprova sempre"

if [ "$FAIL" -ne 0 ]; then echo "POOL-CHECK FALHOU"; exit 1; fi
echo "POOL-CHECK PASS: aceita o pool completo, reprova o incompleto e nomeia o que falta."
