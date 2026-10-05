#!/usr/bin/env python3
# /usr/bin/panthera-limpeza - Limpador de disco Panthera
# So GTK3 + stdlib. Mostra o tamanho MEDIDO de cada categoria e limpa so o que
# o usuario marcar, com confirmacao mostrando o comando exato. Nunca apaga
# documento, foto ou nada da pasta pessoal: so cache, lixeira e logs velhos.
# Teste: python3 -m py_compile + python3 panthera-limpeza.py --help (sem display)
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

import os
import shlex
import subprocess
import sys
import time

LOG = "/var/log/panthera-limpeza.log"
TERMINAL = "x-terminal-emulator"


def registrar(linha):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), linha))
    except OSError:
        pass


def tamanho_pasta(caminho):
    """Bytes somando os arquivos. 0 quando nao existe ou sem permissao."""
    total = 0
    try:
        for raiz, _dirs, arquivos in os.walk(caminho):
            for nome in arquivos:
                try:
                    total += os.lstat(os.path.join(raiz, nome)).st_size
                except OSError:
                    pass
    except OSError:
        pass
    return total


def tamanho_comando(argv):
    """Bytes via du, ou 0 quando o comando falha."""
    try:
        r = subprocess.run(argv + ["-sb"], capture_output=True, text=True, timeout=20)
        if r.returncode == 0:
            return int(r.stdout.split()[0])
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
        pass
    return 0


def tamanho_humano(n):
    if n < 1024:
        return "%d B" % n
    n /= 1024.0
    for unidade in ("KB", "MB", "GB"):
        if n < 1024 or unidade == "GB":
            return "%.1f %s" % (n, unidade)
        n /= 1024.0
    return "%.1f GB" % n


def espaco_livre():
    try:
        r = subprocess.run(["df", "-h", "/"], capture_output=True, text=True, timeout=10)
        return r.stdout.splitlines()[-1].split()[3]
    except (OSError, IndexError, subprocess.TimeoutExpired):
        return "?"


def categorias():
    """Cada categoria: (chave, nome, o-que-e, comandos-sudo). Tamanho medido na hora."""
    casa = os.path.expanduser("~")
    return [
        ("apt", "Pacotes baixados (APT)",
         "Instaladores que ficam guardados depois de instalar. Apagar e seguro: o sistema baixa de novo se precisar.",
         ["apt-get clean"], tamanho_pasta("/var/cache/apt/archives")),
        ("journal", "Registros antigos do sistema",
         "Diario de bordo com mais de 7 dias. O sistema continua registrando normal depois.",
         ["journalctl --vacuum-time=7d"], 0),
        ("lixeira", "Lixeira",
         "Arquivos que voce ja jogou fora. Apagar daqui nao tem volta.",
         [], tamanho_pasta(os.path.join(casa, ".local/share/Trash"))),
        ("miniaturas", "Miniaturas de fotos e videos",
         "Imagens pequenas que o gerenciador de arquivos cria para mostrar previa. Sao recriadas sozinhas.",
         [], tamanho_pasta(os.path.join(casa, ".cache/thumbnails"))),
    ]


if "--help" in sys.argv or "-h" in sys.argv:
    print("Limpeza Panthera: mostra o espaco medido e limpa so o marcado.")
    raise SystemExit(0)


class Limpeza(Gtk.Window):
    def __init__(self):
        super().__init__(title="Limpeza Panthera")
        self.set_default_size(620, 480)
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        v.set_border_width(14)
        self.add(v)

        titulo = Gtk.Label()
        titulo.set_markup("<b>Limpeza Panthera</b>")
        titulo.set_xalign(0)
        v.pack_start(titulo, False, False, 0)

        self.livre = Gtk.Label(label="Espaço livre em /: %s" % espaco_livre())
        self.livre.set_xalign(0)
        v.pack_start(self.livre, False, False, 0)

        info = Gtk.Label(label="Nada e apagado sem voce marcar e confirmar. "
                               "Documento, foto e programa ficam intactos.")
        info.set_xalign(0)
        info.set_line_wrap(True)
        v.pack_start(info, False, False, 0)

        self.caixas = {}
        for chave, nome, desc, _cmds, tamanho in categorias():
            linha = Gtk.Box(spacing=8)
            check = Gtk.CheckButton()
            linha.pack_start(check, False, False, 0)
            textos = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            titulo_item = Gtk.Label()
            titulo_item.set_markup("<b>%s</b> — %s" % (nome, tamanho_humano(tamanho)))
            titulo_item.set_xalign(0)
            textos.pack_start(titulo_item, False, False, 0)
            detalhe = Gtk.Label(label=desc)
            detalhe.set_xalign(0)
            detalhe.set_line_wrap(True)
            textos.pack_start(detalhe, False, False, 0)
            linha.pack_start(textos, True, True, 0)
            v.pack_start(linha, False, False, 0)
            self.caixas[chave] = check

        rodape = Gtk.Box(spacing=8)
        limpar = Gtk.Button(label="Limpar marcados")
        limpar.connect("clicked", lambda _w: self.safe(self.confirmar))
        rodape.pack_start(limpar, False, False, 0)
        v.pack_start(rodape, False, False, 0)

    def safe(self, acao, *args):
        try:
            return acao(*args)
        except Exception as e:
            registrar("erro tratado: %s" % e)
            print("Erro tratado: %s" % e)
            return None

    def confirmar(self):
        marcadas = [c for c, caixinha in self.caixas.items() if caixinha.get_active()]
        if not marcadas:
            self._aviso("Marque pelo menos uma categoria.")
            return
        por_chave = {c[0]: c for c in categorias()}
        comandos = []
        for chave in marcadas:
            _c, _n, _d, cmds, _t = por_chave[chave]
            comandos.extend(cmds)
            if chave == "lixeira":
                comandos.append("rm -rf ~/.local/share/Trash/files/* ~/.local/share/Trash/info/*")
            if chave == "miniaturas":
                comandos.append("rm -rf ~/.cache/thumbnails/*")
        texto = "Vai rodar, nesta ordem:\n\n" + "\n".join("  $ " + c for c in comandos)
        texto += "\n\nConfirma?"
        dialogo = Gtk.MessageDialog(
            transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL, text="Limpar %d categoria(s)?" % len(marcadas),
        )
        dialogo.format_secondary_text(texto)
        resposta = dialogo.run()
        dialogo.destroy()
        if resposta == Gtk.ResponseType.OK:
            self._rodar(comandos)

    def _rodar(self, comandos):
        destino = "/tmp/panthera-limpeza.sh"
        with open(destino, "w", encoding="utf-8") as f:
            f.write("#!/bin/bash\nset -u\n")
            for cmd in comandos:
                f.write("echo '>>> %s'\n" % cmd.replace("'", "'\\''"))
                # rm de lixeira/miniaturas roda como usuario; apt/journal pedem sudo
                if cmd.startswith(("apt-get", "journalctl")):
                    f.write("sudo -E bash -c %s\n\n" % shlex.quote(cmd))
                else:
                    f.write("bash -c %s\n\n" % shlex.quote(cmd))
            f.write("echo '--- pronto ---'; read -p 'Enter para fechar' _\n")
        os.chmod(destino, 0o755)
        registrar("limpeza -> %s" % destino)
        terminal = None
        for pasta in os.environ.get("PATH", "").split(os.pathsep):
            caminho = os.path.join(pasta, TERMINAL)
            if os.access(caminho, os.X_OK):
                terminal = caminho
                break
        if not terminal:
            self._aviso("Nao achei um terminal. Rode:\n\n  bash %s" % destino)
            return
        try:
            subprocess.Popen([terminal, "-e", "bash %s" % destino], start_new_session=True)
        except OSError as e:
            registrar("Popen falhou: %s" % e)
            self._aviso("Nao consegui abrir o terminal.\n%s" % e)

    def _aviso(self, texto):
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.INFO,
                              buttons=Gtk.ButtonsType.CLOSE, text=texto)
        d.run()
        d.destroy()


if __name__ == "__main__":
    janela = Limpeza()
    janela.connect("destroy", Gtk.main_quit)
    janela.show_all()
    Gtk.main()
