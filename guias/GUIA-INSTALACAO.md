# Guia Instalacao — Panthera OS v1 (ODT Secao 11 + 29 + FASE 7)

Autoridade: `Panthera_OS_Prompt_Mestre.odt` Secoes 11 e 29. Leve impresso.

## Roteiro tecnico em campo — 15 minutos (Secao 29)

**Chegada 2min:** pergunte do backup, olhe RAM/HD na etiqueta,
fotografe Windows ativado e BitLocker.

**Boot 3min:** pendrive Ventoy, F12, escolha a ISO, Experimentar,
teste Wi-Fi, som, video YouTube 30s e impressora se houver.

**Decisao disco 2min:**
- HD com defeito: avise e troque, nao instale.
- Windows com espaco: Lado a lado, slider 20GB para o Panthera.
- PC lixo/virus: Apagar tudo, com autorizacao assinada.

**Instalacao 8min:** inicie e deixe copiando enquanto explica os
4 cartoes da Dona Cida (Wi-Fi, favoritos, videos, papel).

**Entrega 5min:** reboot, tire o USB, cliente digita senha forte,
rode Atualizar + Doutor, troque tema ida e volta, mostre Ejetar
pendrive e tecla Print, entregue papel com senha + checklist
bancada assinado.

Volta so se: tela preta NVIDIA (fallback nouveau) ou Wi-Fi
Broadcom sem cabo (use cabo ou tethering USB).

## As 6 telas (texto literal Secao 11)

**T1 Bem-vindo:** Ola, vamos instalar rapidinho. Leve, privado e
seu em ~15min. Mostra RAM e disco. RAM <1.5GB: aviso amarelo
devagar, sem bloquear. Botoes INSTALAR AGORA gigante azul,
Experimentar, Notas. Nada apaga ate a tela Disco.

**T2 Wi-Fi + Idioma + Teclado:** redes + senha, Portugues Brasil,
America/Sao_Paulo, BR ABNT2 (teste: digite c til). Sem Wi-Fi
continua com aviso para depois. Continuar.

**T3 Disco:** A) Apagar tudo (recomendado, mostra o disco, tudo
apaga). B) Lado a lado (slider, minimo 15GB, avisa se Windows
ficar sem 10GB). C) Manual. Criptografar notebook: senha com
medidor. Erros: sem disco = reconecte; BitLocker vermelho =
desative no Windows; bateria <20% sem tomada = bloqueia;
EFI <100MB = recria 512 fat32.

**T4 Quem e voce:** nome, PC automatico, usuario minusculas sem
espaco (bloqueia root/admin), senha min 8 com letra+numero +
confirmar com medidor, foto opcional, login auto OFF. Anote a
senha: sem ela nao entra, nem recupera LUKS.

**T5 Instalando:** barra Copiando/Instalando/Ajustando, slideshow
Leve/Privado/Seu, Ver detalhes (log), sem Cancelar apos 30%.
Sem net continua offline. Falha disco: ERR-DISK-01.

**T6 Pronto (verde):** Remova o pendrive, Reiniciar e usar
(220x60). No Ventoy pode deixar. Na volta escolha Panthera.

## Particao (Secao 11)

- **UEFI GPT:** `/boot/efi` 512 fat32 boot esp, `/` ext4 resto
  (min 12GB, recom 20GB), swapfile 1GB so se RAM<4GB
  (swappiness 10), LUKS2 sem LVM na v1.
- **BIOS MBR:** bios_grub 1MB + `/` ext4.
- Sempre: hostname do usuario, Sao_Paulo, pt_BR, br abnt2,
  GRUB no disco, os-prober (acha Windows), timeout 5, tema.
- Pos-install: remove live, habilita ufw/apparmor/upgrades,
  cria `/etc/panthera/version`.

## Cronometragem DoD

Do clique INSTALAR ao reboot: <=25min HD VM, <=20min SSD ferro.
Reprova se: trava em particao, nao cria usuario, GRUB nao boota,
ou apaga Windows no Lado a lado. Log em
`/var/log/panthera-install.log` (copiado para o instalado).

## Perguntas da Dona Cida (FAQ Secao 14)

- **Chave?** Nunca. Gratis, sem conta, sem pagar.
- **Celeron 2GB?** Sim, use Modo Economia/Super Leve.
- **Virus?** Protegido; escaneie o pendrive antes de abrir.
- **Windows?** Lado a lado preserva, mas faca backup antes.
- **Word?** Loja, 1 clique, LibreOffice.
