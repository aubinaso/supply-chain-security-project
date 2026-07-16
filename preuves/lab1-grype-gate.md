# Lab 1 — SBOM et gate Grype

- Image saine : ghcr.io/johlan78/scs-demo-app:0.1.0
- Image vulnérable temporaire : ghcr.io/johlan78/scs-demo-app:vuln
- Commande de contrôle : grype "$IMG:vuln" --only-fixed --fail-on high
- Code de sortie observé : 2
- Résultat : la gate de sécurité a correctement bloqué l’image vulnérable
- État restauré : Flask 3.0.3
- Scan final de l’image saine : code de sortie 0
