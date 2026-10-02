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
#  - a guarda usava "apt-get install -s --no-download" como sinal de falha, e o
#    --no-download manda o apt recusar qualquer fetch: ele respondeu "E: Unable
#    to fetch" com o pool COMPLETO. Quatro builds queimados nisso (v1.1.1,
#    v1.1.3, v1.1.5, v1.1.6)
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

# apt de mentira. Com --print-uris o apt real imprime a simulacao NORMAL (com as
# linhas Inst) MAIS as linhas de URL. O stub precisa fazer igual, senao o teste
# mente sobre o que a guarda enxerga.
cat > "$STUB/apt-get" <<'STUB'
#!/bin/bash
for a in "$@"; do
  case "$a" in
    --print-uris) cat "$APTX_INST"; cat "$APTX_URIS"; exit ${APTX_URIS_RC:-0} ;;
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
  local nome="$1" inst="$2" uris="$3" esperado="$4"
  printf '%s\n' "$inst" > "$T/inst"
  printf '%s\n' "$uris" > "$T/uris"
  if APTX_INST="$T/inst" APTX_URIS="$T/uris" \
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
  "$INST_OK" "" 0

echo ""
echo "== mas tem que REPROVAR quando o apt ainda buscaria algo =="
# Cenario real da v1.1.3: os 3 estavam no pool e mesmo assim o apt dizia
# "Unable to fetch". O --print-uris e o teste autoritativo: a URL traz o nome
# do pacote que falta.
caso "apt ainda buscaria libavahi-common3 => FALHA nomeando" \
  "$INST_OK
Inst libavahi-common3 (Debian:12.6/stable)" \
  "'http://deb.debian.org/debian/pool/main/a/avahi/libavahi-common3_0.8-10_amd64.deb' libavahi-common3_0.8-10_amd64.deb 21504 SHA256:abc" 1

caso "Inst de pacote ausente, sem URL => FALHA" \
  "$INST_OK
Inst libavahi-common3 (Debian:12.6/stable)" "" 1

# Regressao do falso positivo que custou 4 builds: o apt responder
# "E: Unable to fetch" NAO e motivo de reprovar. Quem autoritativo e o
# --print-uris: se ele nao lista nada, o pool basta. Este cenario e o
# exatamente da v1.1.6.
caso "apt diz 'Unable to fetch' mas --print-uris nao lista nada => OK" \
  "$INST_OK
E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?" "" 0

# ... mas se o proprio apt falhar no --print-uris, a guarda tem de reprovar,
# porque ai nao da para confiar na verificacao.
printf '%s\n' "$INST_OK" > "$T/inst"
: > "$T/uris"
if APTX_INST="$T/inst" APTX_URIS="$T/uris" APTX_URIS_RC=1 PATH="$STUB:$PATH" \
   bash "$GUARDA" "$POOL" >/dev/null 2>&1; then
  bad "apt falhando no --print-uris passou: verificacao sem confianca"
else
  ok "apt falhando no --print-uris reprova"
fi

echo ""
echo "== o diagnostico precisa NOMEAR o pacote que falta =="
printf '%s\n' "$INST_OK" > "$T/inst"
printf "'http://deb.debian.org/debian/pool/main/a/avahi/libavahi-common3_0.8-10_amd64.deb' libavahi-common3_0.8-10_amd64.deb 21504 SHA256:abc\n" > "$T/uris"
: > "$T/nodl"
if APTX_INST="$T/inst" APTX_URIS="$T/uris" PATH="$STUB:$PATH" \
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
echo "== modo --lista: imprime as URLs e nada mais =="
printf '%s\n' "$INST_OK" > "$T/inst"
printf "'http://deb.debian.org/debian/pool/main/a/avahi/libavahi-common3_0.8-10_amd64.deb' libavahi-common3_0.8-10_amd64.deb 21504 SHA256:abc\n" > "$T/uris"
: > "$T/nodl"
SAIDA=$(APTX_INST="$T/inst" APTX_URIS="$T/uris" PATH="$STUB:$PATH" \
        bash "$GUARDA" --lista "$POOL" 2>/dev/null)
if [ "$SAIDA" = "http://deb.debian.org/debian/pool/main/a/avahi/libavahi-common3_0.8-10_amd64.deb" ]; then
  ok "--lista imprime so a URL, sem aspas e sem ruido"
else
  bad "--lista imprimiu errado: [$SAIDA]"
fi
if APTX_INST="$T/inst" APTX_URIS="$T/nodl" PATH="$STUB:$PATH" \
   bash "$GUARDA" --lista "$POOL" 2>/dev/null | grep -q .; then
  bad "--lista imprimiu algo quando nao falta nada"
else
  ok "--lista sai vazio quando o pool esta completo"
fi

echo ""
echo "== o hook se auto-completa: baixa o que falta e tenta de novo =="
# Se o hook so reprovar, cada dependencia esquecida custa um ciclo de build.
# Ele tem que baixar o que a guarda --lista aponta e reconferir.
grep -q -- "--lista" "$HOOK" \
  && ok "o hook usa o modo --lista para baixar o que falta" \
  || bad "o hook nao baixa o que falta: depende de eu adivinhar a dependencia"
grep -q "wget -q -O" "$HOOK" \
  && ok "o hook baixa a URL que a guarda apontou" \
  || bad "o hook nao baixa nada"

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
