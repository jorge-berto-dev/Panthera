# Guia: gerar a ISO sem Debian 12 no notebook

Problema: `build-iso.sh` precisa de root + `live-build` + chroot, e o host
(aqui, Linux Mint 22.3) falhava. Solucao: o build roda num container
`debian:bookworm` privilegiado no GitHub Actions, de graca, sem usar seu
disco nem sua RAM.

## 1. Publicar o codigo no GitHub

```
cd ~/panthera
git init
git add -A
git commit -m "Panthera v1: build da ISO na nuvem"
```

Crie o repositorio em https://github.com/new (ex.: `panthera-os`), depois:

```
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/panthera-os.git
git push -u origin main
```

## 2. Rodar o build

Na aba **Actions** do repositorio: workflow "Panthera ISO" -> **Run workflow**.
Dura 30-60 min. O log aparece em tela.

Ou pelo terminal (precisa do `gh` autenticado):

```
gh workflow run build-iso.yml
gh run watch
```

## 3. Baixar a ISO

O workflow fatia a ISO em `panthera-iso.part-00`, `part-01`... (1 GB cada) e
sobe para um **Release** (limite de 2 GB por arquivo no GitHub).

```
mkdir -p ~/Downloads/panthera-iso && cd ~/Downloads/panthera-iso
gh release download --pattern 'panthera-iso.part-*' --pattern '*.sha256'
cat panthera-iso.part-* > panthera-v1.0-uso-geral-amd64-hybrid.iso
sha256sum -c panthera-v1.0-uso-geral-amd64-hybrid.iso.sha256
```

Se voce nao usa `gh`, baixe os arquivos pela pagina do Release e junte com
`cat`, na ordem `part-00`, `part-01`... O `sha256sum -c` deve responder
`panthera-...iso: OK`.

## 4. Testar antes de gravar o pendrive

```
qemu-system-x86_64 -m 2048 -smp 2 -cdrom ~/Downloads/panthera-iso/panthera-v1.0-uso-geral-amd64-hybrid.iso -boot d
```

## 5. Se o build falhar

Baixe o log: na aba **Actions**, no run que falhou, em "Log e matrizes como
artefato" -> `panthera-iso-logs` -> `docker-build.log`. O erro real esta na
primeira linha com `E:` ou `lb build: error:`.

Causas comuns de falha:

- `E: Package 'X' is not available` -> `X` saiu do bookworm. Tirar de
  `packages-lists/panthera-base.list`.
- `No space left on device` -> o runner precisa de ~10 GB. O workflow ja
  limpa `/usr/share/dotnet` e `/opt/ghc`; se persistir, suba para um
  runner maior ou reduza o pacote list.
- `Failed to mount /proc` -> o runner perdeu o modo privilegiado; o
  workaround e rodar o build num `debian:12` padrao sem `--privileged` e
  usar `--variant=minbase`.
- `lb build: error: hook returned non-zero exit status 0X` -> o erro real
  esta nas linhas anteriores do log.
