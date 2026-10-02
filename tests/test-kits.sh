#!/bin/bash
# tests/test-kits.sh - catalogo Panthera: valida o que a Loja vai prometer
# Uso: ./tests/test-kits.sh
#
# O catalogo e a promessa da Panthera ao usuario. Se ele mente sobre tamanho,
# sobre o que existe, ou recusa coisa que ele exige, o sistema perde a
# confianca. Este teste reprova o build quando o catalogo mente.
set -e
FAIL=0
ok() { echo "[OK] $1"; }
bad() { echo "[FALHA] $1"; FAIL=1; }

CAT=kits/catalogo.json
MOD=scripts/panthera-catalogo.py

echo "== 1. arquivos e JSON =="
[ -f "$CAT" ] && ok "$CAT existe" || { bad "$CAT ausente"; exit 1; }
[ -f "$MOD" ] && ok "$MOD existe" || { bad "$MOD ausente"; exit 1; }
python3 -m json.tool "$CAT" >/dev/null && ok "catalogo e JSON valido" || { bad "JSON invalido"; exit 1; }

echo "== 2. schema: secoes obrigatorias =="
python3 - <<'PY' && ok "apps/kits/recusados/pool_offline presentes" || bad "schema incompleto"
import json, sys
cat = json.load(open("kits/catalogo.json"))
falta = [s for s in ("apps", "kits", "recusados") if not isinstance(cat.get(s), dict)]
if not isinstance(cat.get("pool_offline"), list):
    falta.append("pool_offline")
if cat.get("versao") != 1:
    print("versao do catalogo deveria ser 1")
    sys.exit(1)
sys.exit(1 if falta else 0)
PY

echo "== 3. nenhum pacote recusado aparece em app ou kit =="
python3 - <<'PY' && ok "recusados nao vazam para o catalogo" || bad "um kit exige um pacote que a Panthera recusa"
import json, sys
cat = json.load(open("kits/catalogo.json"))
recusados = set(cat["recusados"])
achados = []
for chave, app in cat["apps"].items():
    for p in app.get("pacotes", []):
        if p in recusados:
            achados.append("app %s -> %s" % (chave, p))
for kit, dados in cat["kits"].items():
    for chave in dados["apps"]:
        if chave not in cat["apps"]:
            print("kit %s aponta para app inexistente: %s" % (kit, chave))
            sys.exit(1)
        for p in cat["apps"][chave].get("pacotes", []):
            if p in recusados:
                achados.append("kit %s -> %s" % (kit, p))
for a in achados:
    print("   " + a)
sys.exit(1 if achados else 0)
PY

echo "== 4. snapd proibido: recusado e nunca oferecido (ODT 3.2) =="
python3 - <<'PY2' && ok "snapd recusado e ausente dos apps" || bad "snapd nao esta recusado, ou esta sendo oferecido"
import json, sys
cat = json.load(open("kits/catalogo.json"))
falha = False
if "snapd" not in cat["recusados"]:
    print("   snapd deveria estar na lista de recusados")
    falha = True
for chave, app in cat["apps"].items():
    if "snapd" in app.get("pacotes", []):
        print("   app %s oferece snapd" % chave)
        falha = True
sys.exit(1 if falha else 0)
PY2

echo "== 5. nenhum item de app ja esta na base (seria redundante) =="
python3 - <<'PY' && ok "nenhum app repete pacote da base" || bad "app repete pacote que ja vem na ISO"
import json, sys
cat = json.load(open("kits/catalogo.json"))
base = {l.split("#")[0].strip() for l in open("packages-lists/panthera-base.list")}
base = {p for p in base if p and not p.startswith("#")}
achados = []
for chave, app in cat["apps"].items():
    for p in app.get("pacotes", []):
        if p in base:
            achados.append("app %s -> %s (ja na base)" % (chave, p))
for a in achados:
    print("   " + a)
sys.exit(1 if achados else 0)
PY

echo "== 6. Firefox fora da base nativa, mas no catalogo e no pool =="
if grep -qx "firefox-esr" packages-lists/panthera-base.list; then
  bad "firefox-esr ainda esta na base nativa"
else
  ok "firefox-esr saiu da base nativa"
fi
python3 -c "
import json,sys
cat=json.load(open('$CAT'))
pk=set()
for app in cat['apps'].values(): pk.update(app.get('pacotes',[]))
sys.exit(0 if 'firefox-esr' in pk else 1)
" && ok "firefox-esr continua acessivel pelo catalogo" || bad "firefox-esr sumiu do sistema inteiro"
python3 -c "
import json,sys
cat=json.load(open('$CAT'))
sys.exit(0 if 'firefox-esr' in cat['pool_offline'] else 1)
" && ok "firefox-esr esta no pool offline (ISO funciona sem internet)" || bad "sem pool offline, quem nao tem internet fica sem navegador"

echo "== 7. GNOME Software fora, senao a recusa e enfeite =="
if grep -qE "^gnome-software" packages-lists/panthera-base.list; then
  bad "gnome-software na base: burlaria a lista de recusados"
else
  ok "gnome-software nao esta na base, a garantia e real"
fi

echo "== 8. pool_offline tem pacotes que existem em algum app =="
python3 - <<'PY' && ok "pool_offline referenciado por algum app" || bad "pool_offline com pacote orfao"
import json, sys
cat = json.load(open("kits/catalogo.json"))
pk = set()
for app in cat["apps"].values():
    pk.update(app.get("pacotes", []))
orfaos = [p for p in cat["pool_offline"] if p not in pk]
for p in orfaos:
    print("   orfao: %s" % p)
sys.exit(1 if orfaos else 0)
PY

echo "== 9. kits resolvem e nao viram string de comando =="
python3 - <<'PY' && ok "todos os kits resolvem" || bad "kit nao resolve"
import importlib.util, sys, json
spec = importlib.util.spec_from_file_location("catalogo", "scripts/panthera-catalogo.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
cat = m.carregar("kits/catalogo.json")
falhas = 0
for kit in sorted(cat["kits"]):
    try:
        pacotes = m.pacotes_de(cat, kit)
        _off, etapas = m.comandos(cat, kit)
        if not etapas:
            print("   kit %s nao gera nenhum comando" % kit)
            falhas += 1
        if not pacotes and not any(i.get("comando") for _c, i in m.itens_de(cat, kit)):
            print("   kit %s nao instala nada" % kit)
            falhas += 1
    except m.CatalogoErro as e:
        print("   kit %s: %s" % (kit, e))
        falhas += 1
sys.exit(1 if falhas else 0)
PY

echo "== 10. uma transacao apt por kit, nao um apt por pacote =="
python3 - <<'PY' && ok "no maximo uma transacao apt por kit" || bad "kit abre varias transacoes apt"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("catalogo", "scripts/panthera-catalogo.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
cat = m.carregar("kits/catalogo.json")
falhas = 0
for kit in sorted(cat["kits"]):
    _off, etapas = m.comandos(cat, kit)
    aps = [argv for _r, argv in etapas if argv[0] == "apt-get"]
    if len(aps) > 1:
        print("   kit %s abre %d transacoes apt" % (kit, len(aps)))
        falhas += 1
sys.exit(1 if falhas else 0)
PY

echo "== 11. tamanhos sao medidos, nunca digitados =="
# Ignora comentarios: o codigo pode citar o "800MB" antigo numa nota.
tam_fixo() {
  grep -vE '^[[:space:]]*#' "$1" | grep -nE '"[0-9]+ ?(MB|GB|KB)"' || true
}
if [ -n "$(tam_fixo "$CAT")" ]; then
  bad "o catalogo tem tamanho digitado, e medido em tempo de instalacao"
  tam_fixo "$CAT" | sed 's/^/   /'
else
  ok "nenhum tamanho digitado no catalogo"
fi
if [ -n "$(tam_fixo scripts/panthera-store.py)" ]; then
  bad "a Loja ainda tem tamanho fixo no codigo"
  tam_fixo scripts/panthera-store.py | sed 's/^/   /'
else
  ok "a Loja nao tem tamanho fixo no codigo"
fi

echo "== 12. modulos e apps que usam o catalogo =="
python3 -m py_compile scripts/panthera-catalogo.py && ok "compila panthera-catalogo" || bad "panthera-catalogo nao compila"
for app in panthera-store panthera-welcome; do
  python3 -m py_compile "scripts/$app.py" && ok "compila $app" || bad "$app nao compila"
  python3 "scripts/$app.py" --help >/dev/null 2>&1 && ok "$app --help sem display" || bad "$app --help falhou"
done
grep -q "/usr/lib/panthera" scripts/panthera-store.py && ok "Loja acha o catalogo instalado" || bad "Loja nao aponta para /usr/lib/panthera"
grep -q "/usr/lib/panthera" scripts/panthera-welcome.py && ok "Bem-vindo acha o catalogo instalado" || bad "Bem-vindo nao aponta para /usr/lib/panthera"

echo "== 13. script de policies do Firefox =="
[ -x scripts/panthera-firefox-policies.sh ] && ok "panthera-firefox-policies executavel" || bad "falta +x em panthera-firefox-policies.sh"
bash -n scripts/panthera-firefox-policies.sh && ok "sintaxe ok" || bad "sintaxe ruim"
grep -q "apt.hooks.d" hooks/live/0300-firefox.hook.chroot && ok "hook do apt instalado pelo 0300" || bad "sem hook do apt: Firefox instalado na mao ficaria sem policies"

if [ "$FAIL" -ne 0 ]; then echo "KITS FALHOU"; exit 1; fi
N=$(python3 -c "import json;print(len(json.load(open('$CAT'))['kits']))")
echo "KITS PASS. DoD manual: abrir a Loja, ver os $N kits com tamanho medido, instalar o Kit Leve, conferir a aba de recusados."
