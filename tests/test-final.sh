#!/bin/bash
# tests/test-final.sh - FASE 7 release (ODT Secao 12 + 20.7)
# Uso: ./tests/test-final.sh
# Roda todas as suites estaticas e escreve out/matriz.txt (Secao 12).
# Testes manuais (QEMU/Ventoy/ferro) ficam PENDENTE com o comando exato.
set -e
FAIL=0
MATRIZ="out/matriz.txt"
mkdir -p out guias
{
echo "Panthera v1 - matriz de release FASE 7 - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Autoridade: Panthera_OS_Prompt_Mestre.odt Secao 12"
echo ""
} > "$MATRIZ"

run() { # run <nome> <comando...>
  N="$1"; shift
  if "$@" >/tmp/panthera-final-"$N".log 2>&1; then
    echo "[OK] estatico $N"
    echo "PASS estatico $N" >> "$MATRIZ"
  else
    echo "[FALHA] estatico $N (veja /tmp/panthera-final-$N.log)"
    echo "FAIL estatico $N" >> "$MATRIZ"
    FAIL=1
  fi
  # Preserva o log: o container do CI e --rm, /tmp some no fim do run
  cp "/tmp/panthera-final-$N.log" "out/final-$N.log" 2>/dev/null || true
}

echo "== suites estaticas =="
run check ./build-iso.sh --check
run iso ./tests/test-iso.sh
run hardening ./tests/test-hardening.sh
run apps ./tests/test-apps.sh

echo "== artefatos FASE 7 =="
for f in guias/GUIA-VENTOY.md guias/GUIA-INSTALACAO.md includes.chroot/usr/share/panthera-ajuda/index.html; do
  if [ -f "$f" ]; then echo "[OK] $f"; echo "PASS $f" >> "$MATRIZ"; else echo "[FALTA] $f"; echo "FAIL $f" >> "$MATRIZ"; FAIL=1; fi
done
python3 -c "import html.parser; html.parser.HTMLParser().feed(open('includes.chroot/usr/share/panthera-ajuda/index.html').read()); print('ajuda HTML valido')" && echo "PASS ajuda HTML" >> "$MATRIZ" || { echo "FAIL ajuda HTML" >> "$MATRIZ"; FAIL=1; }
grep -q "LIBERDADE PARA O SEU MUNDO" includes.chroot/usr/share/panthera-ajuda/index.html && echo "[OK] ajuda slogan"

{
echo ""
echo "== Secao 12: testes manuais (exigem ISO em Debian 12 + ferro) =="
echo "PENDENTE T-QEMU: qemu-system-x86_64 -m 2048 -cdrom out/*.iso -boot d (Live 90s + Boas-vindas)"
echo "PENDENTE T-VENTOY-UEFI: copiar exFAT, boot UEFI, sem rescue, Wi-Fi lista (guia GUIA-VENTOY.md)"
echo "PENDENTE T-VENTOY-BIOS: boot Legacy, instala (guia GUIA-VENTOY.md)"
echo "PENDENTE T-INSTALL: Apagar tudo <=25min HD VM, reboot LightDM (guia GUIA-INSTALACAO.md)"
echo "PENDENTE T-RAM: free -m 2min apos boot, idle <=700MB"
echo "PENDENTE T-DISCO: df / instalado 6-9GB"
echo "PENDENTE T-WIFI-SOM-VIDEO: YouTube 720p 60s + som + impressao sem travar"
echo "PENDENTE T-SEC: 10 provas Secao 9 (comandos no fim de out/provas.txt)"
echo "PENDENTE T-CIDA: Firefox + papel + atualizar <=3 cliques sem terminal (ajuda offline)"
echo "PENDENTE T-NVIDIA: driver com erro volta nouveau, log, sem preta eterna"
echo ""
echo "== peso RF001 (politica Secao 8 + 20.7) =="
echo "Teto 2252MB. build-iso.sh reprova acima. Se pesar, cortar nesta ordem:"
echo "1) fontes CJK extras 2) docs/mans restantes 3) impressoras raras 4) jogos."
echo "Nunca cortar: firmware Wi-Fi, Firefox ESR, Calamares."
echo "Corte atual no hook 0600: apt clean + /usr/share/doc + /usr/share/man + caches."
echo ""
echo "== bundle de entrega =="
echo "out/panthera-v1.0-uso-geral-amd64-hybrid.iso + .sha256 (gerar em Debian 12: sudo ./build-iso.sh)"
echo "guias/GUIA-VENTOY.md + guias/GUIA-INSTALACAO.md + out/matriz.txt + out/provas.txt"
} >> "$MATRIZ"

if [ "$FAIL" -ne 0 ]; then echo "RELEASE FALHOU (estatico). Veja $MATRIZ"; exit 1; fi
echo "RELEASE estatico PASS. Matriz em $MATRIZ"
