#!/bin/bash
# scripts/panthera-grub-patch.sh <dir-binary> <dir-branding>
# Aplica tema + autoboot + marca Panthera no grub.cfg EFI JA GERADO.
#
# Por que existe separado do hook 0700: o grub.cfg real do live-build e escrito
# DEPOIS que os hooks binarios rodam. Na v1.2.1 o hook nao achou o arquivo,
# criou um stub com so "set timeout=5", e a geracao real sobrescreveu depois:
# a ISO saiu com o menu Debian e ninguem avisou. Entao o 0700 cuida do syslinux
# (que existe cedo) e este script roda no build-iso.sh DEPOIS do "lb build",
# seguido de "lb binary_iso" para reconstruir a ISO a partir do binary/ ja
# corrigido.
#
# Idempotente: rodar duas vezes nao duplica nada. Reprova se o grub.cfg nao
# existir, porque ai nao ha o que corrigir e seria outra surpresa silenciosa.
set -e
BIN="${1:?uso: $0 <dir-binary> <dir-branding>}"
SRC="${2:?uso: $0 <dir-binary> <dir-branding>}"
GRUBCFG="$BIN/boot/grub/grub.cfg"

[ -f "$GRUBCFG" ] || { echo "[grub-patch] FALHA: sem $GRUBCFG para corrigir" >&2; exit 1; }
cp "$GRUBCFG" "$GRUBCFG.panthera-bak"

# tema Panthera (fundo pantera 1024x768, selecao #1D83FF)
mkdir -p "$BIN/boot/grub/themes/panthera"
[ -f "$SRC/grub/theme.txt" ] || { echo "[grub-patch] FALHA: sem theme.txt em $SRC" >&2; exit 1; }
[ -f "$SRC/boot/grub-background.png" ] || { echo "[grub-patch] FALHA: sem background.png em $SRC" >&2; exit 1; }
cp "$SRC/grub/theme.txt" "$BIN/boot/grub/themes/panthera/theme.txt"
cp "$SRC/boot/grub-background.png" "$BIN/boot/grub/themes/panthera/background.png"
# fonte unicode para o tema (o tema cai sem ela); procura no host e no chroot
for PF2 in /usr/share/grub/unicode.pf2 /usr/lib/grub/i386-pc/unicode.pf2; do
  if [ -f "$PF2" ]; then
    mkdir -p "$BIN/boot/grub/fonts"
    cp "$PF2" "$BIN/boot/grub/fonts/unicode.pf2" 2>/dev/null || true
    break
  fi
done

# timeout: mostra o menu 5s e inicia sozinho, que nem o Mint
if grep -q "^set timeout=" "$GRUBCFG"; then
  sed -i -E 's/^set timeout=.*/set timeout=5/' "$GRUBCFG"
else
  printf '\nset timeout=5\n' >> "$GRUBCFG"
fi
if grep -q "^set default=" "$GRUBCFG"; then
  sed -i -E 's/^set default=.*/set default=0/' "$GRUBCFG"
fi

# carrega o tema uma vez, depois da linha do terminal grafico
if ! grep -q "themes/panthera/theme.txt" "$GRUBCFG"; then
  awk '
    !feito && /terminal_output gfxterm/ { print; print "insmod png"; print "insmod jpeg"; print "loadfont ($root)/boot/grub/fonts/unicode.pf2"; print "set theme=($root)/boot/grub/themes/panthera/theme.txt"; print "background_image ($root)/boot/grub/themes/panthera/background.png"; feito=1; next }
    { print }
  ' "$GRUBCFG" > "$GRUBCFG.new" && mv "$GRUBCFG.new" "$GRUBCFG"
fi

# marca nos titulos ('simples' e "duplas"; nunca nos parametros do kernel)
sed -i -E "s/'Debian GNU\/Linux([^']*)'/'Panthera\1'/" "$GRUBCFG"
sed -i -E 's/"Debian GNU\/Linux([^"]*)"/"Panthera\1"/' "$GRUBCFG"

N=$(grep -c "Panthera" "$GRUBCFG" || true)
[ "$N" -ge 1 ] || { echo "[grub-patch] FALHA: nenhuma marca Panthera apos o patch" >&2; exit 1; }
grep -q "^set timeout=5" "$GRUBCFG" || { echo "[grub-patch] FALHA: sem autoboot" >&2; exit 1; }
echo "[grub-patch] OK: tema + autoboot 5s + $N marcas Panthera em $GRUBCFG"
