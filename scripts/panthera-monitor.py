#!/usr/bin/env python3
# /usr/bin/panthera-monitor - Monitor do sistema Panthera
# So GTK3 + stdlib. Leitura pura de /proc e /sys: nao instala nada, nao muda
# nada, nao precisa de sudo e nao quebra nada. Atualiza a cada 2 segundos.
# Teste: python3 -m py_compile + python3 panthera-monitor.py --help (sem display)
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

import os
import shutil
import sys
import time


def ler_tempos_cpu():
    """Devolve (ocioso, total) somando os campos de /proc/stat."""
    with open("/proc/stat", encoding="utf-8") as f:
        partes = f.readline().split()[1:]
    numeros = [int(x) for x in partes]
    ocioso = numeros[3] + (numeros[4] if len(numeros) > 4 else 0)
    return ocioso, sum(numeros)


def ler_tempos_processos():
    """Tempos de CPU por pid, para comparar entre duas leituras."""
    tempos = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/stat" % pid, encoding="utf-8") as f:
                campos = f.read().rsplit(")", 1)[1].split()
            tempos[int(pid)] = int(campos[11]) + int(campos[12])
        except (OSError, ValueError, IndexError):
            continue
    return tempos


def ler_memoria():
    """Devolve (total_mb, disponivel_mb, usada_mb) lendo /proc/meminfo."""
    info = {}
    with open("/proc/meminfo", encoding="utf-8") as f:
        for linha in f:
            partes = linha.split()
            if len(partes) >= 2 and partes[0].endswith(":"):
                try:
                    info[partes[0][:-1]] = int(partes[1])
                except ValueError:
                    pass
    total = info.get("MemTotal", 0) // 1024
    disponivel = info.get("MemAvailable", info.get("MemFree", 0)) // 1024
    return total, disponivel, max(0, total - disponivel)


def ler_disco(caminho="/"):
    """Devolve (total_gb, usado_gb, livre_gb) do ponto de montagem."""
    uso = shutil.disk_usage(caminho)
    return uso.total / 1024 ** 3, uso.used / 1024 ** 3, uso.free / 1024 ** 3


def ler_temperatura():
    """Temperatura da CPU em graus, ou None quando o sensor nao existe."""
    for zona in sorted(os.listdir("/sys/class/thermal") if os.path.isdir("/sys/class/thermal") else []):
        if not zona.startswith("thermal_zone"):
            continue
        try:
            with open(os.path.join("/sys/class/thermal", zona, "type"), encoding="utf-8") as f:
                tipo = f.read().strip()
            with open(os.path.join("/sys/class/thermal", zona, "temp"), encoding="utf-8") as f:
                temp = int(f.read().strip()) / 1000.0
            if "cpu" in tipo.lower() or "x86" in tipo.lower() or "soc" in tipo.lower():
                return temp
        except (OSError, ValueError):
            continue
    try:
        with open("/sys/class/thermal/thermal_zone0/temp", encoding="utf-8") as f:
            return int(f.read().strip()) / 1000.0
    except (OSError, ValueError):
        return None


def ler_uptime():
    """Segundos desde o boot, lendo /proc/uptime."""
    try:
        with open("/proc/uptime", encoding="utf-8") as f:
            return float(f.read().split()[0])
    except (OSError, ValueError):
        return 0.0


def formatar_uptime(segundos):
    segundos = int(segundos)
    dias, resto = divmod(segundos, 86400)
    horas, resto = divmod(resto, 3600)
    minutos, _ = divmod(resto, 60)
    if dias:
        return "%dd %dh %dm" % (dias, horas, minutos)
    if horas:
        return "%dh %dm" % (horas, minutos)
    return "%dm" % minutos


def ler_total_cpu():
    with open("/proc/stat", encoding="utf-8") as f:
        return sum(int(x) for x in f.readline().split()[1:])


def top_processos(antes, total_antes, n=5):
    """Os n que mais CPU usaram desde a amostragem anterior.
    Sem sleep: quem chama guarda a amostra e compara no refresh seguinte, entao
    a interface nunca trava esperando. Na primeira chamada nao ha base de
    comparacao e devolve lista vazia."""
    if not antes:
        return []
    total_depois = ler_total_cpu()
    delta_total = max(1, total_depois - total_antes)
    ncpu = os.cpu_count() or 1
    agora = ler_tempos_processos()
    saida = []
    for pid, t0 in antes.items():
        t1 = agora.get(pid)
        if t1 is None or t1 <= t0:
            continue
        try:
            with open("/proc/%s/comm" % pid, encoding="utf-8") as f:
                nome = f.read().strip()
        except (OSError, ValueError):
            continue
        pct = (t1 - t0) / delta_total * 100.0 * ncpu
        if pct > 0.5:
            saida.append((nome, pid, pct))
    saida.sort(key=lambda x: x[2], reverse=True)
    return saida[:n]


if "--help" in sys.argv or "-h" in sys.argv:
    print("Monitor Panthera: CPU, memoria, disco, temperatura e processos. So leitura.")
    raise SystemExit(0)


class Monitor(Gtk.Window):
    def __init__(self):
        super().__init__(title="Monitor Panthera")
        self.set_default_size(520, 480)
        self._cpu_antes = None
        # Amostras para o proximo refresh: sem elas, top_processos precisaria
        # dormir para medir, e dormir na thread da interface trava a janela.
        self._proc_antes = {}
        self._total_antes = 0
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        v.set_border_width(14)
        self.add(v)

        titulo = Gtk.Label()
        titulo.set_markup("<b>Monitor Panthera</b>  —  só observa, não mexe em nada")
        titulo.set_xalign(0)
        titulo.set_line_wrap(True)
        v.pack_start(titulo, False, False, 0)

        self.rotulos = {}
        for chave, texto in (("cpu", "Processador"), ("mem", "Memória"),
                             ("disco", "Disco /"), ("temp", "Temperatura"),
                             ("up", "Ligado há")):
            linha = Gtk.Box(spacing=8)
            nome = Gtk.Label(label=texto)
            nome.set_xalign(0)
            nome.set_width_chars(14)
            linha.pack_start(nome, False, False, 0)
            valor = Gtk.Label(label="medindo...")
            valor.set_xalign(0)
            linha.pack_start(valor, True, True, 0)
            v.pack_start(linha, False, False, 0)
            self.rotulos[chave] = valor

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        v.pack_start(sep, False, False, 4)

        subt = Gtk.Label()
        subt.set_markup("<b>Quem mais usa o processador</b>")
        subt.set_xalign(0)
        v.pack_start(subt, False, False, 0)

        self.lista = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        v.pack_start(self.lista, False, False, 0)

        self._atualizar()
        GLib.timeout_add_seconds(2, self._atualizar)

    def safe(self, acao, *args):
        try:
            return acao(*args)
        except Exception as e:
            print("Erro tratado: %s" % e)
            return None

    def _atualizar(self):
        try:
            agora_ocioso, agora_total = ler_tempos_cpu()
            if self._cpu_antes is not None:
                o1, t1 = self._cpu_antes
                cpu = (1.0 - (agora_ocioso - o1) / max(1, agora_total - t1)) * 100.0
                cpu = max(0.0, min(100.0, cpu))
            else:
                cpu = None
            self._cpu_antes = (agora_ocioso, agora_total)

            total, disponivel, usada = ler_memoria()
            dt, du, dl = ler_disco()
            temp = ler_temperatura()

            self.rotulos["cpu"].set_text(
                "%.0f%%" % cpu if cpu is not None else "medindo...")
            self.rotulos["mem"].set_text(
                "%d de %d MB em uso" % (usada, total) if total else "?")
            self.rotulos["disco"].set_text(
                "%.1f de %.1f GB em uso" % (du, dt))
            self.rotulos["temp"].set_text(
                "%.0f °C  %s" % (temp, "(quente!)" if temp > 80 else "(normal)")
                if temp is not None else "sensor ausente neste PC")
            self.rotulos["up"].set_text(formatar_uptime(ler_uptime()))

            for filho in list(self.lista.get_children()):
                self.lista.remove(filho)
            for nome, pid, pct in top_processos(self._proc_antes, self._total_antes):
                linha = Gtk.Label(label="%s  (pid %d): %.0f%%" % (nome, pid, pct))
                linha.set_xalign(0)
                self.lista.add(linha)
            if not self._proc_antes:
                self.lista.add(Gtk.Label(label="medindo... (aparece no próximo ciclo)"))
            self._proc_antes = ler_tempos_processos()
            self._total_antes = ler_total_cpu()
            self.lista.show_all()
        except Exception as e:
            print("Erro tratado ao atualizar: %s" % e)
        return True


if __name__ == "__main__":
    janela = Monitor()
    janela.connect("destroy", Gtk.main_quit)
    janela.show_all()
    Gtk.main()
