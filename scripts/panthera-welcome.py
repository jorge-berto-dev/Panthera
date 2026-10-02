#!/usr/bin/env python3
# /usr/bin/panthera-welcome.py - autostart uma vez pos-instalacao (ODT Secao 21.2 + I1)
# Janela 700x520: 4 passos + escolha do Kit. Pular tudo, nunca mais.
# So GTK3 + stdlib + /usr/lib/panthera/catalogo.py. FLAG ~/.config/panthera/welcome-done
# Teste: --help (sem display) | --reset apaga FLAG | --meus-kits lista no terminal
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

import os
import shlex
import subprocess
import sys
import time

sys.path.insert(0, "/usr/lib/panthera")

FLAG = os.path.expanduser("~/.config/panthera/welcome-done")
LOG = "/var/log/panthera-welcome.log"
PASSOS = ["1 Conectar Wi-Fi", "2 Importar favoritos do navegador",
          "3 Ativar videos e musicas", "4 Escolher papel de parede"]


def registrar(linha):
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


# --help antes de qualquer import pesado: e o teste de DoD, roda sem display.
if "--help" in sys.argv or "-h" in sys.argv:
    print("Bem-vindo Panthera: 4 passos e escolha do Kit. Abre 1 vez so.")
    raise SystemExit(0)
if "--reset" in sys.argv:
    try:
        os.remove(FLAG)
    except FileNotFoundError:
        pass
    print("FLAG apagada, welcome volta a abrir.")
    raise SystemExit(0)

# O FLAG vem antes do catalogo: quem ja respondeu a boas-vindas nao deve
# depender do catalogo instalado para sair com codigo 0 (teste DoD 7).
if os.path.exists(FLAG):
    raise SystemExit(0)

# O catalogo entra depois dos atalhos: --help/--reset/--meus-kits sao DoD e
# nao podem depender de nada instalado.
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

if "--meus-kits" in sys.argv:
    cat = catalogo.carregar()
    for chave, kit in cat["kits"].items():
        d = catalogo.resumo(cat, chave)
        print("%-12s %-24s %s" % (chave, d["nome"], d["desc"]))
    raise SystemExit(0)


class BoasVindas(Gtk.Window):
    def __init__(self):
        super().__init__(title="Bem-vindo a Panthera")
        self.set_default_size(700, 520)
        try:
            self.cat = catalogo.carregar()
        except catalogo.CatalogoErro as e:
            registrar("catalogo erro: %s" % e)
            self.cat = None

        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        v.set_border_width(16)
        self.add(v)

        titulo = Gtk.Label()
        titulo.set_markup("<span size='xx-large' weight='bold'>Bem-vindo a Panthera</span>")
        v.pack_start(titulo, False, False, 0)

        sub = Gtk.Label(label="Rápido, privado e seu.")
        v.pack_start(sub, False, False, 0)

        for passo in PASSOS:
            try:
                v.pack_start(Gtk.Label(label=passo + "  [Concluir na Central]", xalign=0), False, False, 0)
            except Exception as e:
                registrar("passo %s: %s" % (passo, e))

        v.pack_start(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL), False, False, 6)

        pergunta = Gtk.Label()
        pergunta.set_markup("<b>O que você quer usar a Panthera para?</b>")
        pergunta.set_xalign(0)
        v.pack_start(pergunta, False, False, 0)

        aviso = Gtk.Label(label="Escolher um Kit instala o essencial de uma vez. Você pode mudar tudo depois na Loja.")
        aviso.set_xalign(0)
        aviso.set_line_wrap(True)
        v.pack_start(aviso, False, False, 0)

        self.botoes = {}
        self.escolhido = None
        if self.cat:
            self._pagina_kits(v)
        else:
            v.pack_start(Gtk.Label(label="Não consegui ler o catálogo. Os Kits estão na Loja."), False, False, 0)

        rodape = Gtk.Box(spacing=8)
        instalar = Gtk.Button(label="Instalar kit escolhido")
        instalar.connect("clicked", lambda _w: self.safe(self._instalar))
        pular = Gtk.Button(label="Agora não")
        pular.connect("clicked", lambda _w: self.safe(self._sair, False))
        rodape.pack_start(instalar, False, False, 0)
        rodape.pack_start(pular, False, False, 0)
        v.pack_start(rodape, False, False, 0)

        começar = Gtk.Button(label="Começar a usar (não mostrar de novo)")
        começar.connect("clicked", lambda _w: self.safe(self._sair, False))
        v.pack_start(começar, False, False, 0)

    def safe(self, acao, *args):
        """Todo botao passa por aqui. Nenhum callback pode levantar excecao e
        mostrar traceback para quem esta usando (Secao 20.6)."""
        try:
            return acao(*args)
        except Exception as e:
            registrar("erro tratado em %s: %s" % (getattr(acao, "__name__", acao), e))
            self._aviso("Algo deu errado, mas o sistema continua funcionando.\nO detalhe esta em %s" % LOG)
            return None

    def _pagina_kits(self, v):
        grade = Gtk.Grid(column_spacing=8, row_spacing=4)
        grade.set_border_width(6)
        primeiro_botao = None
        self.radios = []
        for linha, (chave, kit) in enumerate(sorted(self.cat["kits"].items(),
                                                    key=lambda kv: (not kv[1].get("padrao"), kv[0]))):
            try:
                d = catalogo.resumo(self.cat, chave)
            except catalogo.CatalogoErro as e:
                registrar("kit %s: %s" % (chave, e))
                continue
            # Todos os botoes pertencem ao mesmo grupo: sem isso seriam 6 radios
            # independentes e o usuario poderia marcar varios. Neste PyGObject
            # o jeito que funciona e Gtk.RadioButton(group=...); os atalhos
            # new_with_label/new_with_label_from_widget exigem o label como
            # segundo argumento e nao aceitam None.
            if primeiro_botao is None:
                botao = Gtk.RadioButton()
                primeiro_botao = botao
            else:
                botao = Gtk.RadioButton(group=primeiro_botao)
            botao.connect("toggled", lambda _w, c=chave: self.safe(self._selecionou, _w, c))
            self.radios.append((chave, botao))
            grade.attach(botao, 0, linha, 1, 1)

            detalhe = "%s  —  %s" % (d["nome"], d["desc"])
            if d["instalado"]:
                detalhe += "  (já instalado)"
            elif d["download"]:
                detalhe += "  (%.0f MB)" % (d["download"] / 1024 / 1024)
            grade.attach(Gtk.Label(label=detalhe, xalign=0), 1, linha, 1, 1)
            if kit.get("padrao"):
                botao.set_active(True)
                # Nao confiar no sinal "toggled" para o padrao: set_active marca
                # o botao mas o sinal nem sempre vem, e o kit padrao ficava
                # desmarcado. Atribuir direto e deterministico.
                self.escolhido = chave
        v.pack_start(grade, True, True, 0)

    def _selecionou(self, botao, chave):
        if botao.get_active():
            self.escolhido = chave

    def _instalar(self):
        if not self.escolhido:
            self._aviso("Escolha um kit primeiro, ou clique em 'Agora não'.")
            return
        try:
            so_offline, etapas = catalogo.comandos(self.cat, self.escolhido)
        except catalogo.CatalogoErro as e:
            self._aviso("Não posso instalar este kit:\n%s" % e)
            return
        if not etapas:
            self._aviso("Este kit não tem nada a instalar.")
            return
        destino = "/tmp/panthera-kit-%s.sh" % self.escolhido
        with open(destino, "w", encoding="utf-8") as f:
            f.write("#!/bin/bash\nset -euo pipefail\nexport DEBIAN_FRONTEND=noninteractive\n\n")
            for _, argv in etapas:
                f.write("%s\n\n" % " ".join(shlex.quote(a) for a in argv))
        os.chmod(destino, 0o755)
        registrar("instalou kit %s via %s" % (self.escolhido, destino))

        terminal = qual_binario("x-terminal-emulator")
        bash = qual_binario("bash") or "/bin/bash"
        if not terminal:
            self._aviso("Não achei um terminal. Rode:\n\n  sudo %s %s" % (bash, destino))
            return
        cmd = "sudo -E %s %s; echo; read -p '--- Panthera: terminou. Enter para fechar ---' _" % (bash, destino)
        try:
            subprocess.Popen([terminal, "-e", cmd], start_new_session=True)
        except OSError as e:
            registrar("Popen falhou: %s" % e)
            self._aviso("Não consegui abrir o terminal.\n%s" % e)
            return
        self._sair(True)

    def _sair(self, instalou):
        try:
            os.makedirs(os.path.dirname(FLAG), exist_ok=True)
            open(FLAG, "w").write("ok")
        except OSError as e:
            registrar("FLAG: %s" % e)
        Gtk.main_quit()

    def _aviso(self, texto):
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.INFO,
                              buttons=Gtk.ButtonsType.CLOSE, text=texto)
        d.run()
        d.destroy()


if __name__ == "__main__":
    janela = BoasVindas()
    janela.connect("destroy", Gtk.main_quit)
    janela.show_all()
    Gtk.main()
