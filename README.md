# Fer & Fioles

Un petit jeu Roblox medieval original : **deux equipes de deux combattants**, uniquement l'epee pour attaquer et trois tailles de potions. Le personnage continue de marcher, courir et sauter pendant les frappes. Il n'y a ni parade, ni blocage, ni coup de pied.

## Jouer dans Roblox Studio

1. [Telechargez le fichier Roblox](releases/FerEtFioles.rbxlx?raw=1), puis ouvrez-le avec **Fichier > Ouvrir depuis un fichier** dans Roblox Studio. [Le ZIP complet](releases/FerEtFioles.zip?raw=1) contient aussi les sources et le fichier dans `FerEtFioles/build/`.
2. Cliquez sur **Jouer / Play**. Apres une attente de 8 secondes, le serveur prepare les quatre combattants avant d'autoriser le combat.
3. Pour tester le PvP complet, lancez un serveur avec **4 joueurs** dans l'onglet **Test**. Les places manquantes sont remplies par des bots au debut de la manche, ce qui permet aussi de tester seul.

Le fichier contient les scripts du jeu. Aucun modele du catalogue, asset payant, plugin, secret, acces HTTP ou DataStore n'est necessaire pour jouer. Le code ne publie rien sur votre compte; vous pourrez enregistrer et publier la place depuis Studio.

## Commandes et regles

| Commande | Action |
| --- | --- |
| Controles Roblox habituels | Se deplacer, orienter la camera et sauter |
| Clic gauche | Coup d'epee : 25 degats, 10 endurance, delai de 0,45 s |
| Maj maintenue | Courir : 1 endurance par seconde en mouvement |
| **Z** | Petite potion : +20 PV, 3 par manche |
| **X** | Potion moyenne : +45 PV, 2 par manche |
| **C** | Grosse potion : +75 PV, 1 par manche |
| Tab | Tableau des scores |

Les boutons a l'ecran permettent aussi d'attaquer, de courir et de boire les potions sur mobile. La touche Z suit `Enum.KeyCode.Z` de Roblox; selon votre disposition clavier, adaptez-la dans `Client.client.luau` si elle entre en conflit avec le deplacement.

- 100 PV et **100 endurance** au depart. Les coups rates coutent aussi 10 endurance.
- L'endurance se regenere de 5/s apres 1,5 s sans depense. Rester immobile avec Maj ne consomme rien.
- Les soins sont limites a 100 PV. Une potion n'est pas consommee a pleine sante. Boire une potion impose **60 secondes de delai commun aux trois tailles** : changer de touche ne contourne pas l'attente. Le compte a rebours est affiche sur les trois boutons.
- Sante, endurance, stocks et disponibilite des potions reviennent au debut de chaque manche. Aucun soin passif.
- Les frappes ne ralentissent pas le personnage. Seule l'epee est animee.
- Aucun degat aux allies. Protection de 3 s au debut du combat, interrompue quand on attaque.
- **Une seule vie par manche**, humains comme bots. Un mort reste spectateur jusqu'a la prochaine manche. La derniere equipe avec au moins un survivant gagne ; une double elimination est une egalite. Le chrono affiche le temps ecoule, sans imposer de limite de duree.
- Le score des equipes compte les manches gagnees. Kills/Deaths indiquent les eliminations individuelles de la session. Rien ne persiste entre serveurs.
- Un joueur qui rejoint pendant le combat attend la prochaine manche en spectateur. Une deconnexion elimine le combattant sans renfort. Au maximum deux combattants par equipe; au-dela de quatre humains, les autres attendent une place. Les bots ne sont jamais remplaces ou ressuscites pendant le combat.

Toutes les valeurs de gameplay se changent dans [`src/shared/Config.luau`](src/shared/Config.luau). Les collisions, portee, angle de frappe, obstacles, degats, soins, stocks et endurance sont controles par le serveur. Les bots sont une aide pour tester, pas une IA avancee.

## Modifier et reconstruire

Sources organisees pour [Rojo](https://rojo.space/). Sur Linux x86_64 :

```sh
make setup    # Rojo 7.7.1 et Luau 0.742, archives officielles verifiees SHA-256
make check    # Compilation de tous les scripts et tests des regles
make build    # Produit build/FerEtFioles.rbxlx
make serve    # Synchronisation de sources avec le plugin Rojo dans Studio
make studio-test # Produit build/StudioSmoke.rbxlx pour les tests d'integration
make package  # Reconstruit les places et le ZIP, puis actualise releases/
```

Sous Windows/macOS, installez Rojo 7.7.1 depuis ses releases officielles puis executez `rojo build default.project.json -o build/FerEtFioles.rbxlx` (creez `build` au besoin). Le fichier `.rbxlx` deja genere s'ouvre directement, sans Rojo.

## Verifications

Les **58 tests CLI passent** : 25 tests de combat, 19 tests de roster 2v2 et 14 tests du vrai service de manches. Ils couvrent depense et regeneration d'endurance, cooldown de 60 s, soins, stocks, protection, filtres de frappe, elimination definitive et transitions de manche. `tools/test-match.py` execute les sources inchangees de MatchService avec des doubles explicites des Instances, du chargement asynchrone, du temps et de la frontiere du combat; il teste notamment les deconnexions, les arrives tardives et le dernier kill differe. Ce test ne simule pas la physique ni la livraison reseau.

La construction Rojo verifie l'assemblage de la place et les dix scripts du jeu compilent. Ces verifications ne remplacent pas l'execution du moteur Roblox : le rendu, la physique, l'interface tactile et le jeu reseau doivent etre verifies dans Roblox Studio.

Les six spawns et le couloir central sont verifies contre les boites de collision exportees; la carte compte 343 pieces. `make studio-test` construit une place distincte : ouvrez-la dans Studio, lancez **Run** et consultez **Output** pour les tests d'integration avec de vrais Humanoids, raycasts et joints d'epee. Ces tests Studio sont fournis mais n'ont pas ete executes dans cet environnement Linux.

La carte est visible avant Play. `make build` la regenere depuis `MapBuilder.luau` avec `tools/export-map.py`, puis l'inclut dans la place. Au lancement, le meme module la reconstruit. Pour conserver une modification de decor, modifiez `MapBuilder.luau` plutot que le modele genere.

Checklist Studio : jouer a quatre clients; attaquer en courant/sautant; verifier 100 puis 90 endurance par frappe et -1/s en sprint; boire Z puis tenter X/C avant 60 s; verifier disponibilite a 60 s sans stock perdu sur refus; eliminer un joueur et attendre sans reaparition; eliminer son coequipier et verifier victoire adverse; verifier le retour des quatre au debut de la manche suivante; connecter/deconnecter un joueur pendant le combat; verifier que les bots morts ne reviennent pas; tenter de frapper a travers un mur ou un allie.

Ce projet reprend les mecaniques simples demandees avec son propre code et ses decors. Il n'inclut pas le code, les cartes ou les assets de Medieval Warfare.
