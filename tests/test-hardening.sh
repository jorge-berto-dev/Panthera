#!/bin/bash
# tests/test-hardening.sh - 10 provas FASE 5 (ODT Secao 9 + 20.5 + Apendice H)
# Uso: ./tests/test-hardening.sh
# Estatico (sem root): valida projeto. Gera out/provas.txt com resultados +
# comandos Live (Apendice H) para colar no Debian apos o build.
set -e
PROVAS="out/provas.txt"
mkdir -p out
FAIL=0
{
echo "Panthera v1 - 10 provas de seguranca (FASE 5) - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Projeto: $(pwd)"
echo ""
} > "$PROVAS"

prova() { # prova <n> <titulo> <comando...>
  N="$1"; TIT="$2"; shift 2
  echo "== prova $N: $TIT =="
  echo "--- prova $N: $TIT ---" >> "$PROVAS"
  if "$@" >> "$PROVAS" 2>&1; then
    echo "[OK] prova $N: $TIT"
    echo "RESULTADO: PASS" >> "$PROVAS"
  else
    echo "[FALHA] prova $N: $TIT"
    echo "RESULTADO: FAIL" >> "$PROVAS"
    FAIL=1
  fi
  echo "" >> "$PROVAS"
}

# 1. UFW deny-in (Secao 9): ordem canonica no hook + comandos exatos
prova 1 "ufw deny incoming / allow outgoing" bash -c '
  grep -q "ufw default deny incoming" hooks/live/0400-hardening.hook.chroot &&
  grep -q "ufw default allow outgoing" hooks/live/0400-hardening.hook.chroot &&
  grep -q "ufw allow out 53,80,443/tcp" hooks/live/0400-hardening.hook.chroot &&
  grep -q "ufw allow out 53/udp" hooks/live/0400-hardening.hook.chroot &&
  grep -q "ufw --force enable" hooks/live/0400-hardening.hook.chroot &&
  echo "hook 0400: defaults -> allows -> enable OK"'

# 2. AppArmor enforce (Secao 9): cmdline grub + enable + pacote base
prova 2 "apparmor enforce (cmdline + servico)" bash -c '
  grep -q "apparmor=1 security=apparmor" includes.chroot/etc/default/grub &&
  grep -q "systemctl enable.*apparmor" hooks/live/0400-hardening.hook.chroot &&
  grep -q "^apparmor$" packages-lists/panthera-base.list &&
  grep -q "^apparmor-profiles$" packages-lists/panthera-base.list &&
  echo "grub cmdline + enable + pacotes OK"'

# 3. dpkg limpo (Secao 9 + RNF002): nada de snap/apport/whoopsie na base
prova 3 "dpkg sem snapd/apport/whoopsie/popularity" bash -c '
  ! grep -q "^snapd$" packages-lists/panthera-base.list &&
  ! grep -q "^apport$" packages-lists/panthera-base.list &&
  ! grep -q "^whoopsie$" packages-lists/panthera-base.list &&
  ! grep -q "^popularity-contest$" packages-lists/panthera-base.list &&
  grep -q "^snapd$" packages-lists/panthera-remove.list &&
  echo "base limpa + remove.list purga OK"'

# 4. ss essencial (Secao 9): so servicos essenciais em enable (Secao 3.3)
prova 4 "servicos enable so essenciais (sem snap/tracker)" bash -c '
  grep "systemctl enable" hooks/live/0400-hardening.hook.chroot | grep -q "ufw apparmor unattended-upgrades cups NetworkManager systemd-timesyncd" &&
  ! grep "systemctl enable" hooks/live/0400-hardening.hook.chroot | grep -q -E "snapd|tracker|apport" &&
  echo "enable: ufw apparmor upgrades cups NM timesyncd OK"'

# 5. policies Firefox (Secao 8): JSON valido + 6 chaves + entrega por hook do apt.
# O Firefox saiu da base nativa, entao l10n-pt-br nao e mais exigencia da base:
# o que passa a valer e que as policies cheguem ao Firefox INDEPENDENTE de como
# ele foi instalado (Kit, pool offline ou "sudo apt install firefox-esr").
prova 5 "policies.json (telemetria off, DoH Quad9, uBlock)" bash -c '
  python3 -m json.tool firefox/policies.json >/dev/null &&
  grep -q "DisableTelemetry" firefox/policies.json &&
  grep -q "DisableFirefoxStudies" firefox/policies.json &&
  grep -q "DisablePocket" firefox/policies.json &&
  grep -q "dns.quad9.net" firefox/policies.json &&
  grep -q "uBlock0@raymondhill.net" firefox/policies.json &&
  grep -q "HTTPSOnlyMode" firefox/policies.json &&
  ! grep -q "about:panthera-welcome" firefox/policies.json &&
  grep -q "l10n-pt-br" kits/catalogo.json &&
  grep -q "firefox-esr" kits/catalogo.json &&
  grep -q "apt.hooks.d" hooks/live/0300-firefox.hook.chroot &&
  echo "policies + entrega por hook do apt OK"'

# 6. mount noexec (Secao 9 + I7): udisks monta /media sem exec
prova 6 "usb noexec,nodev,nosuid" bash -c '
  grep -q "defaults=noexec,nodev,nosuid" includes.chroot/etc/udisks2/mount_options.conf &&
  echo "udisks2 mount_options OK"'

# 7. manifestos (RNF002 + auditoria item 9)
prova 7 "privacy-manifest + removed-bloat + version" bash -c '
  [ -f includes.chroot/etc/panthera/privacy-manifest.txt ] &&
  grep -q "2026-09-29" includes.chroot/etc/panthera/privacy-manifest.txt &&
  [ -f includes.chroot/etc/panthera/removed-bloat.txt ] &&
  grep -q "^snapd" includes.chroot/etc/panthera/removed-bloat.txt &&
  grep -q "PANTHERA_VERSION=v1.0-uso-geral" includes.chroot/etc/panthera/version &&
  echo "manifestos OK"'

# 8. sudo timeout 10 + sem core (Secao 32)
prova 8 "sudoers timeout 10 + limits core 0" bash -c '
  grep -q "timestamp_timeout=10" includes.chroot/etc/sudoers.d/panthera &&
  grep -q "passwd_tries=3" includes.chroot/etc/sudoers.d/panthera &&
  grep -q "^\* hard core 0$" includes.chroot/etc/security/limits.d/panthera.conf &&
  grep -q "chmod 440" hooks/live/0400-hardening.hook.chroot &&
  echo "sudoers + limits OK"'

# 9. sysctl fiel Secao 3.4
prova 9 "sysctl Panthera (Secao 3.4)" bash -c '
  [ "$(grep -v "^#" includes.chroot/etc/sysctl.d/99-panthera.conf | grep -v "^$" | wc -l)" -eq 13 ] &&
  grep -q "kernel.yama.ptrace_scope=2" includes.chroot/etc/sysctl.d/99-panthera.conf &&
  grep -q "net.ipv4.tcp_syncookies=1" includes.chroot/etc/sysctl.d/99-panthera.conf &&
  grep -q "kernel.unprivileged_bpf_disabled=2" includes.chroot/etc/sysctl.d/99-panthera.conf &&
  echo "13 chaves fieis ao ODT OK"'

# 10. clam sem daemon (Secao 3.1: demanda, sem residente 500MB)
prova 10 "clamav demanda sem daemon" bash -c '
  grep -q "^clamav$" packages-lists/panthera-base.list &&
  grep -q "^clamtk$" packages-lists/panthera-base.list &&
  ! grep -q "clamav-daemon" packages-lists/panthera-base.list &&
  echo "clamav+clamtk sem daemon OK"'

{
echo "================ COMANDOS LIVE (Apendice H, colar no Debian apos build) ================"
echo "# 1 pacotes: dpkg -l | grep -i -E 'snapd|apport|whoopsie|popularity|ubuntu-report' || echo LIMPO-OK"
echo "# 2 servicos: systemctl list-unit-files --state=enabled | grep -E 'snapd|tracker|apport' || echo SERVICOS-OK"
echo "# 3 firewall: sudo ufw status verbose  # active, deny incoming, allow outgoing"
echo "# 4 apparmor: sudo aa-status | head -20  # enforce, firefox incluido"
echo "# 5 sysctl: cat /etc/sysctl.d/99-panthera.conf  # 13 linhas"
echo "# 6 rede: ss -tulpn  # so 127.0.0.1:631, dhcp, avahi; nada 0.0.0.0:22"
echo "# 7 usb: mount | grep media  # noexec,nodev,nosuid"
echo "# 8 manifestos: cat /etc/panthera/privacy-manifest.txt; cat /etc/panthera/removed-bloat.txt"
echo "# 9 sudo/core: cat /etc/sudoers.d/panthera; cat /etc/security/limits.d/panthera.conf; ulimit -c  # 0"
echo "# 10 clam: clamscan --version; ps aux | grep -i clam | grep -v grep || echo SEM-DAEMON-OK"
echo "# 11 firefox: ls -l /usr/lib/firefox-esr/distribution/policies.json; abrir about:policies"
} >> "$PROVAS"

if [ "$FAIL" -ne 0 ]; then echo "HARDENING FALHOU. Veja $PROVAS"; exit 1; fi
echo "HARDENING PASS (10/10). Provas em $PROVAS"
