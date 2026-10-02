#!/bin/bash
# /usr/bin/panthera-firefox-policies - entrega as policies do Firefox sempre que
# o firefox-esr existir na maquina (ODT Secao 8).
#
# Por que um script e nao o hook 0300: o hook roda no build, dentro do chroot.
# Depois que o Firefox saiu da base nativa, o usuario o instala por um Kit, ou
# na mao com "sudo apt install firefox-esr". Se as policies so fossem entregues
# no build, o Firefox instalado na mao nasceria SEM nenhuma protecao: sem DoH
# Quad9, sem HTTPS-only, sem uBlock, com telemetria ligada. Este script fecha
# esse buraco e roda tambem via /etc/apt/apt.hooks.d/90panthera-firefox.
set -u

ORIGEM=/usr/share/panthera-firefox
DESTINO=/usr/lib/firefox-esr/distribution

[ -d "$DESTINO" ] || exit 0          # firefox-esr nao esta instalado: nada a fazer
[ -f "$ORIGEM/policies.json" ] || exit 0
[ -f "$ORIGEM/distribution.ini" ] || exit 0

# Nao sobrescreve edicao local do usuario sem avisar.
if [ -f "$DESTINO/policies.json" ] && ! cmp -s "$ORIGEM/policies.json" "$DESTINO/policies.json"; then
  if [ -f "$DESTINO/.panthera-aviso" ]; then
    exit 0
  fi
  touch "$DESTINO/.panthera-aviso"
  echo "panthera: policies do Firefox foram alteradas localmente." >&2
  echo "panthera: para voltar ao padrao, apague $DESTINO/.panthera-aviso e rode:" >&2
  echo "panthera:   sudo $0" >&2
  exit 0
fi

install -d -m 0755 "$DESTINO" 2>/dev/null || exit 0
install -m 0644 "$ORIGEM/policies.json" "$DESTINO/policies.json" 2>/dev/null || exit 0
install -m 0644 "$ORIGEM/distribution.ini" "$DESTINO/distribution.ini" 2>/dev/null || exit 0
rm -f "$DESTINO/.panthera-aviso"
exit 0
