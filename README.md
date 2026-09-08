# Docko

Des profils de Dock macOS, changeables depuis la barre des menus.

Un profil enregistre les **apps épinglées** et les **espaceurs** du Dock, et, si tu le souhaites, ses **réglages** (taille, agrandissement au survol, masquage automatique, position, effet de réduction, apps récentes…) et un **fond d'écran**. Docko ne touche ni aux dossiers, ni aux apps récentes, et n'ouvre ni ne ferme aucune application. Tout est stocké en local, aucun compte.

## Fonctionnalités

- Icône dans la barre des menus, sans icône dans le Dock. Un clic sur un profil l'applique.
- Raccourcis clavier globaux, depuis n'importe quelle app : un par profil pour l'appliquer, et un par commande du menu (gérer les profils, enregistrer le Dock, profil suivant, relancer le Dock, quitter…). Chaque raccourci est une combinaison complète (⌃⌥1, ⌘⇧D…) que tu choisis ; aucun n'est défini par défaut. Tout se règle dans la fenêtre de gestion, bouton « Réglages » en bas de la barre latérale.
- Enregistrer le Dock actuel comme nouveau profil (apps et réglages), ou mettre à jour le profil actif depuis le Dock actuel. Les réglages du Dock peuvent être retirés d'un profil pour qu'il ne change que les apps.
- Fenêtre de gestion : renommer, colorer, réordonner les apps par glisser-déposer, ajouter des apps ou des espaceurs, supprimer, dupliquer.
- Fond d'écran optionnel par profil : choisis une image (ou mémorise le fond actuel), elle est appliquée à tous les écrans en même temps que le Dock. Limite macOS : seul le bureau affiché de chaque écran change, pas les autres Spaces ; les fonds dynamiques du système (aériens, couleurs) ne sont pas des images et ne peuvent pas être mémorisés.
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
make zip        # dist/Docko-<version>.zip, prêt à partager
```

Le `.app` est signé ad hoc. Pour que « Lancer au démarrage » et le schéma d'URL fonctionnent de manière fiable, installe l'app dans `/Applications` et lance-la au moins une fois.

Pour donner l'app à quelqu'un, passe toujours par `make zip` : l'archive est faite avec `ditto`, qui conserve le bit d'exécution du binaire et la signature. Un zip ou un transfert (cloud, messagerie) qui les perd rend l'app inouvrable, surtout sur Apple Silicon qui refuse tout binaire non signé. Chez le destinataire, la signature ad hoc ne satisfait pas Gatekeeper : la première fois, clic droit › Ouvrir, ou `xattr -dr com.apple.quarantine Docko.app`. Seule la notarisation Apple (compte développeur) évite cette étape.

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

Le fond d'écran passe par `NSWorkspace.setDesktopImageURL`, appliqué à chaque écran après la relance du Dock. Les images choisies sont copiées dans `~/Library/Application Support/Docko/Wallpapers/` pour que le profil survive au déplacement du fichier d'origine (les images système de `/System/Library/Desktop Pictures` sont référencées telles quelles). Un export JSON contient le chemin de l'image, pas l'image elle-même.

Les profils sont stockés dans `~/Library/Application Support/Docko/profiles.json`.

## Structure

```
Package.swift                  Swift Package (cible exécutable, macOS 13+)
Sources/Docko/
  main.swift                   Point d'entrée AppKit
  AppDelegate.swift            Status item, menu, schéma d'URL, fenêtre
  DockService.swift            Lecture/écriture de com.apple.dock, redémarrage du Dock
  WallpaperService.swift       Copie et application du fond d'écran d'un profil
  ProfileStore.swift           Modèle observable + persistance JSON + import/export
  Models.swift                 DockProfile, DockItem
  ManagerView.swift            Fenêtre de gestion (SwiftUI)
  ProfileEditorView.swift      Éditeur d'un profil
  SettingsView.swift           Réglages (démarrage, nom dans la barre, raccourcis), dans la fenêtre de gestion
  AppCommand.swift             Commandes de l'app auxquelles on peut associer un raccourci
  HotkeyManager.swift          Raccourcis globaux Carbon (profils et commandes)
  Shortcut.swift, LoginItemService.swift, ColorHex.swift, Prompts.swift
Resources/Info.plist           LSUIElement, schéma d'URL
Makefile                       Assemble le .app
```

## Limites connues

- Les raccourcis globaux passent par `RegisterEventHotKey` (Carbon), enregistrés en permanence. Ils exigent un modificateur et aucun n'est défini par défaut : un ⌘Q ou un « 1 » global confisquerait la touche à tout le système. Les touches seules des anciennes versions (jouées après ⌘D) sont ignorées au chargement.
- Pas d'intégration App Intents : `swift build` n'exécute pas l'extraction de métadonnées d'Xcode, donc les intents ne seraient pas visibles dans Raccourcis. Le schéma d'URL couvre le besoin.
- Les éléments du Dock d'un type inconnu dans `persistent-apps` sont ignorés à la capture.
