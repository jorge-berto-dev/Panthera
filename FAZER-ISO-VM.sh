#!/bin/bash
# FAZER-ISO-VM.sh - roda DENTRO da VM Debian 12, faz TUDO sozinho.
# Uso: ./FAZER-ISO-VM.sh
# (pede sua senha sudo 1 vez; sem sudo, rode como root via su -)
# Log completo em ~/iso-build.log. Dura 30-60 min. Nao feche.
set -e
set -o pipefail
cd "$(dirname "$0")"
if [ "$EUID" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "Elevando com sudo (digite SUA senha)..."
    exec sudo -E "$0" "$@"
  else
    echo "Sem sudo neste usuario. Rode:"
    echo "  su -"
    echo "  cd ~/panthera && ./FAZER-ISO-VM.sh"
    exit 1
  fi
fi
echo "== [1/5] validacao estatica =="
apt clean 2>/dev/null || true
./build-iso.sh --check
echo "== [2/5] build da ISO (30-60 min) =="
if ! ./build-iso.sh 2>&1 | tee ~/iso-build.log; then
  echo ""
  echo "########## O BUILD FALHOU. ERRO REAL ABAIXO ##########"
  grep -i -E "falha|error|erro|E: " ~/iso-build.log | head -20
  echo "#####################################################"
  echo "Mande FOTO desta tela no chat. Log completo em ~/iso-build.log"
  exit 1
fi
echo "== [3/5] verificacao ISO+SHA+peso =="
if ! ls out/*.iso out/*.iso.sha256 >/dev/null 2>&1; then
  echo "FALHA: ISO nao gerada. Veja o erro acima ou ~/iso-build.log"
  exit 1
fi
./tests/test-iso.sh 2>&1 | tee -a ~/iso-build.log
echo "== [4/5] release final =="
./tests/test-final.sh 2>&1 | tee -a ~/iso-build.log
echo ""
echo "=================================================="
echo "ISO PRONTA:"
ls -lh out/*.iso out/*.iso.sha256
echo "=================================================="
echo "Log completo em ~/iso-build.log"
echo "Proximo: copiar a ISO de volta (scp reverso ou pendrive)."
