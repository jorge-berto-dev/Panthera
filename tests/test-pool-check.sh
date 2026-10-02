#!/bin/bash
# tests/test-pool-check.sh - testa a guarda do pool offline com um apt de mentira
# Uso: ./tests/test-pool-check.sh
#
# A v1.1.2 gastou um ciclo de build inteiro porque a guarda do pool estava
# errada: ela tratava a lista "Inst" do apt como falha, sendo que "Inst" sao os
# pacotes que o apt instalaria, ou seja o resultado esperado. O build reprovou
# com o pool completo na mao.
#
# Aqui a guarda e testada contra saidas controladas do apt, sem build e sem
# rede. Cada cenario abaixo JÁ ACONTECEU de verdade em algum build.
set -e
GUARDA=scripts/panthera-pool-check.sh
FAIL=0
ok() { echo "[OK] $1"; }
bad() { echo "[FALHA] $1"; FAIL=1; }

[ -x "$GUARDA" ] || { echo "$GUARDA ausente ou sem +x"; exit 1; }
bash -n "$GUARDA" || exit 1

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
STUB="$T/bin"
mkdir -p "$STUB"

# apt de mentira: le a resposta de $APTX_RESPOSTA e imprime.
cat > "$STUB/apt-get" <<'STUB'
#!/bin/bash
cat "$APTX_RESPOSTA"
STUB
chmod +x "$STUB/apt-get"

cenario() {
  local nome="$1" resposta="$2" esperado="$3"
  local pool="$T/pool-$nome"
  rm -rf "$pool"; mkdir -p "$pool"
  # O pool tem exatamente os 3 .deb que o apt resolve para firefox-esr no
  # bookworm (medido na analise do indice). Qualquer pacote fora desta lista e
  # justamente o que a guarda tem de acusar.
  touch "$pool/firefox-esr_1_amd64.deb" \
        "$pool/firefox-esr-l10n-pt-br_1_all.deb" \
        "$pool/libevent-2.1-7_1_amd64.deb"
  printf '%s\n' "$resposta" > "$T/resp"
  if APTX_RESPOSTA="$T/resp" PATH="$STUB:$PATH" bash "$GUARDA" "$pool" >/dev/null 2>&1; then
    r=0
  else
    r=1
  fi
  if [ "$r" -eq "$esperado" ]; then ok "$nome"; else bad "$nome (saida $r, esperado $esperado)"; fi
}

echo "== a guarda nao pode reprovar quando o pool esta completo =="
# Cenario real da v1.1.2: o apt instalaria exatamente os 3 pacotes do pool.
# Isso e SUCESSO. A guarda antiga reprovava aqui.
cenario "pool completo, apt lista os 3 do pool => OK" \
'Inst firefox-esr [270.7MB] (Debian:12.6/stable)
Inst firefox-esr-l10n-pt-br (Debian:12.6/stable)
Inst libevent-2.1-7 (Debian:12.6/stable)
Conf firefox-esr (Debian:12.6/stable)' 0

echo ""
echo "== mas tem que reprovar quando falta dependencia de verdade =="
# Cenario real da v1.1.1: faltava uma dependencia, que o apt tentaria buscar.
cenario "dependencia fora do pool => FALHA nomeando" \
'Inst firefox-esr [270.7MB] (Debian:12.6/stable)
Inst libavahi-common3 (Debian:12.6/stable)
E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?' 1

# caso onde o apt pede um pacote que NAO esta no pool, sem mensagem de erro:
# e o que a guarda precisa pegar mesmo sem o E:
cenario "Inst de pacote ausente, sem E: => FALHA" \
'Inst firefox-esr (Debian:12.6/stable)
Inst libavahi-common3 (Debian:12.6/stable)' 1

echo ""
echo "== e quando o apt so reclama de rede =="
cenario "apt pedindo para buscar na rede => FALHA" \
'Inst firefox-esr (Debian:12.6/stable)
E: Unable to acquire some archives' 1

echo ""
echo "== caso de borda =="
T2="$T/vazio"; mkdir -p "$T2"
if bash "$GUARDA" "$T2" >/dev/null 2>&1; then bad "pool vazio passou"; else ok "pool vazio reprova"; fi
if bash "$GUARDA" "$T/nao-existe" >/dev/null 2>&1; then bad "pool inexistente passou"; else ok "pool inexistente reprova"; fi

echo ""
echo "== o hook 0250 usa a guarda, e nao uma logica propria =="
grep -q "panthera-pool-check.sh" hooks/live/0250-pool.hook.chroot \
  && ok "0250-pool chama a guarda testada" \
  || bad "0250-pool tem logica propria: pode divergir da guarda testada"

if [ "$FAIL" -ne 0 ]; then echo "POOL-CHECK FALHOU"; exit 1; fi
echo "POOL-CHECK PASS: a guarda aceita o pool completo e reprova o incompleto."
