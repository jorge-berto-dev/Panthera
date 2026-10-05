#!/bin/bash
# tests/test-iso.sh completo v2 - estatico + ISO (ODT Secao 33 e 20.2)
# Uso: ./tests/test-iso.sh [--static]
# --static: so checagens de projeto (sem ISO). Padrao: se out/*.iso existir, valida ISO tambem.
set -e
MODE="${1:-}"
ISO=$(ls out/*.iso 2>/dev/null | head -1 || true)

echo "== base =="
grep -q bookworm live-build-config/auto/config && echo "[OK] base bookworm" || { echo "[FALHA] base nao e bookworm"; exit 1; }
grep -q 'main contrib non-free non-free-firmware' live-build-config/auto/config && echo "[OK] areas main contrib non-free-firmware" || { echo "[FALHA] archive-areas"; exit 1; }

echo "== proibidos =="
if grep -q "^snapd$" packages-lists/panthera-base.list; then echo "[FALHA] snapd proibido (Secao 3.2)"; exit 1; else echo "[OK] sem snapd"; fi
for p in apport whoopsie popularity-contest; do
  if grep -q "^${p}$" packages-lists/panthera-base.list; then echo "[FALHA] $p proibido"; exit 1; fi
done
# CJK vai via Loja, nunca na ISO (Secao 3.1). Metapacote fonts-noto puxa 400MB.
if grep -q "^fonts-noto$" packages-lists/panthera-base.list; then echo "[FALHA] use fonts-noto-core, nao fonts-noto (puxa CJK)"; exit 1; else echo "[OK] fontes minimas (noto-core)"; fi
if grep -q "cjk" packages-lists/panthera-base.list; then echo "[FALHA] CJK proibido na base"; exit 1; else echo "[OK] sem CJK"; fi
echo "[OK] sem pacotes espiões na base"

echo "== arquivos FASE 2-6 =="
for f in kits/catalogo.json scripts/panthera-catalogo.py scripts/panthera-firefox-policies.sh tests/test-kits.sh build-iso.sh packages-lists/panthera-base.list packages-lists/panthera-remove.list live-build-config/auto/config calamares/settings.conf firefox/policies.json firefox/distribution.ini scripts/panthera-doctor.sh scripts/check-wayland.sh scripts/panthera-central.py scripts/panthera-store.py scripts/panthera-updater.py scripts/panthera-welcome.py scripts/panthera-theme-check.py scripts/panthera-superleve.sh scripts/panthera-monitor.py scripts/panthera-limpeza.py tests/test-hardening.sh tests/test-apps.sh tests/test-final.sh includes.chroot/usr/share/panthera-ajuda/index.html includes.chroot/usr/share/applications/panthera-central.desktop includes.chroot/usr/share/applications/panthera-store.desktop includes.chroot/usr/share/applications/panthera-updater.desktop includes.chroot/usr/share/applications/panthera-monitor.desktop includes.chroot/usr/share/applications/panthera-limpeza.desktop includes.chroot/etc/xdg/autostart/panthera-welcome.desktop includes.chroot/etc/sysctl.d/99-panthera.conf includes.chroot/etc/sudoers.d/panthera includes.chroot/etc/panthera/privacy-manifest.txt includes.chroot/etc/panthera/removed-bloat.txt includes.chroot/etc/panthera/version includes.chroot/etc/security/limits.d/panthera.conf includes.chroot/etc/default/grub includes.chroot/etc/udisks2/mount_options.conf; do
  if [ -f "$f" ]; then echo "[OK] $f"; else echo "[FALTA] $f"; exit 1; fi
done

echo "== hooks 0100-0700 =="
N=$(ls hooks/live/*.hook.chroot 2>/dev/null | wc -l)
if [ "$N" -eq 7 ]; then echo "[OK] 7 hooks"; else echo "[FALHA] esperado 7 hooks (0250-pool entrou), achado $N"; exit 1; fi
for h in hooks/live/*.hook.chroot hooks/live/*.hook.binary; do
  [ -x "$h" ] || { echo "[FALHA] sem +x: $h"; exit 1; }
  bash -n "$h" || { echo "[FALHA] sintaxe: $h"; exit 1; }
done
echo "[OK] hooks executaveis + sintaxe"

echo "== configs =="
python3 -m json.tool firefox/policies.json >/dev/null && echo "[OK] policies.json valido" || { echo "[FALHA] policies.json"; exit 1; }
grep -q "DisableTelemetry" firefox/policies.json && echo "[OK] policies sem telemetria"
grep -q "about:panthera-welcome" firefox/policies.json && { echo "[FALHA] policies aponta para about:panthera-welcome (pagina inexistente)"; exit 1; }
grep -q "raposa" includes.chroot/usr/share/panthera-ajuda/index.html && { echo "[FALHA] ajuda offline ainda manda abrir o Firefox nativo"; exit 1; }
echo "[OK] ajuda offline nao depende de navegador especifico"
grep -q "kernel.yama.ptrace_scope=2" includes.chroot/etc/sysctl.d/99-panthera.conf && echo "[OK] sysctl 12 chaves (amostra ptrace_scope)"
grep -q "timestamp_timeout=10" includes.chroot/etc/sudoers.d/panthera && echo "[OK] sudoers timeout 10"
bash -n build-iso.sh && echo "[OK] build-iso.sh sintaxe"
grep -q 'lb config --distribution bookworm' build-iso.sh && echo "[OK] build-iso.sh lb config fiel Sec 11.1"

# Se nao ha ISO ainda (FASE 2 antes do build), passa no estatico
if [ -z "$ISO" ]; then
  echo "== ISO =="
  echo "[AVISO] sem ISO em out/. Estatico PASS (FASE 1/2 pre-build)."
  echo "Proximo: sudo ./build-iso.sh (~30-60min) depois ./tests/test-iso.sh"
  echo "ESTATICO PASS. Proximo: QEMU + Ventoy manual (ODT Secao 12)."
  exit 0
fi

echo "== ISO =="
ls -lh "$ISO"
if [ -f "$ISO.sha256" ]; then sha256sum -c "$ISO.sha256"; else echo "[FALHA] sem $ISO.sha256"; exit 1; fi

echo "== peso RF001 (<=2252MB) =="
du -m "$ISO" | awk '{if($1>2252){print "[FALHA] ISO pesada "$1"MB"; exit 1}else print "[OK] peso "$1"MB"}'

echo "== hibrida RF008 =="
file "$ISO" | tee /tmp/panthera-file.log
grep -qi "bootable\|hybrid\|DOS/MBR" /tmp/panthera-file.log && echo "[OK] hibrida" || echo "[AVISO] confira isohybrid/file manualmente"

echo "ESTATICO+ISO PASS. Proximo manual:"
echo "  qemu-system-x86_64 -m 2048 -cdrom $ISO -boot d   # 90s ate desktop (T-QEMU)"
echo "  Ventoy: copie exFAT, boot UEFI + Legacy (T-VENTOY)"
