#!/usr/bin/env python3
# /usr/lib/panthera/catalogo.py - leitura e medicao do catalogo Panthera
# Sem gi: logica pura, testavel sem display. Usado pela Loja e pelo Bem-vindo.
#
# Regra central (ODT 8 + Secao 27): tamanho e RAM nunca sao digitados.
# Tudo e medido no APT em tempo de instalacao.
import json
import os
import re
import subprocess

CATALOGO = "/usr/share/panthera-store/catalogo.json"
POOL = "/var/cache/panthera-pool"
# Só para rodar do repo (dev e CI). No sistema instalado o primeiro caminho
# existe e tem prioridade, então isto nunca muda o que o usuario recebe.
CATALOGO_REPO = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "kits", "catalogo.json")
)


class CatalogoErro(Exception):
    pass


def _caminho(caminho=None):
    if caminho:
        return caminho
    for candidato in (CATALOGO, CATALOGO_REPO):
        if os.path.exists(candidato):
            return candidato
    return CATALOGO


def _apt(*args):
    """apt-get com LC_ALL=C: os resumos de espaco so saem faceis de ler em ingles."""
    return subprocess.run(
        ["apt-get", "-y", *args],
        capture_output=True,
        text=True,
        env={**os.environ, "LC_ALL": "C", "DEBIAN_FRONTEND": "noninteractive"},
    )


def carregar(caminho=None):
    caminho = _caminho(caminho)
    try:
        with open(caminho, encoding="utf-8") as f:
            cat = json.load(f)
    except FileNotFoundError:
        raise CatalogoErro("catalogo ausente: %s" % caminho)
    except json.JSONDecodeError as e:
        raise CatalogoErro("catalogo invalido: %s" % e)
    for secao in ("apps", "kits", "recusados"):
        if not isinstance(cat.get(secao), dict):
            raise CatalogoErro("catalogo sem a secao '%s'" % secao)
    for kit, dados in cat["kits"].items():
        if not isinstance(dados.get("apps"), list) or not dados["apps"]:
            raise CatalogoErro("kit '%s' sem lista de apps" % kit)
        for chave in dados["apps"]:
            if chave not in cat["apps"]:
                raise CatalogoErro("kit '%s' aponta para app inexistente: %s" % (kit, chave))
    return cat


def itens_de(cat, kit):
    if kit not in cat["kits"]:
        raise CatalogoErro("kit desconhecido: %s" % kit)
    return [(chave, cat["apps"][chave]) for chave in cat["kits"][kit]["apps"]]


def pacotes_de(cat, kit):
    vistos, saida = set(), []
    for _, item in itens_de(cat, kit):
        for p in item.get("pacotes", []):
            if p not in vistos:
                vistos.add(p)
                saida.append(p)
    return saida


def recusados_no(cat, pacotes):
    return [p for p in pacotes if p in cat.get("recusados", {})]


def ja_instalado(pacotes):
    if not pacotes:
        return True
    r = subprocess.run(
        ["dpkg-query", "-W", "-f=${db:Status-Status} ${Package}\n"] + list(pacotes),
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        return False
    linhas = [l.split() for l in r.stdout.splitlines() if l.strip()]
    if len(linhas) != len(pacotes):
        return False
    return all(estado == "installed" for estado, _ in linhas)


def _simular(pacotes):
    """Saida da simulacao do apt. None quando o apt RECUSOU o pedido (pacote
    inexistente no repo, lista desatualizada). Isso e diferente de 'nada a
    instalar', e a diferenca entre dizer 0 MB e dizer '?'."""
    r = _apt("-s", "install", *pacotes)
    return r.stdout if r.returncode == 0 else None


def _tem_inst(out):
    return any(linha.startswith("Inst ") for linha in out.splitlines())


def medir_download(pacotes):
    """Bytes a baixar. 0 quando ja esta tudo instalado, None quando o apt nao responde."""
    if not pacotes or ja_instalado(pacotes):
        return 0
    out = _simular(pacotes)
    if out is None:
        return None
    if not _tem_inst(out):
        return 0
    r = _apt("--print-uris", "install", *pacotes)
    total = 0
    for linha in r.stdout.splitlines():
        partes = linha.split("'")
        if len(partes) >= 3 and partes[2].split() and partes[2].split()[-1].endswith(".deb"):
            try:
                total += int(partes[2].split()[0])
            except ValueError:
                pass
    return total


def medir_disco(pacotes):
    """Bytes de disco que a instalacao ocupa. 0 quando ja esta instalado, None sem resposta do apt."""
    if not pacotes or ja_instalado(pacotes):
        return 0
    out = _simular(pacotes)
    if out is None:
        return None
    if not _tem_inst(out):
        return 0
    m = re.search(r"After this operation, ([0-9.,]+)\s*([kMGTE]?B)", out)
    if not m:
        return None
    fatores = {"B": 1, "kB": 1024, "MB": 1024 ** 2, "GB": 1024 ** 3, "TB": 1024 ** 4}
    return int(float(m.group(1).replace(",", "")) * fatores.get(m.group(2), 1))


def pool_disponivel(pacote):
    """Caminho do .deb no pool offline da ISO, se estiver la."""
    if not os.path.isdir(POOL):
        return None
    candidatos = sorted(
        f for f in os.listdir(POOL)
        if f.startswith(pacote + "_") and f.endswith(".deb")
    )
    return os.path.join(POOL, candidatos[0]) if candidatos else None


def comandos(cat, kit):
    """Transacoes do kit: uma por origem, nunca um apt por pacote.

    Devolve (so_offline, [(rotulo, argv), ...]). Pacotes que existem no pool
    offline vao por caminho de arquivo e funcionam sem internet nenhuma.
    """
    pacotes = pacotes_de(cat, kit)
    proibidos = recusados_no(cat, pacotes)
    if proibidos:
        raise CatalogoErro("o kit pede pacotes recusados: %s" % ", ".join(proibidos))

    da_rede, do_pool, flatpak, scripts = [], [], [], []
    for _, item in itens_de(cat, kit):
        origem = item.get("origem", "apt")
        if origem == "script":
            scripts.extend(item.get("comando", []))
        elif origem == "flatpak":
            flatpak.extend(item.get("pacotes", []))
        else:
            da_rede.extend(item.get("pacotes", []))

    # Separa o que vem no pool offline sem mexer na lista durante o laco.
    restantes = []
    for p in da_rede:
        local = pool_disponivel(p)
        if local:
            do_pool.append(local)
        else:
            restantes.append(p)
    da_rede = restantes
    etapas = []
    if do_pool:
        etapas.append(("do pool offline da ISO (sem internet)", ["apt-get", "-y", "install"] + do_pool))
    if da_rede:
        etapas.append(("da internet", ["apt-get", "-y", "install"] + da_rede))
    for app_id in flatpak:
        etapas.append(("Flatpak", ["flatpak", "install", "-y", "flathub", app_id]))
    for script in scripts:
        etapas.append(("script do sistema", ["bash", script]))
    return not da_rede and not flatpak and not scripts, etapas


def tamanho_humano(n):
    if n is None:
        return "?"
    if n < 1024:
        return "%d B" % n
    for unidade in ("KB", "MB", "GB"):
        n /= 1024.0
        if n < 1024 or unidade == "GB":
            return "%.1f %s" % (n, unidade)
    return "%.1f GB" % n


def ram_livre():
    try:
        with open("/proc/meminfo", encoding="utf-8") as f:
            for linha in f:
                if linha.startswith("MemAvailable:"):
                    return int(linha.split()[1]) // 1024
    except OSError:
        pass
    return 0


def resumo(cat, kit):
    """Tudo que a tela precisa, com numeros medidos agora."""
    pacotes = pacotes_de(cat, kit)
    return {
        "kit": kit,
        "nome": cat["kits"][kit]["nome"],
        "desc": cat["kits"][kit].get("desc", ""),
        "pacotes": pacotes,
        "instalado": ja_instalado(pacotes),
        "download": medir_download(pacotes),
        "disco": medir_disco(pacotes),
        "ram_livre_mb": ram_livre(),
        "itens": itens_de(cat, kit),
    }
