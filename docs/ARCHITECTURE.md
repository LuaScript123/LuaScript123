# Contrat des modules — Fer & Fioles

Jeu Roblox original : elimination **2 contre 2**, epee comme seule attaque. Aucune parade, blocage, coup de pied, classe ou arme secondaire. Mouvement libre pendant la frappe; 100 endurance, -10/coup et sprint -1/s en mouvement. Potions Z petite, X moyenne, C grosse, delai partage de60s apres une consommation reussie. Aucun asset externe ni DataStore.

## Sources et reseau

`src/shared/Config.luau` definit les valeurs. CombatRules et MatchRules sont portables, sans globals Roblox, et executes dans les tests CLI. Rojo monte les modules partages dans `ReplicatedStorage.MedievalShared`.

`Main.server.luau` cree `ReplicatedStorage.MedievalRemotes` avec Action, State, Effects. Action recoit `(action:string,payload:table?)` : Attack `{Aim:Vector3}`, Sprint `{Active:boolean}`, Potion `{Size="Small"|"Medium"|"Large"}`, Ready `{}`. Le serveur choisit cible, degats, ressources et cooldowns; toute autre attaque est refusee.

Effects emet `(kind,payload)` pour Swing, Hit, Potion, Death, Killfeed et Toast. Payload selon effet : Actor/Target Models, Position/Direction Vector3, Damage, Size, Killer/Victim noms, TeamId. Toast est prive avec Text.

## CombatService

`new(remotes)`, Register(subject,model,teamId), Unregister(subject), Act(subject,action,payload), HandleAction(player,action,payload), Step(dt), SetEnabled(bool), GetState(subject), GetStates() dictionnaire. Subject est Player ou Model bot. MatchService possede OnDeath(victimState,killerState?).

Etat : Subject,Model,Humanoid,Root,TeamId,Stamina,Sprinting,Dead,SpawnProtectedUntil,Potions,LastPotionAt (os.clock),PotionReadyAt (heure serveur synchronisee). Attributs Model : Combatant,TeamId,Stamina,MaxStamina,Sprinting,SpawnProtected,PotionsSmall/Medium/Large,PotionReadyAt,PotionCooldown. Le client compte l'attente avec workspace:GetServerTimeNow(); le serveur valide via LastPotionAt. Une nouvelle inscription reinitialise sante/endurance/stocks/cooldown. La protection de3s est recalee au debut reel du combat.

Humanoid.Health est officiel. Epee procedurale R6/R15 avec Motor6D, sans Tool ou asset; seule l'epee est animee, jamais la locomotion. Controle serveur portee/angle/obstacles/equipe et cible unique par coup. Regeneration de sante Roblox desactivee par StarterCharacterScripts.Health.

## MatchService et BotService

Main desactive Players.CharacterAutoLoads. MatchService.new(remotes,map,combat), AddPlayer, RemovePlayer, SpawnPlayer, Start, Step, SendState et GetSpawn conservent l'entree publique. BotService.new(map,combat,match) s'enregistre via match:SetBotService; il expose Prepare,Step,Destroy et son nettoyage. Les bots ont des rigs R6 locaux et utilisent les memes actions et potions que les humains.

Cycle : Intermission8s -> Preparing (combat desactive, maximum20s) -> Battle quand les quatre combattants sont charges. Preparing construit puis verrouille un roster de deux par equipe, donne priorite a quatre humains maximum et remplit les places manquantes par bots si FillWithBots=true. Les callbacks de chargement verifient phase/manche/generation. Echec de preparation : retour en attente, pas de bataille incomplete.

Battle : une seule vie, aucune reaparition/reparation de roster. Mort/deconnexion elimine le membre; bots morts jamais remplaces. Les arrives tardifs et humains en surplus sont spectateurs, sans nouveau combattant. Player.Spectating et Eliminated pilotent l'UI/camera. La derniere equipe vivante gagne, les deux mortes donnent egalite; aucun temps limite. Scores compte les manches gagnees, Kills/Deaths les statistiques individuelles de session. La prochaine preparation recharge les participants et les ressources.

Snapshot State : Phase="Intermission"|"Preparing"|"Battle",TimeLeft pour attente/preparation,Elapsed pour chrono de combat,Round,Alive={Dawn=n,Ember=n},Scores={Dawn=victoires,Ember=victoires},TeamSize=2,Winner?,Message?.

MatchRules : New(teamOrder,teamSize), Add(roster,id,teamId), Lock, SetReady, IsReady, Begin, Eliminate, CountAlive, Resolve, Get. Le roster complet doit etre verrouille et pret avant Begin. Resolve n'annonce jamais de vainqueur avant Begin. L'elimination est idempotente et ne permet pas de retablir un joueur dans une manche en cours.

## Carte et client

MapBuilder.Build retourne Model,Spawns={Dawn={CFrame,...},Ember={CFrame,...}},Center. Carte primitive medievale; tools/export-map.py execute ce meme module pour fournir l'apercu Studio assets/Arena.rbxmx, remplace a Play.

Client : sante/endurance, survivants2/2, victoires, chrono, trois boutons potions+stocks+compte a rebours commun60s, scoreboard Tab, killfeed. Clic attaque, Maj sprint, Z/X/C potions, equivalents tactiles. Mort : attendre prochaine manche, camera spectateur sur un survivant en priorite allie; retour camera propre au prochain personnage. Le client ne modifie jamais sante/endurance officielles.
