#!/usr/bin/env python3
# /usr/bin/panthera-theme-check.py - rejeita tema perigoso (ODT Secao 21.2 + I9)
# Tema so pode ter cores e papel, nunca codigo. Exige theme.json no zip.
# Teste: python3 /usr/bin/panthera-theme-check.py meu.panthera-theme
import sys, zipfile

BLOQ = ["sudo", "/etc", "/usr", ".sh", ".py", "curl", "wget", "http", "chmod", "+x"]
path = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    z = zipfile.ZipFile(path)
    nomes = z.namelist()
    assert "theme.json" in nomes, "falta theme.json"
    txt = "\n".join([z.read(n).decode("utf-8", "ignore") for n in nomes if n.endswith((".css", ".json"))])
    for b in BLOQ:
        if b in txt:
            print(f"REJEITADO: contem {b}. Tema so pode ter cores e papel, nunca codigo.")
            sys.exit(2)
    print("OK: tema seguro. Pode aplicar em ~/.config/panthera/themes/")
except Exception as e:
    print(f"REJEITADO: {e}")
    sys.exit(1)
