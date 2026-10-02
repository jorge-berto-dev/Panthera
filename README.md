# Panthera OS v1 Uso Geral
Leve, privado, seguro e simples para PC fraco. ISO Ventoy.

## Catalogo e Kits

O sistema vem enxuto e o software vem por **Kits**, na Loja. A escolha acontece no
primeiro boot (Bem-vindo) ou depois, na Loja Panthera.

- **Kits**: Leve (recomendado), Escritorio, Aula e video, Criacao, Programador.
- O navegador **nao vem instalado**. Ele esta no pool offline dentro da propria ISO,
  entao da para instalar sem internet nenhuma.
- Tamanho e memoria necessaria sao **medidos no APT** no momento da tela, nunca estimados.
- A aba **O que recusamos** lista os pacotes que a Panthera nao instala e o motivo.
- O catalogo vive em `kits/catalogo.json`: novo Kit = editar um arquivo, sem rebuild.

Firefox ESR e o navegador. As policies de privacidade sao entregues por hook do apt,
entao valem se ele vier de um Kit, do pool offline ou de um `sudo apt install firefox-esr`.

## Requisitos host (para compilar a ISO, nao para usar)
Debian 12 amd64 limpo, 20GB livre, 4GB RAM, internet.

## Build em 1 comando
```
sudo apt update && sudo apt install -y live-build cdebootstrap debootstrap
sudo ./build-iso.sh
```

## Saída
`out/panthera-v1-amd64-hybrid.iso` + `.sha256`

## Teste rápido
```
./tests/test-iso.sh
qemu-system-x86_64 -m 2048 -cdrom out/*.iso -boot d
```

## Ventoy
Copie o ISO para o pendrive Ventoy exFAT. Boot UEFI e Legacy. Clique INSTALAR.

## Especificação
Autoridade: `Panthera_OS_Prompt_Mestre.odt` (Seções 3, 5, 11).
Licença: GPLv3 código, CC-BY-SA arte. Sem chave, sem telemetria.
