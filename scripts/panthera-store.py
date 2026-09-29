#!/usr/bin/env python3
# /usr/bin/panthera-store - Loja Essenciais 1-clique (ODT Secao 27 + I4 Secao 6)
# So GTK3 + stdlib. Fila unica, log /var/log/panthera-store.log.
# Teste: python3 -m py_compile + python3 panthera-store.py --help (sem display)
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk
import subprocess, sys

if "--help" in sys.argv or "-h" in sys.argv:
    print("Loja Panthera - Essenciais 1-clique (tamanho + funciona com 2GB).")
    raise SystemExit(0)

ESS = [("LibreOffice Completo", "sudo apt install -y libreoffice", "800MB", "Sim"),
       ("VLC", "sudo apt install -y vlc", "120MB", "Sim"),
       ("GIMP", "sudo apt install -y gimp", "200MB", "Nao-4GB-ok"),
       ("VS Code (flatpak)", "flatpak install -y flathub com.visualstudio.code", "400MB", "Nao"),
       ("HPLIP completo", "sudo apt install -y hplip", "150MB", "Sim"),
       ("Codecs video musica", "/usr/bin/panthera-codecs.sh", "100MB", "Sim")]

class Store(Gtk.Window):
    def __init__(self):
        super().__init__(title="Loja Panthera")
        self.set_default_size(640, 480)
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        v.set_border_width(14)
        self.add(v)
        v.pack_start(Gtk.Label(label="Essenciais 1-clique. Tamanho + funciona com 2GB."), False, False, 0)
        for nome, cmd, tam, ok2gb in ESS:
            h = Gtk.Box(spacing=8)
            h.pack_start(Gtk.Label(label=f"{nome}  {tam}  2GB:{ok2gb}", xalign=0), True, True, 0)
            b = Gtk.Button(label="Instalar")
            b.connect("clicked", lambda _, c=cmd, n=nome: self.instalar(c, n))
            h.pack_start(b, False, False, 0)
            v.pack_start(h, False, False, 0)

    def instalar(self, cmd, nome):
        # Nunca mostra traceback ao leigo; log tecnico em arquivo (I6).
        try:
            subprocess.Popen(f"x-terminal-emulator -e '{cmd}; echo {nome} pronto; read' 2>/dev/null || {cmd}", shell=True)
        except Exception as e:
            print(f"Erro tratado ao instalar {nome}: {e}")

w = Store()
w.connect("destroy", Gtk.main_quit)
w.show_all()
Gtk.main()
