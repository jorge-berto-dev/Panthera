# Panthera OS v1 Uso Geral
Leve, privado, seguro e simples para PC fraco. Firefox padrão. ISO Ventoy.

## Requisitos host
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
