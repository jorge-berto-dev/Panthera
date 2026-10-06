#!/bin/bash
# scripts/panthera-grub-patch.sh <dir-binary> <dir-branding>
# Aplica tema + autoboot + marca Panthera no menu de boot JA GERADO.
#
# Roda no build-iso.sh DEPOIS do "lb build", seguido de "lb binary_iso".
# Motivo, verificado na v1.2.1: o grub.cfg real so e escrito depois que os
# hooks binarios rodam. Patch em hook binario criou um stub que a geracao real
# sobrescreveu, e a ISO saiu com o menu Debian sem ninguem avisar.
#
# Cada transformacao abaixo foi extraida da ISO v1.1.8 de verdade, nao de
# palpite sobre o formato do live-build. E cada uma REPROVA se a string
# esperada sumir (formato mudou) em vez de fingir que aplicou.
#
# Idempotente: rodar duas vezes nao duplica nada.
set -e
BIN="${1:?uso: $0 <dir-binary> <dir-branding>}"
SRC="${2:?uso: $0 <dir-binary> <dir-branding>}"
N=0
ok() { N=$((N + 1)); echo "[boot-patch] OK: $1"; }
falha() { echo "[boot-patch] FALHA: $1" >&2; exit 1; }

[ -d "$BIN" ] || falha "sem dir-binary $BIN"
[ -d "$SRC" ] || falha "sem dir-branding $SRC"

# ---------- UEFI: grub.cfg (entradas "Live system (amd64)", sem "Debian") ----------
GRUBCFG="$BIN/boot/grub/grub.cfg"
[ -f "$GRUBCFG" ] || falha "sem $GRUBCFG para corrigir"
cp "$GRUBCFG" "$GRUBCFG.panthera-bak" 2>/dev/null || true
if grep -q 'menuentry "Panthera"' "$GRUBCFG"; then
  echo "[boot-patch] entradas do GRUB ja marcadas, mantendo" >&2
elif grep -q 'menuentry "Live system (amd64)"' "$GRUBCFG"; then
  sed -i 's/menuentry "Live system (amd64)"/menuentry "Panthera"/' "$GRUBCFG"
  sed -i 's/menuentry "Live system (amd64 fail-safe mode)"/menuentry "Panthera (modo seguro)"/' "$GRUBCFG"
else
  falha "formato do grub.cfg mudou: sem entrada Live nem Panthera"
fi
grep -q 'menuentry "Panthera"' "$GRUBCFG" || falha "marca nao pegou no grub.cfg"
ok "entradas do GRUB: Panthera + modo seguro"

# ---------- UEFI: autoboot (no grub.cfg, NAO no config.cfg) ----------
# config.cfg nao existe em binary/ na hora do pos-build: ele so aparece na ISO
# final, gerado na montagem. Tentar corrigir la era FALHA garantida (foi o que
# matou a v1.3.0). Como o grub.cfg faz "source /boot/grub/config.cfg" na
# PRIMEIRA linha, um "set timeout=5" nele sobrescreve qualquer valor do config.
if grep -q "^set timeout=" "$GRUBCFG"; then
  sed -i -E 's/^set timeout=.*/set timeout=5/' "$GRUBCFG"
else
  sed -i '/^source \/boot\/grub\/config.cfg/a set timeout=5' "$GRUBCFG"
fi
grep -q "^set timeout=5" "$GRUBCFG" || falha "autoboot nao pegou no grub.cfg"
ok "GRUB inicia sozinho em 5s"

# ---------- UEFI: splash + tema (theme.cfg usa live-theme/ se splash.png existe) ----------
[ -f "$SRC/boot/grub-background.png" ] || falha "sem background.png em $SRC"
cp "$SRC/boot/grub-background.png" "$BIN/boot/grub/splash.png"
mkdir -p "$BIN/boot/grub/live-theme"
[ -f "$SRC/grub/theme.txt" ] || falha "sem theme.txt em $SRC"
cp "$SRC/grub/theme.txt" "$BIN/boot/grub/live-theme/theme.txt"
cp "$SRC/boot/grub-background.png" "$BIN/boot/grub/live-theme/background.png"
# fontes para o tema (sem unicode.pf2 o tema cai para texto, sem aviso)
for PF2 in /usr/share/grub/unicode.pf2 /usr/lib/grub/i386-pc/unicode.pf2; do
  if [ -f "$PF2" ]; then
    mkdir -p "$BIN/boot/grub/fonts"
    cp "$PF2" "$BIN/boot/grub/fonts/unicode.pf2" 2>/dev/null || true
    break
  fi
done
ok "splash + tema GRUB posicionados"

# ---------- Legacy: entradas do live.cfg ----------
LIVE="$BIN/isolinux/live.cfg"
if [ -f "$LIVE" ]; then
  cp "$LIVE" "$LIVE.panthera-bak" 2>/dev/null || true
  if grep -q "menu label \^Panthera" "$LIVE"; then
    echo "[boot-patch] live.cfg ja marcado, mantendo" >&2
  elif grep -q "Live system (amd64)" "$LIVE"; then
    sed -i 's/menu label \^Live system (amd64)/menu label ^Panthera/' "$LIVE"
    sed -i 's/menu label Live system (amd64 fail-safe mode)/menu label Panthera (modo seguro)/' "$LIVE"
  else
    falha "formato do live.cfg mudou: sem entrada Live nem Panthera"
  fi
  grep -q "menu label \^Panthera" "$LIVE" || falha "marca nao pegou no live.cfg"
  ok "entradas Legacy: Panthera + modo seguro"
else
  falha "sem $LIVE"
fi

# ---------- Legacy: titulo, autoboot e mensagem ----------
for CFG2 in "$BIN/isolinux/isolinux.cfg" "$BIN/isolinux/menu.cfg"; do
  [ -f "$CFG2" ] || continue
  if ! grep -qi "Panthera" "$CFG2"; then
    if grep -qi "^MENU TITLE" "$CFG2"; then
      sed -i -E 's/^MENU TITLE.*/MENU TITLE Panthera - LIBERDADE PARA O SEU MUNDO/i' "$CFG2"
    else
      printf 'MENU TITLE Panthera - LIBERDADE PARA O SEU MUNDO\n' >> "$CFG2"
    fi
  fi
done
ISO="$BIN/isolinux/isolinux.cfg"
if [ -f "$ISO" ]; then
  if grep -qi "^TIMEOUT" "$ISO"; then
    sed -i -E 's/^TIMEOUT.*/TIMEOUT 50/i' "$ISO"
  else
    printf '\nTIMEOUT 50\n' >> "$ISO"
  fi
  grep -qi "^TIMEOUT 50" "$ISO" || falha "autoboot nao pegou no isolinux.cfg"
  ok "Legacy inicia sozinho em 5s"
fi
STD="$BIN/isolinux/stdmenu.cfg"
if [ -f "$STD" ]; then
  cp "$STD" "$STD.panthera-bak" 2>/dev/null || true
  if ! grep -q "Iniciando em 5s" "$STD"; then
    sed -i 's/^menu tabmsg .*/menu tabmsg Iniciando em 5s... ENTER para bootar, TAB para editar/' "$STD"
  fi
  grep -q "Iniciando em 5s" "$STD" || falha "tabmsg nao pegou"
  ok "mensagem do menu em portugues"
fi

# ---------- Legacy: splash com a pantera (tira o swirl amarelo do Debian) ----------
[ -f "$SRC/boot/grub-background.png" ] || falha "sem background para o splash Legacy"
cp "$SRC/boot/grub-background.png" "$BIN/isolinux/splash.png"
python3 -c "
from PIL import Image
Image.open('$SRC/boot/grub-background.png').resize((800, 600)).save('$BIN/isolinux/splash800x600.png')
" 2>/dev/null || cp "$SRC/boot/grub-background.png" "$BIN/isolinux/splash800x600.png"
ok "splash Legacy com a pantera"

# ---------- .disk/info (alimenta o search do GRUB e a linha Built:) ----------
INFO="$BIN/.disk/info"
if [ -f "$INFO" ]; then
  cp "$INFO" "$INFO.panthera-bak" 2>/dev/null || true
  if ! grep -q "^Panthera" "$INFO"; then
    DATA=$(grep -oE '[0-9]{8}-[0-9]{2}:[0-9]{2}' "$INFO" | head -1)
    [ -z "$DATA" ] && DATA=$(date -u +%Y%m%d-%H:%M)
    echo "Panthera v1 - Official Snapshot amd64 LIVE Binary $DATA" > "$INFO"
  fi
  grep -q "^Panthera" "$INFO" || falha ".disk/info nao pegou"
  ok ".disk/info com a marca Panthera"
fi

echo "[boot-patch] OK: $N transformacoes aplicadas em $BIN"
