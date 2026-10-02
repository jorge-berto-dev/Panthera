#!/usr/bin/env python3
# /usr/bin/panthera-store - Catalogo Panthera (ODT Secao 27 + I4)
# So GTK3 + stdlib + /usr/lib/panthera/catalogo.py
#
# Mudancas em relacao a versao anterior:
#  - le kits/catalogo.json (JSON), nao lista Python embutida: novo Kit sem rebuild
#  - tamanho e RAM MEDIDOS no apt, nunca digitados (o codigo antigo tinha "800MB" fixo)
#  - uma transacao apt por kit, nao um apt por pacote
#  - recusa pacotes da lista de recusados, sempre com o motivo visivel
#  - mostra se o kit sai do pool offline da ISO (funciona sem internet)
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

import os
import shlex
import subprocess
import sys
import time

sys.path.insert(0, "/usr/lib/panthera")

LOG = "/var/log/panthera-store.log"
MARCADOR = "/tmp/panthera-kit-ok"
TERMINAL = "x-terminal-emulator"


def registrar(linha):
    """Nunca mostra traceback ao leigo; log tecnico em arquivo (I6)."""
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), linha))
    except OSError:
        pass


def qual_binario(nome):
    for pasta in os.environ.get("PATH", "").split(os.pathsep):
        caminho = os.path.join(pasta, nome)
        if os.access(caminho, os.X_OK):
            return caminho
    return None


# O --help vem ANTES do catalogo de proposito: e o teste de DoD (Secao 26.1),
# roda sem display e sem o catalogo instalado.
if "--help" in sys.argv or "-h" in sys.argv:
    print("Loja Panthera - catalogo verificado. Kits e o que recusamos.")
    print("Tamanho e RAM medidos no APT. Um Kit = uma transacao so.")
    raise SystemExit(0)

import catalogo  # noqa: E402  (depende do bloco --help/--reset/FLAG)

try:
    import catalogo
except ImportError:
    # Fora do sistema (rodando do repo, sem /usr/lib/panthera), carrega o arquivo
    # irmao. Sem isso os testes so veem --help e nunca exercitam o codigo real.
    import importlib.util
    _aqui = os.path.join(os.path.dirname(os.path.abspath(__file__)), "panthera-catalogo.py")
    _spec = importlib.util.spec_from_file_location("catalogo", _aqui)
    catalogo = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(catalogo)


class Loja(Gtk.Window):
    def __init__(self):
        super().__init__(title="Loja Panthera")
        self.set_default_size(720, 640)
        self._construir()

    def safe(self, acao, *args):
        """Todo botao passa por aqui. Nenhum callback pode levantar excecao e
        mostrar traceback para quem esta usando (Secao 20.6)."""
        try:
            return acao(*args)
        except Exception as e:
            registrar("erro tratado em %s: %s" % (getattr(acao, "__name__", acao), e))
            self._aviso("Algo deu errado, mas o sistema continua funcionando.\nO detalhe esta em %s" % LOG)
            return None

    # ---------- interface ----------
    def _construir(self):
        for filho in list(self.get_children()):
            self.remove(filho)
        try:
            self.cat = catalogo.carregar()
            erro = None
        except catalogo.CatalogoErro as e:
            self.cat, erro = None, str(e)
            registrar("catalogo erro: %s" % e)

        raiz = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        raiz.set_border_width(14)
        self.add(raiz)

        titulo = Gtk.Label()
        titulo.set_markup("<b>Loja Panthera</b>")
        titulo.set_xalign(0)
        raiz.pack_start(titulo, False, False, 0)

        if erro:
            aviso = Gtk.Label(label="Nao consegui ler o catalogo do sistema.\n%s\nVeja %s" % (erro, LOG))
            aviso.set_xalign(0)
            aviso.set_line_wrap(True)
            raiz.pack_start(aviso, False, False, 0)
            return

        sub = Gtk.Label(
            label="Tudo vem do Debian ou do Flathub. Nada de repositorio de terceiro.\n"
                  "O tamanho e a memoria necessaria sao medidos agora, nao estimados."
        )
        sub.set_xalign(0)
        sub.set_line_wrap(True)
        raiz.pack_start(sub, False, False, 0)

        abas = Gtk.Notebook()
        raiz.pack_start(abas, True, True, 0)
        abas.append_page(self._pagina_kits(), Gtk.Label(label="Kits"))
        abas.append_page(self._pagina_recusados(), Gtk.Label(label="O que recusamos"))

    def _pagina_kits(self):
        caixa = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        caixa.set_border_width(12)
        ordem = sorted(self.cat["kits"].items(), key=lambda kv: (not kv[1].get("padrao"), kv[0]))
        for chave, kit in ordem:
            try:
                dados = catalogo.resumo(self.cat, chave)
            except catalogo.CatalogoErro as e:
                registrar("kit %s: %s" % (chave, e))
                continue
            caixa.pack_start(self._linha_kit(chave, dados, kit.get("padrao", False)), False, False, 0)
        return caixa

    def _linha_kit(self, chave, d, padrao):
        linha = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        linha.set_border_width(8)

        cabecalho = Gtk.Box(spacing=8)
        nome = Gtk.Label()
        nome.set_markup("<b>%s</b>%s" % (d["nome"], "  (recomendado)" if padrao else ""))
        nome.set_xalign(0)
        cabecalho.pack_start(nome, True, True, 0)

        if d["instalado"]:
            cabecalho.pack_start(Gtk.Label(label="ja instalado"), False, False, 0)
        else:
            botao = Gtk.Button(label="Instalar")
            botao.connect("clicked", lambda _w, c=chave: self.safe(self.confirmar, c))
            cabecalho.pack_start(botao, False, False, 0)
        linha.pack_start(cabecalho, False, False, 0)

        descricao = Gtk.Label(label=d["desc"])
        descricao.set_xalign(0)
        descricao.set_line_wrap(True)
        linha.pack_start(descricao, False, False, 0)

        medido = Gtk.Label(label=" | ".join(self._numeros(chave, d)))
        medido.set_xalign(0)
        medido.set_line_wrap(True)
        medido.get_style_context().add_class("dim-label")
        linha.pack_start(medido, False, False, 0)
        return linha

    def _numeros(self, chave, d):
        """Texto dos numeros medidos. '?' quando o apt nao sabe responder."""
        partes = []
        if d["instalado"]:
            partes.append("ja instalado")
        elif d["download"]:
            partes.append("%.0f MB para baixar" % (d["download"] / 1024 / 1024))
        else:
            partes.append("tamanho nao medido")
        if d["disco"]:
            partes.append("%.1f GB no disco" % (d["disco"] / 1024 ** 3))
        try:
            so_offline, etapas = catalogo.comandos(self.cat, chave)
            if etapas and so_offline:
                partes.append("instalavel SEM INTERNET")
            elif any(catalogo.pool_disponivel(p) for p in d["pacotes"]):
                partes.append("parte vem na propria ISO")
        except catalogo.CatalogoErro as e:
            registrar("medicao %s: %s" % (chave, e))
            partes.append("nao medido")
        for _, item in d["itens"]:
            need = item.get("ram_min_mb", 0)
            if need > d["ram_livre_mb"]:
                partes.append("atencao: %s quer %dMB e voce tem %dMB livres"
                              % (item["nome"], need, d["ram_livre_mb"]))
        return partes

    def _pagina_recusados(self):
        caixa = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        caixa.set_border_width(12)
        titulo = Gtk.Label(
            label="A Panthera nao instala estes pacotes, e o motivo fica visivel aqui.\n"
                  "Nao e lista secreta: e a garantia do catalogo."
        )
        titulo.set_xalign(0)
        titulo.set_line_wrap(True)
        caixa.pack_start(titulo, False, False, 0)
        for pacote, motivo in sorted(self.cat["recusados"].items()):
            linha = Gtk.Box(spacing=8)
            nome = Gtk.Label(label=pacote)
            nome.set_xalign(0)
            nome.set_width_chars(24)
            linha.pack_start(nome, False, False, 0)
            texto = Gtk.Label(label=motivo)
            texto.set_xalign(0)
            texto.set_line_wrap(True)
            linha.pack_start(texto, True, True, 0)
            caixa.pack_start(linha, False, False, 0)
        return caixa

    # ---------- instalacao ----------
    def confirmar(self, chave):
        # Primeiro a confirmacao, so depois a instalacao.

        try:
            so_offline, etapas = catalogo.comandos(self.cat, chave)
        except catalogo.CatalogoErro as e:
            self._aviso("Nao posso instalar este kit:\n%s" % e)
            return
        if not etapas:
            self._aviso("Este kit nao tem nada a instalar.")
            return

        d = catalogo.resumo(self.cat, chave)
        linhas = []
        for rotulo, argv in etapas:
            linhas.append("%s:\n    %s" % (rotulo, " ".join(shlex.quote(a) for a in argv)))
        linhas.append("")
        linhas.append("Instala sem internet, direto do pool da ISO." if so_offline
                      else "Precisa de internet durante a instalacao.")
        linhas.append("Se algo falhar, o apt desfaz: nada fica pela metade.")

        dialogo = Gtk.MessageDialog(
            transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL, text="Instalar o kit '%s'?" % d["nome"],
        )
        dialogo.format_secondary_text("\n".join(linhas))
        resposta = dialogo.run()
        dialogo.destroy()
        if resposta == Gtk.ResponseType.OK:
            self._rodar(chave, etapas)

    def _rodar(self, chave, etapas):
        """Escreve um script auditavel e roda com sudo num terminal.

        Script em arquivo em vez de 'x-terminal-emulator -e \"...\"': sem quoting
        fragil, e da para ler o que vai rodar antes de rodar.
        """
        if os.path.exists(MARCADOR):
            os.remove(MARCADOR)
        destino = "/tmp/panthera-kit-%s.sh" % chave
        with open(destino, "w", encoding="utf-8") as f:
            f.write("#!/bin/bash\nset -euo pipefail\n")
            f.write("export DEBIAN_FRONTEND=noninteractive\n\n")
            for rotulo, argv in etapas:
                f.write("echo '>>> %s'\n" % rotulo)
                f.write("%s\n\n" % " ".join(shlex.quote(a) for a in argv))
            f.write("touch %s\n" % MARCADOR)
        os.chmod(destino, 0o755)
        registrar("kit %s -> %s" % (chave, destino))

        bash = qual_binario("bash") or "/bin/bash"
        terminal = qual_binario(TERMINAL)
        if not terminal:
            self._aviso("Nao achei um terminal nesta sessao. Rode no terminal:\n\n  sudo %s %s"
                        % (bash, destino))
            return
        cmd = "sudo -E %s %s; echo; read -p '--- Panthera: terminou. Enter para fechar ---' _" % (bash, destino)
        try:
            subprocess.Popen([terminal, "-e", cmd], start_new_session=True)
        except OSError as e:
            registrar("Popen falhou: %s" % e)
            self._aviso("Nao consegui abrir o terminal.\n%s" % e)
            return
        self._esperar(chave)

    def _esperar(self, chave):
        """Acompanha o marcador sem travar a interface."""
        def tick():
            if not os.path.exists(MARCADOR):
                return True
            self._aviso("Kit '%s' pronto." % self.cat["kits"][chave]["nome"])
            self._construir()
            self.show_all()
            return False
        GLib.timeout_add(1500, tick)

    def _aviso(self, texto):
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.INFO,
                              buttons=Gtk.ButtonsType.CLOSE, text=texto)
        d.run()
        d.destroy()


if __name__ == "__main__":
    janela = Loja()
    janela.connect("destroy", Gtk.main_quit)
    janela.show_all()
    Gtk.main()
