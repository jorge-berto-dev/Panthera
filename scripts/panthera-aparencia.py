#!/usr/bin/env python3
# /usr/bin/panthera-aparencia - Aparência Panthera
# Troca o tema GTK e o papel de parede, com validacao antes de aplicar.
# So GTK3 + stdlib. Nada e aplicado sem antes passar na validacao: tema que
# nao compila e papel que nao existe sao recusados com o motivo na tela, e o
# detalhe vai para /var/log/panthera-aparencia.log. Tema de terceiro so entra
# se passar no panthera-theme-check (I9): o validador rejeita codigo no tema.
# Teste: python3 -m py_compile + python3 panthera-aparencia.py --help (sem display)
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

import json
import os
import shutil
import subprocess
import sys
import time
import zipfile

LOG = "/var/log/panthera-aparencia.log"
DIR_TEMAS = "/usr/share/themes"
DIR_PAPEIS = "/usr/share/backgrounds/panthera"
VALIDADOR = "/usr/bin/panthera-theme-check.py"


def registrar(linha):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%SZ"), linha))
    except OSError:
        pass


def css_compila(caminho):
    """True quando o GTK3 carrega o CSS sem erro. E o que impede tema quebrado."""
    try:
        from gi.repository import Gtk as _Gtk
        _Gtk.CssProvider().load_from_path(caminho)
        return True
    except Exception as e:
        registrar("css invalido %s: %s" % (caminho, e))
        return False


def descobrir_temas(diretorio=None):
    """Temas instalados que funcionam de verdade: com index.theme, gtk.css que
    compila e pasta gtk-3.0. O que nao passa e listado como quebrado, nao some
    em silencio."""
    diretorio = diretorio or DIR_TEMAS
    bons, quebrados = [], []
    try:
        nomes = sorted(os.listdir(diretorio))
    except OSError:
        return bons, quebrados
    for nome in nomes:
        base = os.path.join(diretorio, nome)
        css = os.path.join(base, "gtk-3.0", "gtk.css")
        indice = os.path.join(base, "index.theme")
        if not os.path.isfile(css):
            continue
        if not os.path.isfile(indice):
            quebrados.append((nome, "sem index.theme: o GTK ignora o tema"))
        elif not css_compila(css):
            quebrados.append((nome, "gtk.css nao compila no GTK3"))
        else:
            bons.append(nome)
    return bons, quebrados


def descobrir_papeis(diretorio=None):
    """Imagens usaveis como papel de parede, por extensao e tamanho minimo."""
    diretorio = diretorio or DIR_PAPEIS
    try:
        arquivos = sorted(os.listdir(diretorio))
    except OSError:
        return []
    return [os.path.join(diretorio, f) for f in arquivos
            if f.lower().endswith((".png", ".jpg", ".jpeg"))]


def validar_pacote_tema(caminho_zip):
    """Roda o validador oficial (I9). Devolve (ok, mensagem)."""
    if not os.path.isfile(caminho_zip):
        return False, "arquivo nao encontrado"
    if not zipfile.is_zipfile(caminho_zip):
        return False, "nao e um arquivo .panthera-theme valido"
    try:
        r = subprocess.run([sys.executable, VALIDADOR, caminho_zip],
                           capture_output=True, text=True, timeout=30)
        saida = (r.stdout + r.stderr).strip().splitlines()
        ultima = saida[-1] if saida else ""
        if r.returncode == 0 and "OK" in ultima.upper():
            return True, ultima or "tema aceito"
        return False, ultima or "tema rejeitado"
    except (OSError, subprocess.TimeoutExpired) as e:
        registrar("validador falhou: %s" % e)
        return False, "nao consegui validar (%s)" % e


def ler_conf_atual():
    """Tema e papel em uso agora, lendo os arquivos que o hook 0200 escreve."""
    casa = os.path.expanduser("~")
    tema, papel = None, None
    ini = os.path.join(casa, ".config", "gtk-3.0", "settings.ini")
    try:
        with open(ini, encoding="utf-8") as f:
            for linha in f:
                if linha.strip().startswith("gtk-theme-name"):
                    tema = linha.split("=", 1)[1].strip()
    except OSError:
        pass
    xml = os.path.join(casa, ".config", "xfce4", "xfconf",
                       "xfce-perchannel-xml", "xfce4-desktop.xml")
    try:
        import xml.dom.minidom
        dom = xml.dom.minidom.parse(xml)
        for prop in dom.getElementsByTagName("property"):
            if prop.getAttribute("name") == "last-image" and prop.hasAttribute("value"):
                papel = prop.getAttribute("value")
                break
    except Exception as e:
        registrar("ler papel atual falhou: %s" % e)
    return tema, papel


def tem_xfconf():
    return shutil.which("xfconf-query") is not None


def aplicar_tema(nome):
    """Aplica agora (xfconf, quando ha sessao XFCE) e grava para persistir."""
    casa = os.path.expanduser("~")
    ok = True
    if tem_xfconf():
        for canal, prop, valor in (("xsettings", "/Net/ThemeName", nome),
                                   ("xsettings", "/Net/IconThemeName", nome)):
            r = subprocess.run(["xfconf-query", "-c", canal, "-p", prop, "-s", valor],
                               capture_output=True, timeout=15)
            if r.returncode != 0:
                ok = False
    conf = os.path.join(casa, ".config", "gtk-3.0")
    try:
        os.makedirs(conf, exist_ok=True)
        with open(os.path.join(conf, "settings.ini"), "w", encoding="utf-8") as f:
            f.write("[Settings]\ngtk-theme-name=%s\ngtk-icon-theme-name=%s\ngtk-font-name=Inter 10\n"
                    % (nome, nome))
    except OSError as e:
        registrar("persistir tema falhou: %s" % e)
        ok = False
    return ok


def aplicar_papel(caminho):
    """Aplica agora (xfconf) e grava o xml para persistir."""
    if not os.path.isfile(caminho):
        return False
    casa = os.path.expanduser("~")
    ok = True
    if tem_xfconf():
        for prop in ("/backdrop/screen0/monitor0/workspace0/last-image",
                     "/backdrop/screen0/workspace0/last-image"):
            r = subprocess.run(["xfconf-query", "-c", "xfce4-desktop", "-p", prop,
                                "-s", caminho], capture_output=True, timeout=15)
            if r.returncode == 0:
                break
        else:
            ok = False
    destino = os.path.join(casa, ".config", "xfce4", "xfconf",
                           "xfce-perchannel-xml", "xfce4-desktop.xml")
    try:
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        with open(destino, "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                    '<channel name="xfce4-desktop" version="1.0">\n'
                    '  <property name="backdrop" type="empty">\n'
                    '    <property name="screen0" type="empty">\n'
                    '      <property name="monitor0" type="empty">\n'
                    '        <property name="workspace0" type="empty">\n'
                    '          <property name="color-style" type="int" value="0"/>\n'
                    '          <property name="color1" type="string" value="#0B111C"/>\n'
                    '          <property name="image-style" type="int" value="2"/>\n'
                    '          <property name="last-image" type="string" value="%s"/>\n'
                    '        </property>\n'
                    '      </property>\n'
                    '    </property>\n'
                    '  </property>\n'
                    '</channel>\n' % caminho)
    except OSError as e:
        registrar("persistir papel falhou: %s" % e)
        ok = False
    return ok


if "--help" in sys.argv or "-h" in sys.argv:
    print("Aparência Panthera: troca o tema e o papel de parede, validando antes.")
    raise SystemExit(0)


class Aparencia(Gtk.Window):
    def __init__(self):
        super().__init__(title="Aparência Panthera")
        self.set_default_size(680, 560)
        self.tema_escolhido, self.papel_escolhido = None, None
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        v.set_border_width(14)
        self.add(v)

        titulo = Gtk.Label()
        titulo.set_markup("<b>Aparência Panthera</b>")
        titulo.set_xalign(0)
        v.pack_start(titulo, False, False, 0)

        tema_atual, papel_atual = ler_conf_atual()
        estado = Gtk.Label(label="Em uso agora: tema %s | papel %s" %
                           (tema_atual or "?", os.path.basename(papel_atual) if papel_atual else "?"))
        estado.set_xalign(0)
        estado.set_line_wrap(True)
        v.pack_start(estado, False, False, 0)

        v.pack_start(self._secao_tema(), True, True, 0)
        v.pack_start(self._secao_papel(), True, True, 0)

        rodape = Gtk.Box(spacing=8)
        aplicar = Gtk.Button(label="Aplicar")
        aplicar.connect("clicked", lambda _w: self.safe(self._aplicar))
        rodape.pack_start(aplicar, False, False, 0)
        instalar = Gtk.Button(label="Instalar tema de arquivo...")
        instalar.connect("clicked", lambda _w: self.safe(self._instalar_arquivo))
        rodape.pack_start(instalar, False, False, 0)
        v.pack_start(rodape, False, False, 0)

    def safe(self, acao, *args):
        try:
            return acao(*args)
        except Exception as e:
            registrar("erro tratado: %s" % e)
            self._aviso("Algo deu errado, mas nada foi aplicado pela metade.\nDetalhe em %s" % LOG)
            return None

    def _secao_tema(self):
        caixa = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        rotulo = Gtk.Label()
        rotulo.set_markup("<b>Tema</b> — só aparece o que funciona de verdade")
        rotulo.set_xalign(0)
        caixa.pack_start(rotulo, False, False, 0)
        bons, quebrados = descobrir_temas()
        if not bons and not quebrados:
            caixa.pack_start(Gtk.Label(label="Nenhum tema encontrado em %s" % DIR_TEMAS), False, False, 0)
            return caixa
        primeiro = None
        for nome in bons:
            botao = Gtk.RadioButton(group=primeiro) if primeiro else Gtk.RadioButton()
            if primeiro is None:
                primeiro = botao
            botao.connect("toggled", lambda _w, n=nome: self.safe(self._marca_tema, n))
            linha = Gtk.Box(spacing=8)
            linha.pack_start(botao, False, False, 0)
            texto = Gtk.Label(label=nome)
            texto.set_xalign(0)
            linha.pack_start(texto, True, True, 0)
            caixa.pack_start(linha, False, False, 0)
            if nome == "Panthera":
                botao.set_active(True)
                self.tema_escolhido = nome
        for nome, motivo in quebrados:
            linha = Gtk.Label(label="%s — indisponível: %s" % (nome, motivo))
            linha.set_xalign(0)
            linha.set_line_wrap(True)
            linha.get_style_context().add_class("dim-label")
            caixa.pack_start(linha, False, False, 0)
        return caixa

    def _marca_tema(self, _botao, nome):
        self.tema_escolhido = nome

    def _secao_papel(self):
        caixa = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        rotulo = Gtk.Label()
        rotulo.set_markup("<b>Papel de parede</b>")
        rotulo.set_xalign(0)
        caixa.pack_start(rotulo, False, False, 0)
        papeis = descobrir_papeis()
        if not papeis:
            caixa.pack_start(Gtk.Label(label="Nenhuma imagem em %s" % DIR_PAPEIS), False, False, 0)
            return caixa
        primeiro = None
        for caminho in papeis:
            botao = Gtk.RadioButton(group=primeiro) if primeiro else Gtk.RadioButton()
            if primeiro is None:
                primeiro = botao
                self.papel_escolhido = caminho
            botao.connect("toggled", lambda _w, c=caminho: self.safe(self._marca_papel, c))
            linha = Gtk.Box(spacing=8)
            linha.pack_start(botao, False, False, 0)
            texto = Gtk.Label(label=os.path.basename(caminho))
            texto.set_xalign(0)
            linha.pack_start(texto, True, True, 0)
            caixa.pack_start(linha, False, False, 0)
        return caixa

    def _marca_papel(self, _botao, caminho):
        self.papel_escolhido = caminho

    def _aplicar(self):
        mensagens = []
        if self.tema_escolhido:
            if aplicar_tema(self.tema_escolhido):
                mensagens.append("Tema %s aplicado." % self.tema_escolhido)
            else:
                mensagens.append("Tema %s gravado, mas pode precisar sair e entrar." % self.tema_escolhido)
        if self.papel_escolhido:
            if aplicar_papel(self.papel_escolhido):
                mensagens.append("Papel de parede aplicado.")
            else:
                mensagens.append("Papel gravado, mas pode precisar sair e entrar.")
        self._aviso("\n".join(mensagens) if mensagens else "Nada para aplicar.")

    def _instalar_arquivo(self):
        dialogo = Gtk.FileChooserDialog(
            title="Escolher tema (.panthera-theme)", parent=self,
            action=Gtk.FileChooserAction.OPEN)
        dialogo.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                            Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        filtro = Gtk.FileFilter()
        filtro.set_name("Temas Panthera")
        filtro.add_pattern("*.panthera-theme")
        dialogo.add_filter(filtro)
        if dialogo.run() != Gtk.ResponseType.OK:
            dialogo.destroy()
            return
        caminho = dialogo.get_filename()
        dialogo.destroy()
        ok, mensagem = validar_pacote_tema(caminho)
        registrar("validar %s: %s" % (caminho, mensagem))
        if ok:
            self._aviso("Tema aceito pelo validador.\n%s\n\nPara usar, extraia para um novo tema em %s." % (mensagem, DIR_TEMAS))
        else:
            self._aviso("Tema REJEITADO e não instalado.\n%s" % mensagem)

    def _aviso(self, texto):
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.INFO,
                              buttons=Gtk.ButtonsType.CLOSE, text=texto)
        d.run()
        d.destroy()


if __name__ == "__main__":
    janela = Aparencia()
    janela.connect("destroy", Gtk.main_quit)
    janela.show_all()
    Gtk.main()
