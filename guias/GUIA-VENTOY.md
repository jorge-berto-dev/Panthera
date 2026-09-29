# Guia Ventoy — Panthera OS v1 (ODT Secao 18 + FASE 7)

Autoridade: `Panthera_OS_Prompt_Mestre.odt` Secao 18. PT-BR simples.

## O que precisa

- ISO `out/panthera-v1.0-uso-geral-amd64-hybrid.iso` + `.sha256`
- Pendrive USB 8GB ou maior (vai apagar tudo do pendrive)
- Ventoy 1.0.9x ou maior
- PC teste 2010–2019 com 2GB+ RAM

## Passo 1 — Confira a ISO

```
sha256sum -c out/panthera-v1.0-uso-geral-amd64-hybrid.iso.sha256
```

Esperado: `out/...iso: OK`. Se falhar, baixe/regenere de novo.
Troque de pendrive se der erro de I/O (`dmesg | grep -i squashfs` sem erro).

## Passo 2 — Instale o Ventoy no pendrive (exFAT)

1. Baixe o Ventoy 1.0.9x+ e rode o `Ventoy2Disk`.
2. Escolha o USB de 8GB, formato exFAT, instale.
3. O pendrive fica com 2 particoes: uma do Ventoy + uma maior exFAT.

## Passo 3 — Copie a ISO

Copie `panthera-v1.0-uso-geral-amd64-hybrid.iso` para a particao
maior do pendrive. Ejete com seguranca.

## Passo 4 — Boot UEFI

1. Desligue o PC teste, plugue o pendrive.
2. Ligue apertando F12 (ou F8/Esc/Del, conforme a marca).
3. Escolha USB **UEFI**, no menu Ventoy escolha a ISO do Panthera.
4. Esperado: menu GRUB azul escuro com 3 linhas
   (Experimentar ou Instalar, Instalar direto, Verificar integridade),
   timeout 10s. Escolha a primeira.

## Passo 5 — Boot Legacy (se possivel)

Mesmo pendrive em PC/VM com BIOS Legacy, boot USB-HDD.
Mesmo esperado do UEFI. Fotografe menu Ventoy + GRUB + desktop.

## Passo 6 — Teste Live (Experimentar, sem instalar)

- Desktop em ate 90s, sem pedir senha, com INSTALAR e Boas-vindas.
- Wi-Fi lista redes em ate 20s. Som, video YouTube 30s.
- Opcao 3 do GRUB (Verificar integridade): check OK.

## Falhas comuns (Secao 18)

- **Secure Boot** reclama do shim: desligue temporario na BIOS.
- **BitLocker** vermelho no instalador: desative no Windows antes.
- **Bateria fraca**: ligue na tomada (instalador bloqueia <20%).
- **Disco nao aparece**: troque para AHCI na BIOS.
- **Tela preta NVIDIA**: boot com nouveau (padrao), driver
  proprietario so depois, com snapshot (TimePanthera).
- **Legacy nao boota**: regere isohybrid + confira `grub-pc-bin`.
- **UEFI nao acha**: confira `grub-efi-amd64-signed`/`shim-signed`.

## Checklist ferro real (dono)

Backup externo, SHA confere, USB 8GB, BIOS boot USB, Live testa,
INSTALAR Apagar tudo so com backup, pos: Atualizar + Doutor + tema,
preta NVIDIA = fallback nouveau no GRUB Opcoes.
