#!/bin/bash
# /usr/bin/panthera-superleve - Modo Super Leve I2 (ODT Secao 6 I2 + 17)
# PC <3GB RAM: desliga compositor e animacoes, zram 50%, swappiness 10.
# Economiza ~200MB. Auto no boot se RAM <3GB (com aviso). So bash.
# Uso: panthera-superleve [--auto]
set -e
echo "[Panthera Super Leve] $(date)"
# 1. Desliga compositor e animacoes (volta com Modo Equilibrado na Central)
xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || echo "sem xfconf, pulei compositor"
# 2. Memoria: swappiness 10 + zram 50% (se modulo e memoria disponiveis)
if [ -w /proc/sys/vm/swappiness ]; then echo 10 > /proc/sys/vm/swappiness && echo "[OK] swappiness 10"; fi
if command -v zramctl >/dev/null 2>&1 && [ ! -e /dev/zram0 ]; then
  modprobe zram 2>/dev/null || true
  MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  zramctl --find --size "$((MEM_KB / 2))K" 2>/dev/null && mkswap /dev/zram0 2>/dev/null && swapon /dev/zram0 2>/dev/null && echo "[OK] zram 50%" || echo "sem zram"
else
  echo "zram ja ativo ou ausente, ok"
fi
# 3. Aviso se Firefox come memoria com pouca RAM livre
FREE_MB=$(free -m | awk '/Mem:/ {print $7}')
echo "RAM livre: ${FREE_MB}MB"
if [ "$FREE_MB" -lt 1024 ]; then echo "[AVISO] Pouca RAM livre. Feche abas do Firefox."; fi
echo "[OK] Modo Super Leve ativo. Confira: free -m"
