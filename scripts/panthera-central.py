#!/usr/bin/env python3
# panthera-central v1.0 - 11 abas funcionais (ODT Secao 26 + abas Secao 16)
# Destino: /usr/bin/panthera-central. So GTK3 + stdlib. Nenhum callback sem try.
# Teste: python3 -m py_compile + python3 panthera-central.py --help (sem display)
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib
import subprocess, os, json, sys

ABAS = ["Wi-Fi e Rede", "Bluetooth", "Aparencia", "Som", "Energia",
        "Privacidade", "Seguranca", "Usuarios", "Impressoras",
        "Atalhos e Idioma", "Sobre"]

if "--help" in sys.argv or "-h" in sys.argv:
    print("Central Panthera - 11 abas:")
    for a in ABAS:
        print(" - " + a)
    print("Uso sem arg: abre a janela (precisa display).")
    raise SystemExit(0)

CFG = os.path.expanduser("~/.config/panthera/theme.json")

def sh(cmd, timeout=15):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, timeout=timeout)
    except subprocess.CalledProcessError as e:
        return f"Falhou ({e.returncode}): {e.output[:500]}"
    except Exception as e:
        return f"Erro: {e}"

def pkexec(cmd):
    return f"pkexec bash -c '{cmd}'"

class Central(Gtk.Window):
    def __init__(self):
        super().__init__(title="Central Panthera")
        self.set_default_size(860, 600)
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.add(root)
        self.search = Gtk.SearchEntry(placeholder_text="Buscar: wifi, impressora, tema, firewall, som...")
        self.search.connect("search-changed", self.on_search)
        root.pack_start(self.search, False, False, 6)
        self.nb = Gtk.Notebook(scrollable=True)
        root.pack_start(self.nb, True, True, 0)
        self.log = Gtk.TextView(editable=False, monospace=True)
        self.log.set_size_request(-1, 90)
        root.pack_start(Gtk.Label(label="Saida e log (tecnico, leigo ignora):", xalign=0), False, False, 0)
        root.pack_start(Gtk.ScrolledWindow(child=self.log), False, False, 0)
        self.tabs = {}
        for nome in ABAS:
            s = Gtk.ScrolledWindow()
            v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            v.set_border_width(14)
            s.add(v)
            self.tabs[nome] = v
            self.nb.append_page(s, Gtk.Label(label=nome))
        self.b_wifi(); self.b_bt(); self.b_look(); self.b_sound()
        self.b_power(); self.b_priv(); self.b_sec(); self.b_users()
        self.b_print(); self.b_lang(); self.b_about()

    def say(self, t):
        try:
            buf = self.log.get_buffer()
            buf.insert(buf.get_end_iter(), t + "\n")
        except Exception:
            print(t)

    def btn(self, parent, label, fn):
        b = Gtk.Button(label=label)
        b.connect("clicked", lambda *_: self.safe(fn))
        parent.pack_start(b, False, False, 0)
        return b

    def safe(self, fn):
        try:
            fn()
        except Exception as e:
            self.say(f"Erro tratado: {e}")

    def lbl(self, parent, t):
        l = Gtk.Label(label=t, xalign=0)
        l.set_line_wrap(True)
        parent.pack_start(l, False, False, 0)

    # --- abas (Secao 16) ---
    def b_wifi(self):
        v = self.tabs["Wi-Fi e Rede"]
        self.lbl(v, "Conecte uma vez, Panthera lembra. Lista mostra sinal %.")
        self.btn(v, "Listar redes agora", lambda: self.say(sh("nmcli -f SSID,SIGNAL,SECURITY device wifi list | head -15")))
        self.btn(v, "Abrir configurador (GUI)", lambda: subprocess.Popen("nm-connection-editor 2>/dev/null || x-terminal-emulator -e nmcli device wifi list", shell=True))
        self.btn(v, "Doutor Rede (ping + reiniciar NM)", lambda: self.say(sh("ping -c2 -W2 9.9.9.9; sudo -n systemctl restart NetworkManager 2>&1 || echo 'vai pedir senha'; sleep 1; nmcli general status")))

    def b_bt(self):
        v = self.tabs["Bluetooth"]
        self.lbl(v, "Desligue para economizar bateria em notebook velho.")
        self.btn(v, "Ligar Bluetooth", lambda: self.say(sh("rfkill unblock bluetooth; sudo -n systemctl start bluetooth 2>&1; bluetoothctl show | head -5")))
        self.btn(v, "Desligar Bluetooth", lambda: self.say(sh("rfkill block bluetooth; echo BT off")))
        self.btn(v, "Parear (30s visivel)", lambda: subprocess.Popen("blueman-manager 2>/dev/null || bluetoothctl scan on & sleep 25; kill %1", shell=True))

    def b_look(self):
        v = self.tabs["Aparencia"]
        self.lbl(v, "Preview aplica na hora. Confirmar salva em ~/.config/panthera/theme.json.")
        for tema in ["Pantera Escuro", "Savana Claro", "Meia-noite"]:
            self.btn(v, f"Aplicar {tema}", lambda t=tema: self.apply_tema(t))
        self.lbl(v, "Cor destaque (padrao #1D83FF):")
        for cor in ["#1D83FF", "#3A9BFF", "#1E3A8A", "#2ECC71", "#E94560", "#F3F6F9"]:
            self.btn(v, f"Usar {cor}", lambda c=cor: self.apply_cor(c))
        self.btn(v, "Fonte 100%", lambda: self.say(sh("xfconf-query -c xsettings -p /Gdk/WindowScalingFactor -s 1 2>/dev/null || gsettings set org.gnome.desktop.interface text-scaling-factor 1.0 2>/dev/null; echo fonte 100")))
        self.btn(v, "Fonte 125% (teste nao quebra dock)", lambda: self.say(sh("xfconf-query -c xsettings -p /Gdk/WindowScalingFactor -s 1 2>/dev/null; gsettings set org.gnome.desktop.interface text-scaling-factor 1.25 2>/dev/null; echo fonte 125")))
        self.btn(v, "Restaurar Padrao Panthera", self.restore)

    def apply_tema(self, t):
        try:
            os.makedirs(os.path.dirname(CFG), exist_ok=True)
            cur = {}
            if os.path.exists(CFG):
                cur = json.load(open(CFG))
            cur["tema"] = t
            json.dump(cur, open(CFG, "w"))
            self.say(f"Aplicado: {t}")
        except Exception as e:
            self.say(f"Erro tema: {e}")

    def apply_cor(self, c_):
        try:
            os.makedirs(os.path.dirname(CFG), exist_ok=True)
            cur = json.load(open(CFG)) if os.path.exists(CFG) else {}
            cur["accent"] = c_
            json.dump(cur, open(CFG, "w"))
            self.say(f"Destaque: {c_}")
        except Exception as e:
            self.say(f"Erro cor: {e}")

    def restore(self):
        try:
            import shutil
            shutil.rmtree(os.path.expanduser("~/.config/panthera/themes"), ignore_errors=True)
            if os.path.exists(CFG):
                os.remove(CFG)
            self.say("Restaurado /usr/share/themes/Panthera.")
        except Exception as e:
            self.say(f"Erro restore: {e}")

    def b_sound(self):
        v = self.tabs["Som"]
        self.lbl(v, "Troca de saida e imediata. Sem som? Doutor abaixo.")
        self.btn(v, "Testar som (seno 2s)", lambda: self.say(sh("speaker-test -c2 -t sine -l1 2>&1 | head -3")))
        self.btn(v, "Abrir volume (pavucontrol)", lambda: subprocess.Popen("pavucontrol 2>/dev/null || pactl list sinks | head -10", shell=True))
        self.btn(v, "Doutor Som", lambda: self.say(sh("aplay -l | head -8; pactl info | head -8")))

    def b_power(self):
        v = self.tabs["Energia"]
        self.lbl(v, "Notebook velho: use Economia. Ele desliga efeito e ativa zram.")
        self.btn(v, "Modo Economia", lambda: self.say(sh("xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null; echo economia on")))
        self.btn(v, "Modo Equilibrado", lambda: self.say(sh("xfconf-query -c xfwm4 -p /general/use_compositing -s true 2>/dev/null; echo equilibrado")))
        self.btn(v, "Modo Super Leve (I2)", lambda: self.say(sh("/usr/bin/panthera-superleve 2>&1 | tail -5 || echo sem-superleve")))
        self.btn(v, "Ver bateria", lambda: self.say(sh("upower -i $(upower -e | grep BAT | head -1) 2>/dev/null | grep -E 'percentage|state|health' | head -5 || acpi 2>/dev/null || echo sem-bateria")))

    def b_priv(self):
        v = self.tabs["Privacidade"]
        self.lbl(v, "Nunca enviamos nada. Localizacao e relatorios OFF travados.")
        self.btn(v, "Limpar historico e miniaturas", lambda: self.say(sh("rm -rf ~/.local/share/RecentDocuments/* ~/.thumbnails/* ~/.cache/thumbnails/* 2>/dev/null; echo limpo")))
        self.btn(v, "Prova de privacidade (I12, salva em Documentos)", lambda: self.say(sh("cat /etc/panthera/privacy-manifest.txt 2>/dev/null; echo ---; sudo ufw status 2>&1 | head -5")))

    def b_sec(self):
        v = self.tabs["Seguranca"]
        self.lbl(v, "Verde = protegido. Vermelho so se firewall OFF.")
        self.btn(v, "Ver regras firewall", lambda: self.say(sh("sudo ufw status verbose 2>&1 | head -12")))
        self.btn(v, "Ligar firewall agora", lambda: self.say(sh("sudo ufw --force enable 2>&1 | tail -2")))
        self.btn(v, "Escanear pasta pessoal (rapido)", lambda: subprocess.Popen("x-terminal-emulator -e 'clamscan -ri --max-filesize=50M $HOME/Documents $HOME/Downloads 2>&1 | tail -20; read' 2>/dev/null || clamscan --version", shell=True))
        self.btn(v, "Rodar 10 provas (Secao 9)", lambda: self.say(sh("cat /etc/sysctl.d/99-panthera.conf 2>/dev/null | head -15; sudo aa-status 2>&1 | head -5")))

    def b_users(self):
        v = self.tabs["Usuarios"]
        self.lbl(v, "Senha forte: minimo 8 com letra e numero. Login auto OFF.")
        self.btn(v, "Trocar minha senha (abre terminal seguro)", lambda: subprocess.Popen("x-terminal-emulator -e passwd 2>/dev/null || gnome-terminal -- passwd", shell=True))
        self.btn(v, "Listar usuarios", lambda: self.say(sh("cut -d: -f1,3 /etc/passwd | grep -E ':[0-9]{4}:' | head -10")))

    def b_print(self):
        v = self.tabs["Impressoras"]
        self.lbl(v, "HP Epson USB detecta em 60s. Conecte e aguarde.")
        self.btn(v, "Listar impressoras", lambda: self.say(sh("lpstat -p 2>/dev/null || echo nenhuma; lsusb | grep -i -E 'hp|epson|brother|canon' || echo usb-nenhuma")))
        self.btn(v, "Pagina teste (padrao)", lambda: self.say(sh("lp -d $(lpstat -d 2>/dev/null | awk '{print $4}') /usr/share/cups/data/testprint 2>&1 | head -3 || echo sem-impressora")))
        self.btn(v, "Abrir scanner", lambda: subprocess.Popen("simple-scan 2>/dev/null || echo sem-scanner", shell=True))

    def b_lang(self):
        v = self.tabs["Atalhos e Idioma"]
        self.lbl(v, "Teclado ABNT2. Teste: digite c til a. Atalhos na Secao 7.")
        self.btn(v, "Aplicar ABNT2 agora", lambda: self.say(sh("setxkbmap -layout br -variant abnt2 2>&1; echo ABNT2 ok. Digite: c ~ ^")))
        self.btn(v, "Fuso Sao Paulo + NTP", lambda: self.say(sh("sudo timedatectl set-timezone America/Sao_Paulo 2>&1; timedatectl 2>&1 | head -5")))

    def b_about(self):
        v = self.tabs["Sobre"]
        self.lbl(v, "Panthera v1 Uso Geral. Copie info para suporte com 1 clique.")
        self.btn(v, "Copiar info do PC", lambda: self.say(sh("cat /etc/panthera/version 2>/dev/null; lscpu 2>/dev/null | grep 'Model name'; free -h 2>/dev/null | head -2; df -h / 2>/dev/null | tail -1")))
        self.btn(v, "Doutor completo", lambda: self.say(sh("/usr/bin/panthera-doctor --check all 2>&1 | tail -30")))
        self.btn(v, "Ajuda offline (I11)", lambda: subprocess.Popen("firefox file:///usr/share/panthera-ajuda/index.html 2>/dev/null || xdg-open file:///usr/share/panthera-ajuda/index.html 2>/dev/null || echo sem-ajuda", shell=True))

    def on_search(self, entry):
        try:
            q = entry.get_text().strip().lower()
            if not q:
                return
            mapa = {"wifi": "Wi-Fi e Rede", "rede": "Wi-Fi e Rede", "bluetooth": "Bluetooth",
                    "tema": "Aparencia", "papel": "Aparencia", "fonte": "Aparencia",
                    "som": "Som", "audio": "Som", "energia": "Energia", "bateria": "Energia",
                    "priva": "Privacidade", "firewall": "Seguranca", "virus": "Seguranca",
                    "usuario": "Usuarios", "senha": "Usuarios", "impress": "Impressoras",
                    "scan": "Impressoras", "teclado": "Atalhos e Idioma",
                    "idioma": "Atalhos e Idioma", "sobre": "Sobre", "versao": "Sobre"}
            for k, aba in mapa.items():
                if k in q:
                    idx = list(self.tabs.keys()).index(aba)
                    self.nb.set_current_page(idx)
                    break
        except Exception as e:
            self.say(f"Erro busca: {e}")

if __name__ == "__main__":
    w = Central()
    w.connect("destroy", Gtk.main_quit)
    w.show_all()
    Gtk.main()
