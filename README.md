# Docko

Des profils de Dock macOS, changeables depuis la barre des menus.

Un profil enregistre les **apps épinglées** et les **espaceurs** du Dock, et, si tu le souhaites, ses **réglages** (taille, agrandissement au survol, masquage automatique, position, effet de réduction, apps récentes…). Docko ne touche ni aux dossiers, ni aux apps récentes, et n'ouvre ni ne ferme aucune application. Tout est stocké en local, aucun compte.

## Fonctionnalités

- Icône dans la barre des menus, sans icône dans le Dock. Un clic sur un profil l'applique.
- Raccourcis globaux en séquence : ⌘D puis la touche du profil (1 à 9 par défaut), depuis n'importe quelle app. Déclencheur et touches modifiables dans Réglages…
- Enregistrer le Dock actuel comme nouveau profil (apps et réglages), ou mettre à jour le profil actif depuis le Dock actuel. Les réglages du Dock peuvent être retirés d'un profil pour qu'il ne change que les apps.
- Fenêtre de gestion : renommer, colorer, réordonner les apps par glisser-déposer, ajouter des apps ou des espaceurs, supprimer, dupliquer.
- Import / export des profils en JSON.
- Lancement au démarrage (élément d'ouverture de session macOS, réappliqué à chaque lancement), affichage optionnel du nom du profil actif dans la barre, icône optionnelle dans le Dock.
- Schéma d'URL `docko://` pour piloter Docko depuis Raccourcis (bascule automatique avec les modes de concentration).

## Prérequis

- macOS 13 Ventura ou plus récent.
- Xcode 15+ ou les Command Line Tools (`xcode-select --install`) pour compiler.

## Compiler

```sh
make            # construit dist/Docko.app
make run        # construit puis lance
make install    # copie dans /Applications
```

Le `.app` est signé ad hoc. Pour que « Lancer au démarrage » et le schéma d'URL fonctionnent de manière fiable, installe l'app dans `/Applications` et lance-la au moins une fois.

Au lancement, Docko n'ouvre pas de fenêtre et n'apparaît pas dans le Dock : cherche son icône dans la barre des menus, en haut à droite (sur un MacBook avec encoche, elle peut être masquée si la barre est pleine). Si Hidden Bar est installé, Docko se place de lui-même à droite de son chevron au premier lancement ; avec Bartender ou Ice, déplie la zone cachée puis ⌘-glisse l'icône Docko à droite du séparateur. Pour avoir aussi l'icône et le point « en cours d'exécution » dans le Dock, active « Afficher Docko dans le Dock » dans le menu ou les Réglages. Au tout premier lancement, sans profil, la fenêtre de gestion s'ouvre d'elle-même ; relancer l'app alors qu'elle tourne déjà la rouvre aussi. Docko ne tourne qu'en une seule instance : lancer une autre copie (par exemple `dist/Docko.app` après un `make run`) remplace celle en cours. `make install` arrête l'ancienne version, installe la nouvelle dans `/Applications` et la lance.

L'icône de l'app est dans `Resources/AppIcon.icns`, générée depuis `Resources/AppIcon.png` (1024×1024) avec `make icon` ; à refaire seulement si le PNG change.

## Bascule automatique avec un mode de concentration

macOS n'expose pas d'API publique pour réagir aux modes de concentration. Docko passe par Raccourcis :

1. Ouvre **Raccourcis** → **Automatisation** → **+**.
2. Choisis le mode de concentration (par exemple « Travail »), déclencheur « À l'activation ».
3. Ajoute l'action **Ouvrir des URL** avec `docko://apply?name=Travail`.
4. Optionnel : une seconde automatisation « À la désactivation » qui ouvre `docko://apply?name=Perso`.

Le nom est comparé sans tenir compte de la casse.

URLs disponibles :

| URL | Effet |
| --- | --- |
| `docko://apply?name=Travail` ou `docko://apply/Travail` | Applique le profil nommé |
| `docko://next` | Applique le profil suivant dans la liste |
| `docko://manage` | Ouvre la fenêtre de gestion |

Depuis un terminal : `open "docko://apply?name=Travail"`.

## Comment ça marche

Docko lit et écrit la clé `persistent-apps` du domaine de préférences `com.apple.dock` via CFPreferences, puis relance le Dock (`killall Dock`). C'est la même approche que `dockutil`. L'app n'est donc pas sandboxée et ne peut pas être distribuée sur le Mac App Store telle quelle.

Les profils sont stockés dans `~/Library/Application Support/Docko/profiles.json`.

## Structure

```
Package.swift                  Swift Package (cible exécutable, macOS 13+)
Sources/Docko/
  main.swift                   Point d'entrée AppKit
  AppDelegate.swift            Status item, menu, schéma d'URL, fenêtre
  DockService.swift            Lecture/écriture de com.apple.dock, redémarrage du Dock
  ProfileStore.swift           Modèle observable + persistance JSON + import/export
  Models.swift                 DockProfile, DockItem
  ManagerView.swift            Fenêtre de gestion (SwiftUI)
  ProfileEditorView.swift      Éditeur d'un profil
  SettingsView.swift           Réglages (démarrage, nom dans la barre, raccourcis)
  HotkeyManager.swift          Raccourcis globaux Carbon (déclencheur puis touche)
  Shortcut.swift, LoginItemService.swift, ColorHex.swift, Prompts.swift
Resources/Info.plist           LSUIElement, schéma d'URL
Makefile                       Assemble le .app
```

## Limites connues

- Les raccourcis globaux passent par `RegisterEventHotKey` (Carbon). Pendant les deux secondes qui suivent ⌘D, les touches des profils sont capturées globalement, puis relâchées.
- Pas d'intégration App Intents : `swift build` n'exécute pas l'extraction de métadonnées d'Xcode, donc les intents ne seraient pas visibles dans Raccourcis. Le schéma d'URL couvre le besoin.
- Les éléments du Dock d'un type inconnu dans `persistent-apps` sont ignorés à la capture.
