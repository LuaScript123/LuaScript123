# Fer & Fioles — Lobby PvP

Jeu Roblox medieval original avec lobby, demandes de combat **1v1 ou 2v2**, pieces et epees cosmetiques. Aucun combat automatique ou farming de PNJ. L'epee est la seule attaque : deux frappes horizontales alternees, aucune parade ni coup de pied, deplacement libre.

## Telecharger et jouer

1. [Telechargez le ZIP de la nouvelle version](releases/FerEtFioles.zip?raw=1) et decompressez-le.
2. Dans **Roblox Studio > Fichier > Ouvrir depuis un fichier**, ouvrez `FerEtFioles/build/FerEtFioles.rbxlx`. [Le fichier Roblox seul](releases/FerEtFioles.rbxlx?raw=1) est aussi disponible.
3. Lancez **Play**. Vous apparaissez dans le lobby; le bouton **MENU PvP** ouvre les demandes, la boutique et les factions.
4. Dans l'onglet **Test**, lancez un serveur avec **2 joueurs** pour un duel ou **4 joueurs** pour un 2v2. Les autres doivent etre dans le meme serveur : aucun bot ne remplit une place.

Le fichier contient la carte et les scripts; aucun modele du catalogue ou asset payant n'est necessaire. Vous pouvez publier la place depuis Studio sur votre compte.

## Invitations et combats

- **Duel** : choisissez un adversaire dans la liste, puis envoyez la demande.
- **2v2** : choisissez votre allie et deux adversaires. Les trois joueurs doivent accepter.
- Delai de **15 secondes** entre vos invitations; une demande expire apres **25 secondes**. Refuser, annuler ou quitter libere tous les joueurs concernes.
- Une arene fonctionne a la fois; les autres joueurs restent libres dans le lobby. Une invitation acceptee teleporte uniquement ses participants.
- Une seule vie par combat. Apres une mort, vous regardez les survivants jusqu'au resultat. La derniere equipe en vie gagne; une double elimination est une egalite.
- Les resultats restent affiches 6 secondes, puis les participants retournent au lobby. Aucun nouveau combat ne commence sans invitation acceptee.
- Quitter pendant un combat donne un forfait, sans pieces pour ce combat. Une preparation annulee ne donne aucune recompense.

## Commandes

| Touche | Action |
| --- | --- |
| Controles Roblox habituels | Marcher, camera et saut |
| Clic gauche | Frapper, alternativement gauche-droite puis droite-gauche |
| Maj maintenue | Sprint pendant le combat |
| **Ctrl gauche ou droit** | Activer/desactiver le verrouillage camera a l'epaule |
| **Z** | Petite potion : +20 PV, 3 par combat |
| **X** | Potion moyenne : +45 PV, 2 par combat |
| **C** | Grosse potion : +75 PV, 1 par combat |
| Tab | Tableau des joueurs |

Le menu, le chat et le mode spectateur liberent temporairement la souris. Fermer le menu restaure le verrouillage Ctrl. Les boutons tactiles sont aussi disponibles. Les touches potions utilisent les KeyCode Roblox; adaptez-les dans le client au besoin selon votre clavier.

Chaque combattant commence avec **100 PV et 100 endurance**. Une frappe coute 10 endurance et inflige 25 degats, avec 0,45 s entre les coups. Le sprint consomme 1 endurance/s en mouvement. L'endurance revient a 5/s apres 1,5 s sans depense. Les trois potions partagent **60 secondes** de cooldown, affiche sur les boutons. Les soins sont plafonnes a 100 PV et ne consomment rien a pleine sante. Les ressources reviennent au debut de chaque combat. Aucun soin passif, aucun degat aux allies. Le lobby est protege et ne permet pas d'attaquer.

## Pieces, boutique et factions

Un combat termine par elimination attribue **50 pieces aux gagnants**, **10 aux perdants**, ou **10 a chacun en cas d'egalite**. Le serveur calcule et attribue la recompense une fois par combat; le client ne peut pas choisir les montants.

| Epee | Prix |
| --- | ---: |
| Epee de fer | Gratuite au depart |
| Lame Redcliff | 100 |
| Croc Korblox | 150 |
| Acier Greywolf | 200 |
| Oeil Overseer | 250 |

Les epees ont toutes exactement les memes degats, portee, vitesse et cout d'endurance. Seuls les couleurs et les details visuels changent. Achetez puis equipez l'epee dans la boutique du lobby.

Choisissez gratuitement **Redcliff, Korblox, Greywolf ou Overseer** dans l'onglet Factions. Chaque choix applique une armure originale faite de primitives, sans avantage de combat. La faction est independante de l'equipe bleue/rouge du match. Les clans et leur classement restent prevus pour une prochaine version.

## Sauvegarde

Sur une experience Roblox publiee, les pieces, epees possedees, epee equipee, faction et victoires/defaites utilisent DataStoreService. Bail de session, sauvegarde automatique toutes les 60 s, au depart et a la fermeture. Un echec de chargement ou un profil deja ouvert ne remplace jamais les donnees par un profil vide.

Dans Studio non publie, ou si l'acces DataStore echoue, un message **Mode session** indique que ces choix ne sont pas conserves en quittant. Pour tester la persistance dans Studio, publiez l'experience puis activez **Parametres du jeu > Securite > Activer l'acces Studio aux services API**. L'option HTTP n'est pas necessaire.

## Developpement et validation

```sh
make setup       # Rojo 7.7.1 et Luau 0.742, archives verifiees SHA-256
make check       # Compiler les sources et executer les tests
make build       # Regenerer carte + build/FerEtFioles.rbxlx
make studio-test # Place separee avec smoke tests du moteur Roblox
make package     # Reconstruire places, ZIP et copies dans releases/
make serve       # Synchroniser les sources avec le plugin Rojo
```

Sous Windows/macOS, le fichier .rbxlx fourni s'ouvre sans Rojo. Pour reconstruire depuis les sources, installez Rojo et executez `rojo build default.project.json -o build/FerEtFioles.rbxlx` (creez build au besoin). Le modele genere dans assets contient deja le lobby.

**113 tests CLI reussis** : 26 combat, 19 rosters, 18 invitations, 15 regles de profil, 20 scenarios du service de matchs et 15 scenarios du service de profils. Les tests de services executent les vraies sources avec des doubles explicites de temps, personnages et DataStore; ils ne simulent pas la physique ni le reseau Roblox. La carte compte 538 primitives, avec 14 spawns et leurs sols verifies. Les scripts compilent et Rojo construit les places.

Le moteur Roblox n'est pas disponible dans cet environnement Linux : animations, camera, interface tactile, jeu multijoueur et vraie persistance restent a verifier dans Studio. La video de reference YouTube n'etait pas accessible depuis l'environnement; le jeu suit les precisions ecrites de la demande et utilise ses propres decors et assets proceduraux.

Valeurs de jeu : `src/shared/Config.luau`. Prix, factions et couleurs : `src/shared/Catalog.luau`. Geometrie : `src/server/MapBuilder.luau`; modifier ce module plutot que le modele genere, qui est reconstruit a Play.
