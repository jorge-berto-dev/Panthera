#!/bin/bash
# Panthera v1 build-iso.sh - gera ISO híbrida Ventoy (FASE 2)
# Autoridade: Panthera_OS_Prompt_Mestre.odt Secao 11.1 + 15.2 + 20.2
# Uso: sudo ./build-iso.sh [--clean] | ./build-iso.sh --check | ./build-iso.sh --help
# Base fixa Secao 3.1: Debian 12 bookworm amd64 + live-build. Nao trocar.
set -e
VERSION="v1.0-uso-geral"
OUT="out/panthera-${VERSION}-amd64-hybrid.iso"
LOG="out/build.log"

# Ajuda PT-BR simples
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  echo "Uso:"
  echo "  sudo ./build-iso.sh          # build completo (Debian 12, 20GB livre)"
  echo "  sudo ./build-iso.sh --clean  # limpa config/ binary/ cache/ e rebuilda"
  echo "  ./build-iso.sh --check       # validacao estatica sem root (FASE 2)"
  exit 0
fi

# Modo check: valida sem root e sem rede (para host nao-Debian / CI)
if [ "$1" = "--check" ]; then
  echo "[Panthera FASE2 --check] validacao estatica..."
  FAIL=0
  [ -f packages-lists/panthera-base.list ] && echo "[OK] panthera-base.list" || { echo "[FALTA] panthera-base.list"; FAIL=1; }
  # PROIBIDO: snapd na ISO (Secao 3.2)
  if grep -q "^snapd$" packages-lists/panthera-base.list; then echo "[FALHA] snapd proibido na base"; FAIL=1; else echo "[OK] sem snapd"; fi
  grep -q bookworm live-build-config/auto/config && echo "[OK] base bookworm" || { echo "[FALHA] base nao e bookworm"; FAIL=1; }
  for h in 0100-locale 0200-branding 0250-pool 0300-firefox 0400-hardening 0500-calamares 0600-cleanup; do
    [ -x "hooks/live/${h}.hook.chroot" ] && echo "[OK] hook $h executavel" || { echo "[FALTA] hook $h"; FAIL=1; }
    bash -n "hooks/live/${h}.hook.chroot" && echo "[OK] sintaxe $h" || { echo "[FALHA] sintaxe $h"; FAIL=1; }
  done
  [ -x "hooks/live/0700-bootmenu.hook.binary" ] && echo "[OK] hook 0700-bootmenu binario executavel" || { echo "[FALTA] hook 0700-bootmenu"; FAIL=1; }
  bash -n "hooks/live/0700-bootmenu.hook.binary" && echo "[OK] sintaxe 0700-bootmenu" || { echo "[FALHA] sintaxe 0700-bootmenu"; FAIL=1; }
  bash -n "scripts/panthera-grub-patch.sh" && echo "[OK] sintaxe panthera-grub-patch" || { echo "[FALHA] sintaxe panthera-grub-patch"; FAIL=1; }
  grep -q "lb binary_iso" build-iso.sh && echo "[OK] ISO reconstruida apos o patch do GRUB" || { echo "[FALHA] sem lb binary_iso: o patch do GRUB nao entraria na ISO"; FAIL=1; }
  grep -q "panthera-grub-patch.sh binary branding" build-iso.sh && echo "[OK] patch do GRUB apos o lb build" || { echo "[FALHA] patch do GRUB fora de ordem"; FAIL=1; }
  bash -n build-iso.sh && echo "[OK] sintaxe build-iso.sh"
  python3 -m json.tool firefox/policies.json >/dev/null && echo "[OK] policies.json valido" || { echo "[FALHA] policies.json"; FAIL=1; }
  [ -f firefox/distribution.ini ] && echo "[OK] distribution.ini"
  [ -f calamares/settings.conf ] && echo "[OK] calamares settings"
  [ -f includes.chroot/etc/sysctl.d/99-panthera.conf ] && echo "[OK] sysctl"
  [ -f includes.chroot/etc/sudoers.d/panthera ] && echo "[OK] sudoers"
  [ -f includes.chroot/etc/panthera/privacy-manifest.txt ] && echo "[OK] privacy-manifest"
  # Catalogo Panthera (nova FASE 8): kits, apps, recusados e pool offline
  python3 -m json.tool kits/catalogo.json >/dev/null && echo "[OK] kits/catalogo.json valido" || { echo "[FALHA] kits/catalogo.json"; FAIL=1; }
  python3 -m py_compile scripts/panthera-catalogo.py && echo "[OK] compile panthera-catalogo" || { echo "[FALHA] compile panthera-catalogo"; FAIL=1; }
  [ -x tests/test-kits.sh ] && echo "[OK] test-kits.sh executavel" || { echo "[FALTA] test-kits.sh"; FAIL=1; }
  bash -n scripts/panthera-firefox-policies.sh && echo "[OK] sintaxe panthera-firefox-policies" || { echo "[FALHA] sintaxe panthera-firefox-policies"; FAIL=1; }
  # Firefox saiu da base nativa: se voltar, a ISO infla e a promessa do pool quebra
  if grep -qx "firefox-esr" packages-lists/panthera-base.list; then echo "[FALHA] firefox-esr voltou para a base nativa"; FAIL=1; else echo "[OK] Firefox fora da base (vem por Kit + pool)"; fi
  # FASE 6: apps compilam (Secao 26.1 COMPILE-OK)
  for app in panthera-central panthera-store panthera-updater panthera-welcome panthera-theme-check; do
    python3 -m py_compile "scripts/${app}.py" && echo "[OK] compile $app" || { echo "[FALHA] compile $app"; FAIL=1; }
  done
  for shf in scripts/panthera-doctor.sh scripts/panthera-codecs.sh scripts/panthera-superleve.sh scripts/check-wayland.sh; do
    bash -n "$shf" && echo "[OK] sintaxe $shf" || { echo "[FALHA] sintaxe $shf"; FAIL=1; }
  done
  if [ "$FAIL" -ne 0 ]; then echo "[FASE2 --check] FALHOU"; exit 1; fi
  echo "[FASE2 --check] PASS. Para ISO real rode em Debian 12: sudo ./build-iso.sh"
  exit 0
fi

# Build real exige root
if [ "$EUID" -ne 0 ]; then echo "Rode com sudo (ou use ./build-iso.sh --check para validar sem root)"; exit 1; fi
if [ "$1" = "--clean" ]; then lb clean --purge 2>/dev/null || true; rm -rf config binary .build cache; fi
apt update && apt install -y live-build cdebootstrap debootstrap xorriso isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin mtools dosfstools squashfs-tools python3 file
# Limpeza total: sem ela, resto de build falho quebra o debootstrap
# ("Tried to extract package, but file already exists" = chroot/ sujo)
lb clean --purge 2>/dev/null || true
rm -rf config binary .build cache chroot bootstrap
# Remove artefatos de build anterior (ISO reprovada nao serve e come GBs)
rm -f out/*.iso out/*.iso.sha256 2>/dev/null || true
# Espaco: build pede ~10GB livres além do sistema (medido em build real)
AVAIL_MB=$(df -m . | tail -1 | awk '{print $4}')
if [ "$AVAIL_MB" -lt 12000 ]; then echo "FALHA: so ${AVAIL_MB}MB livres, precisa 12000MB. Rode apt clean na VM ou aumente o disco."; exit 4; fi
mkdir -p out config/package-lists config/hooks/live config/includes.chroot
# Linha lb config (ODT Secao 11.1). Correcoes 2026-09-29:
#  - --bootloaders "syslinux grub-efi": syslinux da boot Legacy/BIOS, grub-efi da boot UEFI.
#    Antes era "grub-efi" so, ou seja a ISO nao bootava em PC com BIOS (violava RF008).
#  - --debian-installer REMOVIDO: o instalador oficial do Debian competia com o Calamares
#    (branding Panthera, 6 telas, botao INSTALAR) e adds centenas de MB. Calamares e o
#    unico instalador (Secao 11 / hook 0500-calamares).
lb config --distribution bookworm --archive-areas "main contrib non-free non-free-firmware" --bootloaders "syslinux grub-efi" --binary-images iso-hybrid --iso-application "Panthera OS v1" --iso-volume "PANTHERA_V1" --bootappend-live "boot=live components quiet splash loglevel=2 locales=pt_BR.UTF-8 keyboard-layouts=br timezone=America/Sao_Paulo" --mirror-bootstrap http://deb.debian.org/debian --mirror-chroot http://deb.debian.org/debian --mirror-binary http://deb.debian.org/debian
cp packages-lists/panthera-base.list config/package-lists/panthera.list.chroot
# FASE 2: entrega hooks 0100-0600 para o live-build (idempotente)
cp hooks/live/*.hook.chroot config/hooks/live/
chmod +x config/hooks/live/*.hook.chroot
# Hook binario 0700-bootmenu: tema GRUB + autoboot 5s. Roda no host depois do
# estagio binary; sem ele o menu e o do Debian parado esperando ENTER.
cp hooks/live/*.hook.binary config/hooks/live/ 2>/dev/null || true
chmod +x config/hooks/live/*.hook.binary 2>/dev/null || true
# FASE 2: entrega includes (sysctl, sudoers, manifest, skel)
cp -a includes.chroot/. config/includes.chroot/
# FASE 2: disponibiliza fontes dos hooks dentro do chroot em /usr/share/panthera-src
# (hook .chroot roda DENTRO do chroot e nao enxerga a pasta do projeto no host)
#
# ATENCAO: NAO use config/includes.chroot/tmp/ aqui. Verificado na ISO v1.1-kits:
# o live-build NAO entrega includes.chroot/tmp no chroot. As fontes chegavam
# vazias, o hook 0200 nao achava o gtk.css e a ISO saia com o tema do Debian 12
# sem nenhum aviso que parasse o build. Tudo sob /usr/share chega, como o
# catalogo e o modulo em /usr/lib provaram.
mkdir -p config/includes.chroot/usr/share/panthera-src
cp -a branding config/includes.chroot/usr/share/panthera-src/ 2>/dev/null || true
cp -a calamares config/includes.chroot/usr/share/panthera-src/ 2>/dev/null || true
cp -a firefox config/includes.chroot/usr/share/panthera-src/ 2>/dev/null || true
cp -a scripts/check-wayland.sh config/includes.chroot/usr/share/panthera-src/ 2>/dev/null || true
cp -a scripts/panthera-doctor.sh config/includes.chroot/usr/share/panthera-src/ 2>/dev/null || true
cp -a scripts/panthera-pool-check.sh config/includes.chroot/usr/share/panthera-src/ 2>/dev/null || true
chmod +x config/includes.chroot/usr/share/panthera-src/panthera-pool-check.sh 2>/dev/null || true
# FASE 6: apps em /usr/bin com nomes do ODT (fonte unica: scripts/)
mkdir -p config/includes.chroot/usr/bin
cp scripts/panthera-central.py config/includes.chroot/usr/bin/panthera-central
cp scripts/panthera-store.py config/includes.chroot/usr/bin/panthera-store
cp scripts/panthera-updater.py config/includes.chroot/usr/bin/panthera-updater
cp scripts/panthera-welcome.py config/includes.chroot/usr/bin/panthera-welcome.py
cp scripts/panthera-theme-check.py config/includes.chroot/usr/bin/panthera-theme-check.py
cp scripts/panthera-doctor.sh config/includes.chroot/usr/bin/panthera-doctor
cp scripts/panthera-codecs.sh config/includes.chroot/usr/bin/panthera-codecs.sh
cp scripts/panthera-superleve.sh config/includes.chroot/usr/bin/panthera-superleve
cp scripts/check-wayland.sh config/includes.chroot/usr/bin/panthera-check-wayland
cp scripts/panthera-firefox-policies.sh config/includes.chroot/usr/bin/panthera-firefox-policies
cp scripts/panthera-monitor.py config/includes.chroot/usr/bin/panthera-monitor
cp scripts/panthera-limpeza.py config/includes.chroot/usr/bin/panthera-limpeza
cp scripts/panthera-aparencia.py config/includes.chroot/usr/bin/panthera-aparencia
cp scripts/panthera-backup.py config/includes.chroot/usr/bin/panthera-backup
cp scripts/panthera-drivers.py config/includes.chroot/usr/bin/panthera-drivers
chmod +x config/includes.chroot/usr/bin/panthera-*
# Catalogo Panthera: fonte unica da Loja, do Bem-vindo e do pool offline.
# Novo Kit = editar kits/catalogo.json, sem rebuild e sem tocar em Python.
mkdir -p config/includes.chroot/usr/share/panthera-store config/includes.chroot/usr/lib/panthera
cp kits/catalogo.json config/includes.chroot/usr/share/panthera-store/catalogo.json
cp scripts/panthera-catalogo.py config/includes.chroot/usr/lib/panthera/catalogo.py
chmod 644 config/includes.chroot/usr/share/panthera-store/catalogo.json
chmod 755 config/includes.chroot/usr/lib/panthera/catalogo.py
# Log do build (cauda de 50 linhas pedida na Secao 20.2)
{
echo "[Panthera] build iniciado $(date -u +%Y-%m-%dT%H:%M:%SZ) base=bookworm"
lb build
} 2>&1 | tee "$LOG"
# Patch do GRUB EFI + reconstrucao da ISO. O grub.cfg real so existe DEPOIS do
# lb build (os hooks binarios rodam antes da geracao dele). Sem isto, a ISO sai
# com o menu Debian parado esperando ENTER, como a v1.1.8. O syslinux ja foi
# corrigido pelo hook 0700; aqui vai o GRUB, e o lb binary_iso reconstrói a ISO
# a partir do binary/ ja corrigido.
# SEM "| tee" direto no lb: o status do pipeline e o do tee, e falha do lb
# seria engolida (foi assim que a v1.2.5 publicou a ISO sem o patch do GRUB).
# Usa PIPESTATUS e ainda confere pelo relogio que a ISO saiu do rebuild.
if [ -f scripts/panthera-grub-patch.sh ] && [ -f binary/boot/grub/grub.cfg ]; then
  bash scripts/panthera-grub-patch.sh binary branding 2>&1 | tee -a "$LOG"
  # O status do pipeline e o do tee: sem PIPESTATUS, falha do patch seria
  # engolida e a ISO sairia sem timeout (foi o que matou a v1.3.0 em silencio).
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "[Panthera] FALHA: patch do GRUB reprovou" | tee -a "$LOG"; exit 3; }
  echo "[Panthera] reconstruindo a ISO com o boot corrigido (lb binary_iso)" | tee -a "$LOG"
  # O live-build carimba estagios concluidos em .build/ e pula re-execucao com
  # "W: Skipping binary_iso, already done". Sem remover o carimbo, o rebuild
  # nunca acontece e a guarda de mtime reprova com razao (foi o que a v1.2.8
  # mostrou). Remove o carimbo para forcar.
  ls .build/ 2>/dev/null | tee -a "$LOG" || true
  rm -f .build/binary_iso
  MARCO=$(date +%s)
  lb binary_iso 2>&1 | tee -a "$LOG"
  RC=${PIPESTATUS[0]}
  [ "$RC" -eq 0 ] || { echo "[Panthera] FALHA: lb binary_iso saiu com codigo $RC" | tee -a "$LOG"; exit 3; }
  NOVA=""
  for C in live-image-amd64.hybrid.iso binary.hybrid.iso; do
    [ -f "$C" ] || continue
    if [ "$(stat -c %Y "$C")" -ge "$MARCO" ]; then NOVA="$C"; break; fi
  done
  [ -n "$NOVA" ] || { echo "[Panthera] FALHA: nenhuma ISO nova apos o lb binary_iso (sairia a ISO velha sem o patch)" | tee -a "$LOG"; ls -l --time-style=full-iso *.iso 2>/dev/null | tee -a "$LOG"; exit 3; }
  echo "[Panthera] ISO reconstruida: $NOVA" | tee -a "$LOG"
  # O ISO_GEN abaixo escolhe por ordem alfabetica e poderia pegar a ISO velha.
  # So pode sobrar a recem-reconstruida.
  for C in live-image-amd64.hybrid.iso binary.hybrid.iso; do
    if [ "$C" != "$NOVA" ] && [ -f "$C" ]; then
      echo "[Panthera] descartando ISO anterior ao rebuild: $C" | tee -a "$LOG"
      rm -f "$C"
    fi
  done
else
  echo "[Panthera] FALHA: sem binary/boot/grub/grub.cfg para corrigir apos o lb build" | tee -a "$LOG"
  exit 3
fi
# Localiza ISO gerada (nome varia por versao do live-build)
# Localiza ISO gerada (nome varia por versao do live-build)
ISO_GEN=$(ls live-image-amd64.hybrid.iso binary.hybrid.iso 2>/dev/null | head -1)
if [ -z "$ISO_GEN" ]; then echo "FALHA: lb build nao gerou ISO. Veja $LOG"; exit 3; fi
mv "$ISO_GEN" "$OUT"
# Garante hibrida Ventoy UEFI+Legacy (RF008)
if command -v isohybrid >/dev/null 2>&1; then isohybrid "$OUT" || true; fi
sha256sum "$OUT" | tee "$OUT.sha256"
SIZE_MB=$(du -m "$OUT" | cut -f1)
if [ "$SIZE_MB" -gt 2252 ]; then echo "FALHA: ISO pesada ${SIZE_MB}MB > 2252MB. Corte pacotes!"; exit 2; fi
echo "OK $OUT. Teste: qemu-system-x86_64 -m 2048 -cdrom $OUT -boot d"
echo "Ventoy: copie para pendrive exFAT e boot UEFI e Legacy."
