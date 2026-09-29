#!/bin/bash
# panthera-codecs.sh - ativa vídeos e músicas (ver ODT Seção 6.1)
set -e
echo "Precisa internet. Você é responsável conforme leis do seu país. Continuar? [s/n]"
read -r r
[ "$r" = "s" ] || exit 0
sudo apt update && sudo apt install -y gstreamer1.0-libav gstreamer1.0-plugins-ugly libavcodec-extra
echo "$(date) codecs ok" | sudo tee -a /var/log/panthera-codecs.log
