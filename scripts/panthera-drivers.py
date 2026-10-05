#!/usr/bin/env python3
# /usr/bin/panthera-drivers - Drivers Panthera
# Mostra cada peça do PC, diz se tem driver em uso e oferece o firmware que
# falta, com o motivo. So GTK3 + stdlib. Deteccao via lspci/lsusb/sysfs;
# instalacao via apt em terminal com sudo, uma transacao so.
# Regra honesta: firmware (arquivo) instala com 1 clique; driver proprietario
# (NVIDIA) mostra aviso forte e explica, porque troca o boot e so se prova em
# hardware real com reboot.
# Teste: python3 -m py_compile + python3 panthera-drivers.py --help (sem display)
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

import os
import re
import shutil
import subprocess
import sys
import time

LOG = "/var/log/panthera-drivers.log"
TERMINAL = "x-terminal-emulator"

# driver em uso (ou modulo) -> (pacote firmware, por que). So o que e fato no
# Debian bookworm; o que nao esta aqui vira "sem sugestao automatica", nunca
# chute.
FIRMWARE_POR_DRIVER = {
    "iwlwifi": ("firmware-iwlwifi", "Wi-Fi Intel precisa deste firmware para ligar"),
    "rtw88_pci": ("firmware-realtek", "Wi-Fi Realtek precisa deste firmware para ligar"),
    "rtw89_pci": ("firmware-realtek", "Wi-Fi Realtek precisa deste firmware para ligar"),
    "rtl8723be": ("firmware-realtek", "Wi-Fi Realtek precisa deste firmware para ligar"),
    "rtl8821ce": ("firmware-realtek", "Wi-Fi Realtek precisa deste firmware para ligar"),
    "ath10k_pci": ("firmware-atheros", "Wi-Fi Atheros precisa deste firmware para ligar"),
    "ath11k_pci": ("firmware-atheros", "Wi-Fi Atheros precisa deste firmware para ligar"),
    "amdgpu": ("firmware-amd-graphics", "Video AMD precisa deste firmware para acelerar"),
    "snd_sof_pci": ("firmware-sof-signed", "Audio Intel moderno precisa deste firmware para sair som"),
    "btusb": (None, ""),
}
# Sem driver nenhum e com estes nomes: sugestao direta pelo nome da peca.
SEM_DRIVER_POR_NOME = [
    ("nvidia", "nvidia-driver", "proprietario",
     "Placa NVIDIA sem driver: o livre (nouveau) nao assumiu. O proprietario troca o boot: so instale se o video estiver ruim, e saiba que precisa reiniciar."),
    ("iwlwifi", "firmware-iwlwifi", "firmware",
     "Wi-Fi Intel reconhecida mas sem firmware."),
    ("realtek", "firmware-realtek", "firmware",
     "Peca Realtek reconhecida mas sem firmware."),
    ("atheros", "firmware-atheros", "firmware",
     "Peca Atheros reconhecida mas sem firmware."),
    ("broadcom", "firmware-brcm80211", "firmware",
     "Wi-Fi Broadcom reconhecida mas sem firmware."),
]


def registrar(linha):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%SZ"), linha))
    except OSError:
        pass


def rodar(argv, timeout=20):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout
    except (OSError, subprocess.TimeoutExpired) as e:
        registrar("rodar %s falhou: %s" % (argv[0], e))
        return 127, ""


def parse_lspci(texto):
    """Quebra o 'lspci -nnk' em pecas: slot, classe, nome, driver, modulos."""
    pecas, atual = [], None
    for linha in texto.splitlines():
        m = re.match(r"^([0-9a-f:.]+) (.+?) \[([0-9a-f]{4})\]: (.+?) \[([0-9a-f]{4}):([0-9a-f]{4})\]", linha)
        if m:
            atual = {"slot": m.group(1), "classe": m.group(2), "classe_id": m.group(3),
                     "nome": m.group(4), "driver": None, "modulos": []}
            pecas.append(atual)
            continue
        if atual is None:
            continue
        m = re.match(r"^\s+Kernel driver in use: (\S+)", linha)
        if m:
            atual["driver"] = m.group(1)
            continue
        m = re.match(r"^\s+Kernel modules: (.+)", linha)
        if m:
            atual["modulos"] = m.group(1).split(", ")
    return pecas


def parse_lsusb(texto):
    """Quebra o 'lsusb' em dispositivos: bus, id, nome."""
    saidas = []
    for linha in texto.splitlines():
        m = re.match(r"^Bus (\d+) Device (\d+): ID ([0-9a-f:]+) (.+)$", linha)
        if m:
            saidas.append({"bus": m.group(1), "id": m.group(3), "nome": m.group(4).strip()})
    return saidas


def pacote_instalado(nome):
    if not nome:
        return True
    rc, _ = rodar(["dpkg-query", "-W", "-f=${db:Status-Status}", nome])
    return rc == 0


def avaliar(peca):
    """Devolve (estado, pacote, detalhe). Estado: ok | firmware | proprietario | manual."""
    driver = (peca.get("driver") or "").lower()
    modulos = [m.lower() for m in peca.get("modulos", [])]
    nome = peca.get("nome", "")
    baixo = nome.lower()
    for candidato in [driver] + modulos:
        if candidato in FIRMWARE_POR_DRIVER:
            pacote, motivo = FIRMWARE_POR_DRIVER[candidato]
            if pacote is None:
                return "ok", None, "driver %s em uso" % candidato
            if pacote_instalado(pacote):
                return "ok", None, "driver %s em uso, firmware %s instalado" % (candidato, pacote)
            return "firmware", pacote, motivo
    if driver in ("nouveau",):
        return "ok", None, "video funcionando com driver livre (nouveau)"
    if driver:
        return "ok", None, "driver %s em uso" % peca.get("driver")
    for pedaço, pacote, tipo, motivo in SEM_DRIVER_POR_NOME:
        if pedaço in baixo:
            return tipo, pacote, motivo
    if peca.get("classe_id") in ("0600", "0601", "0500", "0780", "0c80", "1180"):
        return "ok", None, "peca auxiliar, nao precisa de firmware"
    return "manual", None, "sem driver em uso e sem sugestao automatica: anote o nome e procure ajuda"


def faltando_firmware(pecas):
    """Pacotes firmware que faltam, deduplicados e na ordem."""
    vistos, saida = set(), []
    for peca in pecas:
        estado, pacote, _det = avaliar(peca)
        if estado == "firmware" and pacote not in vistos:
            vistos.add(pacote)
            saida.append(pacote)
    return saida


if "--help" in sys.argv or "-h" in sys.argv:
    print("Drivers Panthera: mostra cada peça, o driver em uso e o firmware que falta.")
    raise SystemExit(0)


class Drivers(Gtk.Window):
    def __init__(self):
        super().__init__(title="Drivers Panthera")
        self.set_default_size(680, 520)
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        v.set_border_width(14)
        self.add(v)

        titulo = Gtk.Label()
        titulo.set_markup("<b>Drivers Panthera</b>")
        titulo.set_xalign(0)
        v.pack_start(titulo, False, False, 0)

        sub = Gtk.Label(label="Cada peça do PC, o driver em uso e o que falta. Firmware instala com 1 clique; proprietário avisa antes.")
        sub.set_xalign(0)
        sub.set_line_wrap(True)
        v.pack_start(sub, False, False, 0)

        rc, saida = rodar(["lspci", "-nnk"])
        self.pecas = parse_lspci(saida) if rc == 0 else []
        if not self.pecas:
            v.pack_start(Gtk.Label(label="Não consegui ler o hardware (lspci ausente ou falhou). Veja %s" % LOG), False, False, 0)
            return

        for peca in self.pecas:
            estado, pacote, detalhe = avaliar(peca)
            linha = Gtk.Box(spacing=8)
            marca = {"ok": "✓", "firmware": "⬇", "proprietario": "⚠", "manual": "?"}.get(estado, "?")
            simbolo = Gtk.Label(label=marca)
            simbolo.set_width_chars(3)
            linha.pack_start(simbolo, False, False, 0)
            textos = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            nome = Gtk.Label(label="%s  [%s]" % (peca["nome"][:70], peca["slot"]))
            nome.set_xalign(0)
            textos.pack_start(nome, False, False, 0)
            info = Gtk.Label(label=detalhe)
            info.set_xalign(0)
            info.set_line_wrap(True)
            textos.pack_start(info, False, False, 0)
            linha.pack_start(textos, True, True, 0)
            if estado in ("firmware", "proprietario"):
                botao = Gtk.Button(label="Instalar")
                botao.connect("clicked", lambda _w, p=pacote, t=estado, n=peca["nome"]: self.safe(self._instalar_um, p, t, n))
                linha.pack_start(botao, False, False, 0)
            v.pack_start(linha, False, False, 0)

        faltam = faltando_firmware(self.pecas)
        if faltam:
            rodape = Gtk.Box(spacing=8)
            todos = Gtk.Button(label="Instalar tudo que falta (%d)" % len(faltam))
            todos.connect("clicked", lambda _w: self.safe(self._instalar_tudo, faltam))
            rodape.pack_start(todos, False, False, 0)
            v.pack_start(rodape, False, False, 0)

    def safe(self, acao, *args):
        try:
            return acao(*args)
        except Exception as e:
            registrar("erro tratado: %s" % e)
            self._aviso("Algo deu errado, mas nada foi instalado pela metade.\nDetalhe em %s" % LOG)
            return None

    def _instalar_um(self, pacote, tipo, nome):
        if tipo == "proprietario":
            dialogo = Gtk.MessageDialog(
                transient_for=self, modal=True, message_type=Gtk.MessageType.WARNING,
                buttons=Gtk.ButtonsType.OK_CANCEL,
                text="Instalar o driver proprietário para\n%s?" % nome[:60])
            dialogo.format_secondary_text(
                "Isso troca o driver de vídeo do sistema e precisa reiniciar. "
                "Se o vídeo já está funcionando, não instale. Só validei este caminho em docs, nunca em hardware real.")
            resposta = dialogo.run()
            dialogo.destroy()
            if resposta != Gtk.ResponseType.OK:
                return
        self._rodar(["apt-get", "install", "-y", pacote], "Driver %s instalado. Reinicie o PC." % pacote)

    def _instalar_tudo(self, pacotes):
        dialogo = Gtk.MessageDialog(
            transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text="Instalar %d pacote(s)?" % len(pacotes))
        dialogo.format_secondary_text("Uma transação só:\n\n  sudo apt-get install -y %s" % " ".join(pacotes))
        resposta = dialogo.run()
        dialogo.destroy()
        if resposta == Gtk.ResponseType.OK:
            self._rodar(["apt-get", "install", "-y"] + pacotes,
                        "Firmwares instalados. Reinicie o PC para ativarem.")

    def _rodar(self, argv, pronto):
        destino = "/tmp/panthera-drivers.sh"
        with open(destino, "w", encoding="utf-8") as f:
            f.write("#!/bin/bash\nset -euo pipefail\nexport DEBIAN_FRONTEND=noninteractive\n")
            f.write("sudo -E %s\n" % " ".join(argv))
            f.write("echo '--- pronto ---'; read -p 'Enter para fechar' _\n")
        os.chmod(destino, 0o755)
        registrar("drivers -> %s" % " ".join(argv))
        terminal = shutil.which(TERMINAL)
        if not terminal:
            self._aviso("Não achei um terminal. Rode:\n\n  sudo %s" % " ".join(argv))
            return
        try:
            subprocess.Popen([terminal, "-e", "bash %s" % destino], start_new_session=True)
        except OSError as e:
            registrar("Popen falhou: %s" % e)
            self._aviso("Não consegui abrir o terminal.\n%s" % e)
            return
        self._aviso("%s\n\nAbri o terminal instalando. %s" % (" ".join(argv), pronto))

    def _aviso(self, texto):
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.INFO,
                              buttons=Gtk.ButtonsType.CLOSE, text=texto)
        d.run()
        d.destroy()


if __name__ == "__main__":
    janela = Drivers()
    janela.connect("destroy", Gtk.main_quit)
    janela.show_all()
    Gtk.main()
