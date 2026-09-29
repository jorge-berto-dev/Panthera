#!/bin/bash
# /usr/bin/panthera-doctor - diagnostico PT-BR (ODT Secao 5.2 + 10 + I6)
# Uso: panthera-doctor --check wifi|audio|video|printer|all
# Saida simples OK/FALTA + botao Corrigir na Central. Log /var/log/panthera-doctor.log.
# Nunca remove kernel. So bash + ferramentas do sistema.
LOG=/var/log/panthera-doctor.log
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
touch "$LOG" 2>/dev/null || LOG="$HOME/.cache/panthera-doctor.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
exec > >(tee -a "$LOG" 2>/dev/null) 2>&1
echo "[Panthera Doutor] $(date)"
FALTA=0
check_wifi() {
  echo "--- Wi-Fi ---"
  if nmcli device status 2>/dev/null | grep -q wifi; then
    echo "[OK] Wi-Fi detectado"
  else
    echo "[FALTA] Sem Wi-Fi. Veja a placa:"; lspci 2>/dev/null | grep -i net || echo "sem lspci"
    FALTA=1
  fi
  if ping -c1 -W2 9.9.9.9 >/dev/null 2>&1; then echo "[OK] Internet OK"; else echo "[AVISO] Sem internet"; fi
}
check_audio() {
  echo "--- Audio ---"
  if aplay -l 2>/dev/null | head -5; then echo "[OK] Audio listado acima"; else echo "[FALTA] Sem audio"; FALTA=1; fi
}
check_video() {
  echo "--- Video ---"
  lspci 2>/dev/null | grep -i vga || echo "[AVISO] placa nao listada"
  echo "Dica: rode glxgears para teste visual"
}
check_printer() {
  echo "--- Impressora ---"
  if lpstat -p 2>/dev/null; then echo "[OK] Impressora acima"; else echo "[AVISO] Nenhuma impressora. Conecte USB e aguarde 60s"; fi
}
case "$1" in
  --check)
    case "$2" in
      wifi) check_wifi;;
      audio) check_audio;;
      video) check_video;;
      printer) check_printer;;
      all|"") check_wifi; check_audio; check_video; check_printer;;
      *) echo "Uso: $0 --check wifi|audio|video|printer|all"; exit 2;;
    esac;;
  --help|-h) echo "Uso: $0 --check wifi|audio|video|printer|all"; exit 0;;
  *) echo "Uso: $0 --check wifi|audio|video|printer|all"; exit 2;;
esac
exit "$FALTA"
