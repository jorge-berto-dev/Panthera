#!/usr/bin/env python3
# /usr/bin/panthera-backup - Backup Panthera
# Copia a pasta pessoal para um pendrive/HD externo e restaura de volta.
# So GTK3 + stdlib. Usa rsync (esta na base). Nunca apaga a origem: o backup
# so COPIA, e a restauracao pede confirmacao mostrando exatamente o que volta.
# Todo backup carrega um carimbo PANTHERA-BACKUP.txt; restaurar de pasta sem
# carimbo e recusado, para ninguem restaurar a pasta errada por engano.
# Teste: python3 -m py_compile + python3 panthera-backup.py --help (sem display)
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

import json
import os
import shutil
import subprocess
import sys
import time

LOG = "/var/log/panthera-backup.log"
CARIMBO = "PANTHERA-BACKUP.txt"
# Cache e lixeira nao sao backup: ocupam espaco e sao recriados sozinhos.
EXCLUIR = [".cache/", ".local/share/Trash/", ".local/share/Trash",
           "snap/", ".mozilla/firefox/*/Cache/"]


def registrar(linha):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%SZ"), linha))
    except OSError:
        pass


def tamanho_pasta(caminho, excluir=()):
    """Bytes somando arquivos, pulando o que esta na lista de exclusao."""
    total = 0
    try:
        for raiz, _dirs, arquivos in os.walk(caminho):
            rel = os.path.relpath(raiz, caminho)
            if any(rel.startswith(e.rstrip("/")) or e.rstrip("/") in rel for e in excluir):
                continue
            for nome in arquivos:
                try:
                    total += os.lstat(os.path.join(raiz, nome)).st_size
                except OSError:
                    pass
    except OSError:
        pass
    return total


def tamanho_humano(n):
    if n is None:
        return "?"
    if n < 1024:
        return "%d B" % n
    n /= 1024.0
    for unidade in ("KB", "MB", "GB"):
        if n < 1024 or unidade == "GB":
            return "%.1f %s" % (n, unidade)
        n /= 1024.0
    return "%.1f GB" % n


def destinos_removiveis():
    """Pendrives e HDs externos montados, com espaco livre medido."""
    base = "/media/%s" % os.environ.get("USER", "user")
    saidas = []
    for raiz in (base, "/media", "/run/media/%s" % os.environ.get("USER", "user")):
        try:
            nomes = sorted(os.listdir(raiz))
        except OSError:
            continue
        for nome in nomes:
            caminho = os.path.join(raiz, nome)
            if not os.path.ismount(caminho) and raiz == "/media":
                continue
            if not os.path.isdir(caminho) or not os.access(caminho, os.W_OK):
                continue
            try:
                uso = shutil.disk_usage(caminho)
                livre = uso.free
            except OSError:
                continue
            if not any(d[0] == caminho for d in saidas):
                saidas.append((caminho, livre))
    return saidas


def escrever_carimbo(pasta, origem):
    dados = {"app": "panthera-backup", "versao": 1,
             "data": time.strftime("%Y-%m-%dT%H:%M:%S"),
             "origem": origem, "usuario": os.environ.get("USER", "?")}
    with open(os.path.join(pasta, CARIMBO), "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=2)


def ler_carimbo(pasta):
    """Devolve o carimbo ou None quando a pasta nao e um backup Panthera."""
    try:
        with open(os.path.join(pasta, CARIMBO), encoding="utf-8") as f:
            dados = json.load(f)
        if dados.get("app") == "panthera-backup":
            return dados
    except (OSError, ValueError):
        pass
    return None


def comando_backup(origem, destino):
    """rsync de copia. Nunca --delete na origem: o backup so soma."""
    argv = ["rsync", "-a", "--info=progress2"]
    for e in EXCLUIR:
        argv += ["--exclude", e]
    return argv + [origem.rstrip("/") + "/", destino.rstrip("/") + "/"]


def comando_restaurar(backup, destino):
    return ["rsync", "-a", "--info=progress2",
            backup.rstrip("/") + "/", destino.rstrip("/") + "/"]


if "--help" in sys.argv or "-h" in sys.argv:
    print("Backup Panthera: copia a pasta pessoal para pendrive e restaura de volta.")
    raise SystemExit(0)


class Backup(Gtk.Window):
    def __init__(self):
        super().__init__(title="Backup Panthera")
        self.set_default_size(640, 520)
        self.processo = None
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        v.set_border_width(14)
        self.add(v)

        titulo = Gtk.Label()
        titulo.set_markup("<b>Backup Panthera</b>")
        titulo.set_xalign(0)
        v.pack_start(titulo, False, False, 0)

        casa = os.path.expanduser("~")
        tam = tamanho_pasta(casa, EXCLUIR)
        info = Gtk.Label(label="Sua pasta pessoal tem %s para guardar (sem cache nem lixeira).\nO backup só COPIA: nada daqui e apagado." % tamanho_humano(tam))
        info.set_xalign(0)
        info.set_line_wrap(True)
        v.pack_start(info, False, False, 0)

        rot = Gtk.Label()
        rot.set_markup("<b>Para onde vai o backup</b>")
        rot.set_xalign(0)
        v.pack_start(rot, False, False, 0)

        self.lista_dest = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        v.pack_start(self.lista_dest, False, False, 0)
        self.destino = None
        self._listar_destinos()

        outra = Gtk.Button(label="Escolher outra pasta...")
        outra.connect("clicked", lambda _w: self.safe(self._escolher_pasta))
        v.pack_start(outra, False, False, 0)

        self.progresso = Gtk.ProgressBar()
        self.progresso.set_show_text(True)
        self.progresso.set_text("parado")
        v.pack_start(self.progresso, False, False, 0)

        self.estado = Gtk.Label(label="")
        self.estado.set_xalign(0)
        self.estado.set_line_wrap(True)
        v.pack_start(self.estado, False, False, 0)

        rodape = Gtk.Box(spacing=8)
        fazer = Gtk.Button(label="Fazer backup agora")
        fazer.connect("clicked", lambda _w: self.safe(self._backup))
        rodape.pack_start(fazer, False, False, 0)
        restaurar = Gtk.Button(label="Restaurar de um backup...")
        restaurar.connect("clicked", lambda _w: self.safe(self._restaurar))
        rodape.pack_start(restaurar, False, False, 0)
        v.pack_start(rodape, False, False, 0)

    def safe(self, acao, *args):
        try:
            return acao(*args)
        except Exception as e:
            registrar("erro tratado: %s" % e)
            self._aviso("Algo deu errado, mas nada foi apagado.\nDetalhe em %s" % LOG)
            return None

    def _listar_destinos(self):
        for filho in list(self.lista_dest.get_children()):
            self.lista_dest.remove(filho)
        primeiro = None
        for caminho, livre in destinos_removiveis():
            botao = Gtk.RadioButton(group=primeiro) if primeiro else Gtk.RadioButton()
            if primeiro is None:
                primeiro = botao
                self.destino = caminho
            botao.connect("toggled", lambda _w, c=caminho: self.safe(self._marca_destino, c))
            linha = Gtk.Box(spacing=8)
            linha.pack_start(botao, False, False, 0)
            texto = Gtk.Label(label="%s  (%s livres)" % (caminho, tamanho_humano(livre)))
            texto.set_xalign(0)
            linha.pack_start(texto, True, True, 0)
            self.lista_dest.pack_start(linha, False, False, 0)
        if primeiro is None:
            self.lista_dest.pack_start(
                Gtk.Label(label="Nenhum pendrive encontrado. Espete um e reabra, ou use 'Escolher outra pasta'."), False, False, 0)
        self.lista_dest.show_all()

    def _marca_destino(self, _botao, caminho):
        self.destino = caminho

    def _escolher_pasta(self):
        dialogo = Gtk.FileChooserDialog(
            title="Escolher onde guardar", parent=self,
            action=Gtk.FileChooserAction.SELECT_FOLDER)
        dialogo.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                            Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        if dialogo.run() == Gtk.ResponseType.OK:
            self.destino = dialogo.get_filename()
            self.estado.set_text("Destino: %s" % self.destino)
        dialogo.destroy()

    def _backup(self):
        if not self.destino:
            self._aviso("Escolha primeiro para onde vai o backup.")
            return
        casa = os.path.expanduser("~")
        if os.path.abspath(self.destino) == os.path.abspath(casa) or \
           os.path.abspath(self.destino).startswith(os.path.abspath(casa) + os.sep):
            self._aviso("O backup nao pode ficar DENTRO da pasta pessoal: seria copiar a copia para sempre.\nEscolha um pendrive ou outra pasta fora da pessoal.")
            return
        try:
            livre = shutil.disk_usage(self.destino).free
        except OSError as e:
            self._aviso("Nao consegui ler o destino.\n%s" % e)
            return
        precisa = tamanho_pasta(casa, EXCLUIR)
        if precisa > livre:
            self._aviso("Nao cabe: precisa de %s e o destino tem %s livres." % (
                tamanho_humano(precisa), tamanho_humano(livre)))
            return
        dialogo = Gtk.MessageDialog(
            transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text="Copiar %s para\n%s?" % (tamanho_humano(precisa), self.destino))
        dialogo.format_secondary_text("Nada daqui sera apagado. Demora conforme o tamanho.")
        resposta = dialogo.run()
        dialogo.destroy()
        if resposta != Gtk.ResponseType.OK:
            return
        pasta = os.path.join(self.destino, "panthera-backup")
        try:
            os.makedirs(pasta, exist_ok=True)
        except OSError as e:
            self._aviso("Nao consegui criar a pasta.\n%s" % e)
            return
        self._rodar(comando_backup(casa, pasta),
                    "Backup pronto em %s." % pasta,
                    lambda: escrever_carimbo(pasta, casa))

    def _restaurar(self):
        dialogo = Gtk.FileChooserDialog(
            title="Escolher a pasta do backup", parent=self,
            action=Gtk.FileChooserAction.SELECT_FOLDER)
        dialogo.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                            Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        if dialogo.run() != Gtk.ResponseType.OK:
            dialogo.destroy()
            return
        origem = dialogo.get_filename()
        dialogo.destroy()
        carimbo = ler_carimbo(origem)
        if carimbo is None:
            self._aviso("Esta pasta nao tem o carimbo %s.\nPara nao restaurar a pasta errada por engano, so restauro backup feito por este app." % CARIMBO)
            return
        casa = os.path.expanduser("~")
        conf = Gtk.MessageDialog(
            transient_for=self, modal=True, message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text="Trazer de volta o backup de %s?" % carimbo.get("data", "?"))
        conf.format_secondary_text("Vai para: %s\nArquivos com o mesmo nome serao substituidos. O backup continua la." % casa)
        resposta = conf.run()
        conf.destroy()
        if resposta != Gtk.ResponseType.OK:
            return
        self._rodar(comando_restaurar(origem, casa), "Restauração concluída. Saia e entre de novo para recarregar tudo.")

    def _rodar(self, argv, pronto, depois=None):
        if self.processo is not None:
            self._aviso("Ja tem uma copia rodando. Espere terminar.")
            return
        registrar("iniciando: %s" % " ".join(argv))
        self.progresso.pulse()
        self._tick = GLib.timeout_add(200, lambda: self.progresso.pulse() or True)
        self.estado.set_text("Copiando... pode demorar. Nao feche esta janela.")
        try:
            self.processo = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError as e:
            GLib.source_remove(self._tick)
            registrar("Popen falhou: %s" % e)
            self._aviso("Nao consegui iniciar a copia.\n%s" % e)
            self.processo = None
            return

        def vigiar():
            rc = self.processo.poll()
            if rc is None:
                return True
            GLib.source_remove(self._tick)
            self.progresso.set_fraction(1.0)
            self.processo = None
            if rc == 0:
                try:
                    if depois:
                        depois()
                except Exception as e:
                    registrar("pos-copia falhou: %s" % e)
                registrar("concluido")
                self.estado.set_text(pronto)
                self.progresso.set_text("pronto")
                self._aviso(pronto)
            else:
                registrar("rsync saiu com codigo %d" % rc)
                self.estado.set_text("A copia falhou no meio. Nada foi apagado da origem.")
                self.progresso.set_text("falhou — veja %s" % LOG)
                self._aviso("A copia falhou no meio (código %d).\nNada foi apagado da origem. Detalhe em %s" % (rc, LOG))
            return False
        GLib.timeout_add(1000, vigiar)

    def _aviso(self, texto):
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.INFO,
                              buttons=Gtk.ButtonsType.CLOSE, text=texto)
        d.run()
        d.destroy()


if __name__ == "__main__":
    janela = Backup()
    janela.connect("destroy", Gtk.main_quit)
    janela.show_all()
    Gtk.main()
