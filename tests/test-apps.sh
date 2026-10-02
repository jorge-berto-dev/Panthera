#!/bin/bash
# tests/test-apps.sh - FASE 6 sem traceback (ODT Secao 20.6 + 26.1)
# Uso: ./tests/test-apps.sh
# Nao precisa display: compile + --help + auditoria AST + fixtures + doctor.
set -e
FAIL=0
ok() { echo "[OK] $1"; }
bad() { echo "[FALHA] $1"; FAIL=1; }

echo "== 1. COMPILE-OK (Secao 26.1) =="
for app in panthera-central panthera-store panthera-updater panthera-welcome panthera-theme-check panthera-catalogo; do
  python3 -m py_compile "scripts/${app}.py" && ok "compile $app" || bad "compile $app"
done
for shf in scripts/panthera-doctor.sh scripts/panthera-codecs.sh scripts/panthera-superleve.sh scripts/check-wayland.sh; do
  bash -n "$shf" && ok "sintaxe $shf" || bad "sintaxe $shf"
done

echo "== 2. --help sem display =="
for app in panthera-central panthera-store panthera-updater panthera-welcome; do
  python3 "scripts/${app}.py" --help >/dev/null 2>&1 && ok "$app --help" || bad "$app --help"
done
# --meus-kits do Bem-vindo: prova que ele le o catalogo de verdade
python3 scripts/panthera-welcome.py --meus-kits >/dev/null 2>&1 && ok "welcome --meus-kits" || bad "welcome --meus-kits"

echo "== 3. Central tem 11 abas (Secao 16) =="
python3 -c "
import sys
sys.argv = ['x', '--help']
out = __import__('subprocess').check_output(['python3', 'scripts/panthera-central.py', '--help'], text=True)
abas = [l[3:] for l in out.splitlines() if l.startswith(' - ')]
assert len(abas) == 11, abas
print('11 abas:', ', '.join(abas))
" && ok "11 abas" || bad "11 abas"

echo "== 4. Nenhum callback sem try (Secao 20.6) =="
python3 -c "
import re
# Todo clicked deve passar por wrapper com try: safe/instalar/safe_check/safe_update/ok
for f in ['scripts/panthera-central.py', 'scripts/panthera-store.py', 'scripts/panthera-updater.py', 'scripts/panthera-welcome.py']:
    for i, line in enumerate(open(f), 1):
        if 'connect(\"clicked\"' in line or \"connect('clicked'\" in line:
            assert any(w in line for w in ['safe', 'instalar', 'ok']), f'{f}:{i}: {line.strip()}'
print('clicked sempre via wrapper com try')
" && ok "callbacks protegidos" || bad "callbacks protegidos"

echo "== 5. So stdlib + GTK3 (R6) =="
python3 -c "
import ast, glob
permit = {'gi', 'subprocess', 'os', 'json', 'sys', 'zipfile', 'shutil', 'time', 'shlex', 're', 'catalogo', 'importlib'}
for f in glob.glob('scripts/panthera-*.py'):
    tree = ast.parse(open(f).read())
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for a in n.names:
                assert a.name.split('.')[0] in permit, f'{f}: import {a.name}'
        elif isinstance(n, ast.ImportFrom):
            assert (n.module or '').split('.')[0] in permit, f'{f}: from {n.module}'
print('imports ok: gi + stdlib')
" && ok "imports R6" || bad "imports R6"

echo "== 6. theme-check aceita/rejeita (I9) =="
rm -rf /tmp/panthera-theme-test && mkdir -p /tmp/panthera-theme-test/good /tmp/panthera-theme-test/bad /tmp/panthera-theme-test/nojson
printf '{"tema":"Teste","accent":"#1D83FF"}' > /tmp/panthera-theme-test/good/theme.json
printf 'button{background:#1D83FF}' > /tmp/panthera-theme-test/good/style.css
printf '{"tema":"X"}' > /tmp/panthera-theme-test/bad/theme.json
printf 'a{color:red} sudo rm /etc/x' > /tmp/panthera-theme-test/bad/evil.css
printf 'nada aqui' > /tmp/panthera-theme-test/nojson/style.css
(cd /tmp/panthera-theme-test/good && zip -q ../good.panthera-theme theme.json style.css)
(cd /tmp/panthera-theme-test/bad && zip -q ../bad.panthera-theme theme.json evil.css)
(cd /tmp/panthera-theme-test/nojson && zip -q ../nojson.panthera-theme style.css)
python3 scripts/panthera-theme-check.py /tmp/panthera-theme-test/good.panthera-theme | grep -q "OK" && ok "tema bom aceito" || bad "tema bom aceito"
python3 scripts/panthera-theme-check.py /tmp/panthera-theme-test/bad.panthera-theme 2>&1 | grep -q "REJEITADO" && ok "tema malicioso rejeitado" || bad "tema malicioso rejeitado"
if python3 scripts/panthera-theme-check.py /tmp/panthera-theme-test/nojson.panthera-theme 2>&1 | grep -q "REJEITADO"; then ok "sem theme.json rejeitado"; else bad "sem theme.json rejeitado"; fi

echo "== 7. welcome abre 1 vez (I1) =="
export HOME_TMP="$(mktemp -d)"
mkdir -p "$HOME_TMP/.config/panthera" && touch "$HOME_TMP/.config/panthera/welcome-done"
HOME="$HOME_TMP" python3 scripts/panthera-welcome.py && ok "FLAG presente sai 0 sem display" || bad "FLAG presente sai 0 sem display"
HOME="$HOME_TMP" python3 scripts/panthera-welcome.py --reset | grep -q "FLAG apagada" && ok "welcome --reset" || bad "welcome --reset"
rm -rf "$HOME_TMP"

echo "== 8. doctor --check (ODT Secao 10) =="
./scripts/panthera-doctor.sh --help | grep -q "Uso" && ok "doctor --help" || bad "doctor --help"
if ./scripts/panthera-doctor.sh --check bogus >/dev/null 2>&1; then bad "doctor arg invalido sai 2"; else [ "$?" -eq 2 ] && ok "doctor arg invalido sai 2" || bad "doctor arg invalido sai 2"; fi
if ./scripts/panthera-doctor.sh --check all >/dev/null 2>&1; then ok "doctor --check all roda"; else [ "$?" -le 1 ] && ok "doctor --check all roda (com FALTA)" || bad "doctor --check all roda"; fi
[ -n "$(ls /var/log/panthera-doctor.log 2>/dev/null || ls ~/.cache/panthera-doctor.log 2>/dev/null)" ] && ok "doctor gera log" || bad "doctor gera log"

echo "== 9. desktop + autostart =="
python3 -c "
import configparser
for f, exe in [('includes.chroot/usr/share/applications/panthera-central.desktop', '/usr/bin/panthera-central'),
               ('includes.chroot/usr/share/applications/panthera-store.desktop', '/usr/bin/panthera-store'),
               ('includes.chroot/usr/share/applications/panthera-updater.desktop', '/usr/bin/panthera-updater')]:
    c = configparser.ConfigParser(interpolation=None)
    assert c.read(f), f
    assert c['Desktop Entry']['Exec'] == exe, f
    print('OK', f)
" && ok "3 desktop Exec" || bad "3 desktop Exec"
grep -q "Exec=/usr/bin/panthera-welcome.py" includes.chroot/etc/xdg/autostart/panthera-welcome.desktop && ok "autostart welcome" || bad "autostart welcome"

echo "== 10. staging usr/bin (build-iso.sh) =="
rm -rf /tmp/panthera-fase6-staging && mkdir -p /tmp/panthera-fase6-staging/usr/bin
cp scripts/panthera-central.py /tmp/panthera-fase6-staging/usr/bin/panthera-central
cp scripts/panthera-store.py /tmp/panthera-fase6-staging/usr/bin/panthera-store
cp scripts/panthera-updater.py /tmp/panthera-fase6-staging/usr/bin/panthera-updater
cp scripts/panthera-welcome.py /tmp/panthera-fase6-staging/usr/bin/panthera-welcome.py
cp scripts/panthera-theme-check.py /tmp/panthera-fase6-staging/usr/bin/panthera-theme-check.py
cp scripts/panthera-doctor.sh /tmp/panthera-fase6-staging/usr/bin/panthera-doctor
cp scripts/panthera-codecs.sh /tmp/panthera-fase6-staging/usr/bin/panthera-codecs.sh
cp scripts/panthera-superleve.sh /tmp/panthera-fase6-staging/usr/bin/panthera-superleve
cp scripts/check-wayland.sh /tmp/panthera-fase6-staging/usr/bin/panthera-check-wayland
cp scripts/panthera-firefox-policies.sh /tmp/panthera-fase6-staging/usr/bin/panthera-firefox-policies
chmod +x /tmp/panthera-fase6-staging/usr/bin/panthera-*
N=$(ls /tmp/panthera-fase6-staging/usr/bin/ | wc -l)
[ "$N" -eq 10 ] && ok "10 apps em /usr/bin" || bad "10 apps em /usr/bin (achado $N)"
grep -q "config/includes.chroot/usr/bin/panthera-central" build-iso.sh && ok "build-iso.sh entrega apps" || bad "build-iso.sh entrega apps"

if [ "$FAIL" -ne 0 ]; then echo "APPS FALHOU"; exit 1; fi
echo "APPS PASS. DoD visual (com display): abrir 11 abas, instalar VLC, atualizar, doutor all, welcome."
