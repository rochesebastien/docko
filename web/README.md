# Landing page Docko

Site statique, sans build : `index.html`, `styles.css`, `main.js` et `assets/`.

Prévisualiser en local :

```sh
cd web && python3 -m http.server 8000
# http://localhost:8000
```

Déployer : pointer Vercel, Netlify ou GitHub Pages sur le dossier `web/`. Aucune configuration nécessaire.

Les liens « Télécharger » pointent vers la dernière release GitHub du dépôt.

## Assets

- `assets/docko-title.png` : logo avec texte (nav). Noir sur fond transparent, inversé en CSS.
- `assets/icon-docko.png` : glyphe seul (favicon, icône dans la barre des menus de la démo).
- `assets/docko-macos.png` : icône de l'app, affichée dans le Dock de la démo.
- `assets/wallpaper.avif` : fond d'écran de la démo.
- `assets/icons/*.svg` : logos d'applications tiers, récupérés sur [devicons.io](https://devicons.io). Ce sont des marques de leurs propriétaires respectifs, utilisées ici à titre d'illustration.
