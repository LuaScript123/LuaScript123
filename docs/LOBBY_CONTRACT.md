> Historical lobby-mode documentation. The current default kingdom world, health regeneration and world systems are documented in [KINGDOM_WORLD.md](KINGDOM_WORLD.md). The earlier no-regeneration/lobby-only requirements below have been superseded by the current request.

# Lobby PvP, progression et controles

Conserver epee seule, aucun block/parry/kick, mouvement libre, stamina100/-10coup/-1s sprint, potions ZXC et cooldown COMMUN60. Pas de clan/classement maintenant. Lien YouTube inaccessible (403), ne pas pretendre avoir vu la video.

## Modules et responsabilites

Main cree remotes existants Action/State/Effects plus `Lobby` et `Profile` (RemoteEvents). MapBuilder.Build retourne aussi `LobbySpawns={CFrame,...}`, `LobbyCenter=Vector3`. Arena Spawns/Center existants inchanges. Main initialise ProfileService.new(remotes), CombatService.new(remotes), MatchService.new(remotes,map,combat,profiles). AUCUN BotService instancie; aucun combat automatique. Join: profiles:AddPlayer puis match:AddPlayer (tous deux non bloquants, Match attend ProfileLoaded avant d'autoriser invitations si besoin). Leave: match:RemovePlayer puis profiles:RemovePlayer; Step combat/match/profiles; fermeture profiles:Close().

Player.Activity = `Lobby`|`Preparing`|`Battle`|`Results`. Player.Spectating/Eliminated/TeamId selon match. Lobby = personnage physique, non enregistre au combat, aucune depense/attaque/soin possible. Profil peut se charger asynchroniquement mais lobby doit apparaitre. Catalog et Config sont des modules pure Lua dans MedievalShared.

## Invitations (MatchService + InvitationRules)

Mode `Duel` = host Dawn vs OpponentUserId Ember. Mode `Teams` = host+AllyUserId Dawn vs OpponentUserId+OpponentAllyUserId Ember. Tous humains reels presents au lobby, IDs uniques, profil charge, pas occupes/reserves. Aucun NPC et aucun remplissage automatique. Mode utilise selon precision utilisateur; defaut les deux pour conserver 2v2 et offrir 1v1.

Actions vers Match: `Invite` {Mode,OpponentUserId,AllyUserId?,OpponentAllyUserId?}, `InviteRespond` {InviteId:string,Accept:boolean}, `InviteCancel` {InviteId:string}. Root route si action commence Invite. Serveur valide, cooldown host15s en temps monotone, expiration25s, une invitation en attente par joueur, declin/annulation/depart/expiration libere tous. Tous les invites doivent accepter avant le chargement. Une seule arene active; ArenaBusy refuse nouvelle invitation (pending peut etre annulee si une autre partie demarre d'abord). MatchRules supporte taille1 ou2 selon mode. Roster de manche verrouille.

`Lobby:FireClient(player, snapshot)` personnel : {Players={{UserId,Name,DisplayName,Activity,FactionId,Busy:boolean}},InviteCooldownUntil:number (GetServerTimeNow),Incoming={Id,HostName,Mode,ExpiresAt:number,Members={{Name,TeamId,Accepted}}}?,Outgoing=memeforme?,ArenaBusy:boolean}. Snapshot actualise au Ready, chaque changement et periodiquement1s. Invitations UI doivent se baser sur UserId, jamais nom client. Methods Match : AddPlayer/RemovePlayer/Start/Step/SendState/SendLobby/HandleLobbyAction/GetSpawn; anciens autres internes a choix agent.

Cycle Lobby -> Preparing (20s maximum, combat desactive) -> Battle jusqu'a elimination -> Results6s -> retour Lobby, pas de nouvelle manche automatique. Mort spectateur de son combat, aucune reaparition avant retour lobby; autres joueurs restent dans lobby vivants. Les depart sont forfait (aucune recompense pour ce combat). Toute preparation avortee retourne les participants au lobby et ne recompense personne. Protection3sec rebasee au debut. Anciens callbacks et LoadCharacterAsync obsoletes doivent etre rejetes avant WaitForChild. Roster guard contre nouveaux arrivants. Les joueurs non participants ne sont jamais touches par un SetSpectating global ou cleanup global des caracteres. Combat:GetStates ne contient que participants actifs.

`State` conserve Phase (Lobby|Preparing|Battle|Results),TimeLeft/Elapsed,Round,Alive,Scores (victoires session),TeamSize,Winner,Message; envoyer aussi `Participants={userId,...}` optionnel. Client decide son interface par Activity: lobby affiche lobby UI, seuls participants voient overlay match. Profil et lobby remotes supplementaires.

Fin valide par elimination avec humains presents: `profiles:AwardMatch(matchId:string, roster, winnerTeam:string?)` une fois. `roster` est MatchRules.Members, chaque membre .Id Player, .TeamId, .IsBot=false. Pas d'appel pour abandon/preparation echouee; aucune recompense au KO ni remote. Seul ProfileService modifie coins.

## Profil et boutique (ProfileService + ProfileRules)

API ProfileService.new(remotes), AddPlayer(player), RemovePlayer(player), Step(dt), Close(), SendProfile(player), HandleAction(player,action,payload), AwardMatch(matchId,roster,winner). Async charge/sauve dans DataStore UpdateAsync avec lease session, autosave60/leave/shutdown. Studio non publie ou API unavailable: mode session explicite, aucune sauvegarde ne doit ecraser un profil dont load a echoue. Profil lu sur autre session occupe: commerce refuse plutot qu'ecraser, eviter save defaults. Validations strictes client. Operations en memoire sans yield, par profil pour depense. Lease expire180s renouvele autosave. Source de verite pure ProfileRules (New/Sanitize/Buy/Equip/ChooseFaction/Reward) sans globalsRoblox, API exacte a annoncer tests.

Actions `BuySword` {SwordId},`EquipSword` {SwordId},`ChooseFaction` {FactionId}, uniquement Activity Lobby et ProfileLoaded. Owned starterIron, coins0, factions libres. Catalogue Config.Catalog module Catalog. Stock cosmetic uniquement, toutes stats combat restent Config.Combat (pas de Damage/Range par sword). Recompense Win50/Loss10/Draw10, idempotence MatchId. Profil conserve Coins,OwnedSwords,EquippedSword,FactionId,Wins,Losses. Attributes Player: ProfileLoaded,Coins,EquippedSword,FactionId,SaveMode (Persistent|Session|Unavailable). Profile payload {Loaded,Coins,OwnedSwords={id=true},EquippedSword,FactionId,Wins,Losses,SaveMode,Message?}. Invoke `combat:DressCharacter(player,player.Character)` apres succes equip/faction au lobby depuis Main.

## Cosmetiques et animations (CombatService)

`DressCharacter(player,model)` affiche une epee cosmetique+armure faction en lobby SANS combat:Register, ne modifie pas resources, remplace proprement FerSword/FerFaction et FerSwordGrip. Register utilise attributes EquippedSword/FactionId pour joueur; stats identiques pour tous. Bots heritage peuvent defautIron si tests. Une seule animation gauche->droite et miroir droite->gauche alternant a chaque frappe ACCEPTEE. Tween joints/epee uniquement, aucune restriction locomotion. Payload Swing ajoute Side=1|-1; agentclient traces reflettent direction. Pas d'assets ni AnimationId requis; valider que seuls ces2chemins existent.

## Client

Client.client peut utiliser modules LobbyUI.luau et CameraLock.luau a choix, dossiers Rojo shared nom correct. Ecran lobby clair: liste joueurs, duel bouton, selection allie/adversaires pour2v2, demandes recus/accepter/refuser/annuler + timer/CD, onglets boutique et factions, coins, equip/achete. Images seulement formes/couleurs originales, pas d'assets externes. Clans mention optionnel "a venir", aucun fauxclassement.

Ctrl gauche/droit toggle shiftlock natif-equivalent (centre souris, offset epaule, AutoRotatefalse+orientationyawcamera) avec camera Roblox conservee. Shift sprint reste. Menus/chat/focusperdu libere souris+AutoRotate provisoirement et restaure mode; ne pas rendre UI impossibleaclquer. Controle surmobile bouton si utile. Respawn/spectateur restaurecamera propre. LobbyUI ouvert = shiftlock suspendu, quand UI fermee retombeleCtrl. HUD match existant potions60+endurance. ActivityLobby ne doit PAS etre spectateur sans personnage. Action client jamaisbalancecoins/hits.

## Verification et livraison

58tests actuels a conserver quand toujours pertinents. Anciens tests MatchService automatic rounds doivent etre adaptes a invitations et lobby (pas juste desactives). Nouveaux tests invitations (CD/expiration/consent/reservation/depart),cosmeticprofile achat/idempotence/ownership/equalstats/persistencefakes, lifecyclematch. CLI Luau et Rojo deja .tools/bin. Generateurmap/exportstub a adapter au lobby. make check package puis commit/push GitHub autorise deja par user pour versionslivrables; pas publication Roblox automatique.
