> Historical lobby-mode documentation. The current default kingdom world, health regeneration and world systems are documented in [KINGDOM_WORLD.md](KINGDOM_WORLD.md). The earlier no-regeneration/lobby-only requirements below have been superseded by the current request.

# Architecture — Fer & Fioles Lobby PvP

Le contrat courant est decrit dans [LOBBY_CONTRACT.md](LOBBY_CONTRACT.md).

Main cree cinq RemoteEvents sous ReplicatedStorage.MedievalRemotes : Action, State, Effects, Lobby et Profile. Les modules partages sont sous MedievalShared. Les joueurs apparaissent au lobby avec un vrai personnage, protege et non enregistre au combat. MatchService ne charge l'arene qu'apres une invitation acceptee par tous les participants.

## Cycle

Lobby -> Preparing -> Battle -> Results -> Lobby. Duel : 1 par equipe; Teams : 2 par equipe. Invitations : 15s de cooldown, 25s d'expiration. Une seule arene et uniquement des humains. MatchRules verrouille le roster jusqu'au resultat. Les autres joueurs gardent leur personnage dans le lobby; aucun balayage global des personnages. LoadCharacterAsync est serialise et les generations perimees sont rejetees avant WaitForChild. Le dernier kill differe reste comptabilise pendant Results.

## Progression

ProfileService est seul proprietaire des pieces, achats et choix; ProfileRules utilise le catalogue serveur. Un GUID distingue chaque combat termine. Recompenses idempotentes et aucune recompense au KO, au forfait ou a une preparation echouee. DataStore utilise un bail de session; loadfail ou bail etranger ne permettent jamais de sauvegarder des valeurs par defaut. Le mode Studio sans DataStore reste explicitement une session locale.

## Combat et presentation

CombatService ne contient que les participants. Toutes les epees ont les stats de Config.Combat. Les frappes alternees1/-1 animent uniquement le Motor6D de l'epee. DressCharacter ajoute les cosmetiques au lobby sans inscrire le personnage au combat ni toucher aux ressources. Catalog est visuel uniquement.

Client.client integre LobbyUI et CameraLock. Ctrl active un offset camera et une orientation joueur sans remplacer le controleur camera Roblox; menus/chat/focus/spectateur suspendent le verrouillage. Le client ne decide jamais des degats, pieces, stocks ou achats.

MapBuilder genere lobby et arene dans FerEtFiolesArena. L'export CLI utilise ce module exact et valide14spawns; aucune deuxieme definition de carte a maintenir. La place .rbxlx et le ZIP dans releases sont generes par make package et livres via GitHub.
