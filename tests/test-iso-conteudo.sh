#!/bin/bash
# tests/test-iso-conteudo.sh - o que a ISO realmente carrega dentro do chroot
# Uso: ./tests/test-iso-conteudo.sh [caminho/para/iso]
#
# Por que este teste existe: na v1.1-kits o build ficou VERDE e publicou uma ISO
# sem tema, sem policies e com pool offline incompleto. Os testes so olhavam o
# codigo do projeto, nunca o que foi realmente para dentro do chroot. Um build
# verde nao prova nada se a entrega silenciosamente falhou.
#
# Sem argumento: roda as checagens estaticas que nao dependem da ISO.
# Com argumento: extrai o filesystem.squashfs e confere o conteudo de verdade.
set -u
FAIL=0
ok() { echo "[OK] $1"; }
bad() { echo "[FALHA] $1"; FAIL=1; }

echo "== 1. estatico: os hooks reprovam quando falta fonte =="
# Se um hook so avisa quando o arquivo sumiu, ele repara de novo em silencio.
for h in 0200-branding 0300-firefox; do
  f="hooks/live/${h}.hook.chroot"
  n=$(grep -c "FALHA" "$f" 2>/dev/null || echo 0)
  [ "$n" -ge 3 ] && ok "$h tem $n bloqueios de FALHA" || bad "$h tem so $n: fonte faltando vira so aviso"
done

echo "== 2. estatico: as fontes NAO vao em includes.chroot/tmp =="
# includes.chroot/tmp nao chega no chroot (verificado na v1.1-kits).
if grep -vE "^[[:space:]]*#" build-iso.sh | grep -q "includes.chroot/tmp"; then
  bad "build-iso.sh ainda entrega fontes em includes.chroot/tmp (nao chega no chroot)"
  grep -n "includes.chroot/tmp" build-iso.sh | grep -v "#" | sed 's/^/   /'
else
  ok "fontes entregues em includes.chroot/usr/share"
fi
if grep -rn 'SRC="/tmp/panthera-src"' hooks/ 2>/dev/null; then
  bad "algum hook ainda le as fontes de /tmp"
else
  ok "nenhum hook le fontes de /tmp"
fi

echo "== 3. estatico: o pool baixa as dependencias, nao so os .deb nomeados =="
if grep -q "download-only" hooks/live/0250-pool.hook.chroot; then
  ok "0250-pool usa --download-only (traz as dependencias junto)"
else
  bad "0250-pool baixa so os .deb nomeados: a instalacao offline falha nas dependencias"
fi
if grep -q "FALHA: o pool NAO cobre" hooks/live/0250-pool.hook.chroot; then
  ok "pool incompleto reprova o build, e so avisa nao"
else
  bad "pool incompleto so avisa: a ISO pode prometer offline e nao entregar"
fi

echo "== 4. estatico: as mensagens de sucesso sao honestas =="
# O 0300 imprimia "OK policies" mesmo tendo pulado a copia inteira.
if grep -q 'FALHA: policies nao chegaram' hooks/live/0300-firefox.hook.chroot; then
  ok "0300 confere que as policies chegaram antes de dizer OK"
else
  bad "0300 diz OK sem conferir se copiou"
fi

ISO="${1:-}"
if [ -z "$ISO" ]; then
  echo ""
  echo "[AVISO] sem caminho de ISO: pulei as checagens de conteudo."
  echo "        Use: $0 ~/Downloads/panthera-iso/*.iso   apos baixar a ISO."
  [ "$FAIL" -ne 0 ] && { echo "CONTEUDO FALHOU (estatico)"; exit 1; }
  echo "CONTEUDO PASS (estatico). Falta conferir a ISO de verdade."
  exit 0
fi

echo ""
echo "== 5. conteudo real da ISO =="
[ -f "$ISO" ] || { bad "ISO nao encontrada: $ISO"; exit 1; }
command -v xorriso >/dev/null || { bad "xorriso ausente, nao da para inspecionar"; exit 1; }
command -v unsquashfs >/dev/null || { bad "unsquashfs ausente (instale squashfs-tools)"; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.squashfs "$T/fs.squashfs" >/dev/null 2>&1 \
  || { bad "nao consegui extrair o filesystem.squashfs"; exit 1; }
unsquashfs -ll "$T/fs.squashfs" > "$T/lista.txt" 2>/dev/null || { bad "nao consegui ler o squashfs"; exit 1; }
unsquashfs -f -d "$T/raiz" "$T/fs.squashfs" var/log/panthera-hooks.log >/dev/null 2>&1 || true
LOG="$T/raiz/var/log/panthera-hooks.log"

tem() { grep -q "$1" "$T/lista.txt"; }
logtem() { [ -f "$LOG" ] && grep -q "$1" "$LOG"; }

tem "usr/share/panthera-store/catalogo.json" \
  && ok "catalogo dentro da ISO" || bad "catalogo NAO chegou na ISO"
tem "usr/lib/panthera/catalogo.py" \
  && ok "modulo do catalogo dentro da ISO" || bad "modulo NAO chegou na ISO"
tem "usr/bin/panthera-catalogo\|usr/lib/panthera/catalogo.py" || true

tem "usr/share/themes/Panthera/index.theme" \
  && ok "index.theme do tema (sem ele o GTK ignora o tema)" \
  || bad "index.theme AUSENTE: o GTK3 vai ignorar o tema"
tem "usr/share/themes/Panthera/gtk-3.0/gtk.css" \
  && ok "gtk.css dentro de gtk-3.0/" \
  || bad "gtk.css AUSENTE: era o bug que fez a ISO sair com o tema do Debian"
tem "usr/share/panthera-firefox/policies.json" \
  && ok "policies do Firefox entregues" \
  || bad "policies.json AUSENTE: Firefox sem protecao"
tem "usr/share/panthera-firefox/distribution.ini" \
  && ok "distribution.ini entregue" || bad "distribution.ini ausente"
tem "etc/apt/apt.hooks.d/90panthera-firefox" \
  && ok "hook do apt que entrega as policies" \
  || bad "hook do apt ausente: Firefox instalado na mao ficaria sem policies"
tem "var/cache/panthera-pool/firefox-esr_" \
  && ok "pool offline com o Firefox dentro da ISO" \
  || bad "pool offline sem Firefox: quem nao tem internet fica sem navegador"
tem "etc/skel/.config/gtk-3.0/settings.ini" \
  && ok "tema aplicado no skel (usuario instalado)" || bad "skel sem tema"
tem "etc/skel/.config/xfce4/xfconf/xfce-perchannel-desktop/xfce4-desktop.xml" \
  && ok "papel de parede aplicado no skel" || bad "skel sem papel de parede"
# O usuario do Live NAO existe no squashfs (/home vem vazio): o live-boot cria
# ele no primeiro boot com "useradd -m", e o useradd copia o /etc/skel. Por isso
# que o caminho certo do branding e o skel, e nao /home/user.
tem "home/user/" && bad "/home/user existe no squashfs: o usuario do Live passou a ser criado no build" \
  || ok "usuario do Live e criado no boot (skel e quem aplica o branding)"

echo ""
echo "== 6. bootloaders UEFI e Legacy (RF008) =="
# EFI/ e isolinux/ vivem no filesystem da ISO, nao dentro do squashfs. Conferir
# pelo listing do squashfs daria falso negativo.
ISO_ARQ=$(xorriso -indev "$ISO" -find / -maxdepth 3 2>/dev/null)
echo "$ISO_ARQ" | grep -q "grubx64.efi" && ok "UEFI presente" || bad "sem bootloader UEFI"
echo "$ISO_ARQ" | grep -q "isolinux.bin" && ok "Legacy presente" || bad "sem bootloader Legacy"

echo ""
echo "== 7. o log dos hooks nao tem aviso de fonte faltando =="
if [ -f "$LOG" ]; then
  logtem "AVISO: gtk.css ausente" && bad "log: gtk.css ausente" || ok "log sem aviso de gtk.css ausente"
  logtem "AVISO: index.theme ausente" && bad "log: index.theme ausente" || ok "log sem aviso de index.theme ausente"
  logtem "FALHA" && { bad "log tem FALHA:"; grep "FALHA" "$LOG" | sed 's/^/   /'; } || ok "log sem FALHA"
else
  bad "sem /var/log/panthera-hooks.log na ISO para auditar"
fi

echo ""
if [ "$FAIL" -ne 0 ]; then echo "CONTEUDO FALHOU"; exit 1; fi
echo "CONTEUDO PASS: a ISO carrega o que o catalogo promete."
