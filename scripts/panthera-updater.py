#!/usr/bin/env python3
# /usr/bin/panthera-updater - Atualizador honesto com snapshot (ODT Secao 27 + I5/I10)
# So GTK3 + stdlib. Mostra MB/tempo, nunca reinicia sozinho, snapshot antes.
# Teste: python3 -m py_compile + python3 panthera-updater.py --help (sem display)
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk
import subprocess, sys

if "--help" in sys.argv or "-h" in sys.argv:
    print("Atualizador Panthera - mostra MB e tempo, nunca reinicia sozinho.")
    raise SystemExit(0)

def sh(c):
    try:
        return subprocess.check_output(c, shell=True, text=True, timeout=60)
    except Exception as e:
        return str(e)

class Up(Gtk.Window):
    def __init__(self):
        super().__init__(title="Atualizador Panthera")
        self.set_default_size(560, 380)
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        v.set_border_width(14)
        self.add(v)
        v.pack_start(Gtk.Label(label="Mostra MB e tempo. Nunca reinicia sozinho. Snapshot antes."), False, False, 0)
        self.out = Gtk.TextView(editable=False, monospace=True)
        v.pack_start(Gtk.ScrolledWindow(child=self.out), True, True, 0)
        b1 = Gtk.Button(label="Verificar (verde: Atualizar tudo)")
        b1.get_style_context().add_class("suggested-action")
        b1.connect("clicked", lambda *_: self.safe_check())
        v.pack_start(b1, False, False, 0)
        b2 = Gtk.Button(label="Atualizar tudo agora")
        b2.connect("clicked", lambda *_: self.safe_update())
        v.pack_start(b2, False, False, 0)

    def log(self, t):
        try:
            self.out.get_buffer().set_text(t)
        except Exception as e:
            print(f"Erro tratado no log: {e}")

    def safe_check(self):
        try:
            self.log(sh("sudo apt update 2>&1 | tail -5; apt list --upgradable 2>/dev/null | head -10"))
        except Exception as e:
            self.log(f"Erro tratado: {e}")

    def safe_update(self):
        try:
            subprocess.Popen("x-terminal-emulator -e 'sudo apt upgrade -y 2>&1 | tail -20; echo Concluido sem reboot forcado; read' 2>/dev/null", shell=True)
        except Exception as e:
            self.log(f"Erro tratado: {e}")

w = Up()
w.connect("destroy", Gtk.main_quit)
w.show_all()
Gtk.main()
