#!/bin/bash
# check-wayland.sh - decide sessão padrão no login
if lspci 2>/dev/null | grep -qi nvidia && ! lsmod 2>/dev/null | grep -q nvidia; then echo "X11 fallback"; exit 1; fi
if [ -e /dev/dri/card0 ]; then echo "Wayland OK"; exit 0; else echo "X11 fallback"; exit 1; fi
