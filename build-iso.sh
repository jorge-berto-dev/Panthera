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
  for h in 0100-locale 0200-branding 0300-firefox 0400-hardening 0500-calamares 0600-cleanup; do
    [ -x "hooks/live/${h}.hook.chroot" ] && echo "[OK] hook $h executavel" || { echo "[FALTA] hook $h"; FAIL=1; }
    bash -n "hooks/live/${h}.hook.chroot" && echo "[OK] sintaxe $h" || { echo "[FALHA] sintaxe $h"; FAIL=1; }
  done
  bash -n build-iso.sh && echo "[OK] sintaxe build-iso.sh"
  python3 -m json.tool firefox/policies.json >/dev/null && echo "[OK] policies.json valido" || { echo "[FALHA] policies.json"; FAIL=1; }
  [ -f firefox/distribution.ini ] && echo "[OK] distribution.ini"
  [ -f calamares/settings.conf ] && echo "[OK] calamares settings"
  [ -f includes.chroot/etc/sysctl.d/99-panthera.conf ] && echo "[OK] sysctl"
  [ -f includes.chroot/etc/sudoers.d/panthera ] && echo "[OK] sudoers"
  [ -f includes.chroot/etc/panthera/privacy-manifest.txt ] && echo "[OK] privacy-manifest"
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
apt update && apt install -y live-build cdebootstrap debootstrap xorriso isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin mtools dosfstools squashfs-tools
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
# FASE 2: entrega includes (sysctl, sudoers, manifest, skel)
cp -a includes.chroot/. config/includes.chroot/
# FASE 2: disponibiliza fontes dos hooks dentro do chroot em /tmp/panthera-src
# (hook .chroot roda DENTRO do chroot e nao enxerga a pasta do projeto no host)
mkdir -p config/includes.chroot/tmp/panthera-src
cp -a branding config/includes.chroot/tmp/panthera-src/ 2>/dev/null || true
cp -a calamares config/includes.chroot/tmp/panthera-src/ 2>/dev/null || true
cp -a firefox config/includes.chroot/tmp/panthera-src/ 2>/dev/null || true
cp -a scripts/check-wayland.sh config/includes.chroot/tmp/panthera-src/ 2>/dev/null || true
cp -a scripts/panthera-doctor.sh config/includes.chroot/tmp/panthera-src/ 2>/dev/null || true
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
chmod +x config/includes.chroot/usr/bin/panthera-*
# Log do build (cauda de 50 linhas pedida na Secao 20.2)
{
echo "[Panthera] build iniciado $(date -u +%Y-%m-%dT%H:%M:%SZ) base=bookworm"
lb build
} 2>&1 | tee "$LOG"
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
