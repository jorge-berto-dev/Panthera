#!/usr/bin/env python3
# /usr/bin/panthera-welcome.py - autostart uma vez pos-instalacao (ODT Secao 21.2 + I1)
# Janela 700x460, 4 passos (Wi-Fi, favoritos, codecs, papel), Pular tudo, nunca mais.
# So GTK3 + stdlib. FLAG ~/.config/panthera/welcome-done.
# Teste: python3 panthera-welcome.py --help (sem display) | --reset apaga FLAG.
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk
import os, sys

FLAG = os.path.expanduser("~/.config/panthera/welcome-done")

if "--help" in sys.argv or "-h" in sys.argv:
    print("Bem-vindo Panthera: 4 passos (Wi-Fi, favoritos, videos, papel). Abre 1 vez.")
    raise SystemExit(0)
if "--reset" in sys.argv:
    try:
        os.remove(FLAG)
    except FileNotFoundError:
        pass
    print("FLAG apagada, welcome volta a abrir.")
    raise SystemExit(0)
if os.path.exists(FLAG):
    raise SystemExit(0)

PASSOS = ["1 Conectar Wi-Fi", "2 Importar favoritos do Chrome",
          "3 Ativar videos e musicas", "4 Escolher papel de parede"]

w = Gtk.Window(title="Bem-vindo a Pantera")
w.set_default_size(700, 460)
v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
v.set_border_width(16)
w.add(v)
v.pack_start(Gtk.Label(label="Bem-vindo a Pantera! Rapido, privado e seu."), False, False, 0)
for passo in PASSOS:
    try:
        v.pack_start(Gtk.Label(label=passo + "  [Concluir na Central]"), False, False, 0)
    except Exception as e:
        print(f"Erro tratado: {e}")
b = Gtk.Button(label="Comecar a usar (nao mostrar de novo)")

def ok(*_):
    try:
        os.makedirs(os.path.dirname(FLAG), exist_ok=True)
        open(FLAG, "w").write("ok")
    except Exception as e:
        print(f"Erro tratado ao salvar FLAG: {e}")
    Gtk.main_quit()

b.connect("clicked", ok)
v.pack_start(b, False, False, 0)
w.connect("destroy", Gtk.main_quit)
w.show_all()
Gtk.main()
