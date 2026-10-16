-- The only server entry point. No client request supplies damage or inventory.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("MedievalShared"):WaitForChild("Config"))
local worldMode = Config.Game.Mode == "Kingdoms"

Players.CharacterAutoLoads = false

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "MedievalRemotes"
local remotes = {}
for _, name in ipairs({ "Action", "State", "Effects", "Lobby", "Profile", "World" }) do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotesFolder
	remotes[name] = remote
end
remotesFolder.Parent = ReplicatedStorage

local MapBuilder = require(worldMode and script.Parent.WorldMapBuilder or script.Parent.MapBuilder)
local CombatService = require(script.Parent.CombatService)
local SessionService = require(worldMode and script.Parent.WorldService or script.Parent.MatchService)
local ProfileService = require(script.Parent.ProfileService)

local map = MapBuilder.Build()
local combat = CombatService.new(remotes)
local profiles = ProfileService.new(remotes)
local session = SessionService.new(remotes, map, combat, profiles)
local lastReady = {}
local lastFeedback = {}
local buckets = {}
local appearanceConnections = {}
local appearanceQueued = {}
local worldActions = { ChooseKingdom = true, Harvest = true, BuildOutpost = true, SetOutpostSpawn = true }
local feedback = {
	Stamina = "Pas assez d'endurance.",
	FullHealth = "Votre sante est deja au maximum.",
	Empty = "Vous n'avez plus cette potion.",
	Intermission = "Acceptez une demande PvP pour entrer en combat.",
	InsufficientCoins = "Vous n'avez pas assez de pieces.",
	NotOwned = "Achetez cette epee avant de l'equiper.",
	NotLobby = "Cette action est disponible au lobby.",
	ArenaBusy = "L'arene est occupee. Attendez la fin du combat.",
	Busy = "Un des joueurs est deja occupe.",
	Cooldown = "Patientez avant d'envoyer une nouvelle invitation.",
	NotLoaded = "Votre profil est encore en cours de chargement.",
	ProfileUnavailable = "Votre progression n'est pas disponible. Consultez le message du profil.",
	NotInLobby = "Cette action est disponible au lobby.",
	UnknownSword = "Cette epee n'est pas dans la boutique.",
	UnknownFaction = "Choisissez une faction disponible.",
	AlreadyOwned = "Vous possedez deja cette epee.",
	InviteCooldown = "Patientez avant d'envoyer une nouvelle invitation.",
	PlayerBusy = "Ce joueur a deja une invitation en attente.",
	PlayerUnavailable = "Ce joueur n'est pas disponible au lobby.",
	Expired = "Cette invitation a expire.",
	UnknownInvite = "Cette invitation n'est plus disponible.",
	UnknownKingdom = "Choose one of the available kingdoms.",
	AlreadyKingdom = "You already belong to this kingdom.",
	KingdomCooldown = "Wait for the kingdom change cooldown.",
	InCombat = "Rest out of combat before changing kingdom.",
	CombatLocked = "Rest out of combat before changing kingdom.",
	ChooseKingdom = "Choose a kingdom first.",
	HarvestCooldown = "Wait before gathering again.",
	Depleted = "This resource is regrowing. Find another node.",
	OutOfRange = "Move closer to interact.",
	TooFar = "Move closer to interact.",
	Blocked = "There is an obstacle between you and the resource.",
	Obstructed = "There is an obstacle between you and the interaction point.",
	NotOwner = "Your kingdom must control this flag.",
	AlreadyBuilt = "This outpost has already been built.",
	InsufficientWood = "Gather more wood first.",
	InsufficientOre = "Mine more ore first.",
	NotBuilt = "Build this owned outpost before using it as a spawn.",
	Contested = "Clear the enemy from the capture zone first.",
}

local function refreshAppearance(player)
	if appearanceQueued[player] then return end
	appearanceQueued[player] = true
	task.defer(function()
		appearanceQueued[player] = nil
		if player.Parent == Players and player:GetAttribute("Activity") == "Lobby" and player.Character then
			combat:DressCharacter(player, player.Character)
		end
	end)
end

local function addPlayer(player)
	if appearanceConnections[player] then return end
	local connections = {}
	appearanceConnections[player] = connections
	for _, name in ipairs({ "ProfileLoaded", "EquippedSword", "FactionId" }) do
		table.insert(connections, player:GetAttributeChangedSignal(name):Connect(function()
			refreshAppearance(player)
		end))
	end
	profiles:AddPlayer(player)
	session:AddPlayer(player)
end
Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(function(player)
	lastReady[player] = nil
	lastFeedback[player] = nil
	buckets[player] = nil
	appearanceQueued[player] = nil
	for _, connection in ipairs(appearanceConnections[player] or {}) do connection:Disconnect() end
	appearanceConnections[player] = nil
	session:RemovePlayer(player)
	profiles:RemovePlayer(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	addPlayer(player)
end

remotes.Action.OnServerEvent:Connect(function(player, action, payload)
	if player.Parent ~= Players or type(action) ~= "string" or #action > 24 or (payload ~= nil and type(payload) ~= "table") then
		return
	end
	local now = os.clock()
	local bucket = buckets[player] or { At = now, Tokens = 20 }
	bucket.Tokens = math.min(20, bucket.Tokens + (now - bucket.At) * 12)
	bucket.At = now
	buckets[player] = bucket
	if bucket.Tokens < 1 then return end
	bucket.Tokens -= 1
	if action == "Ready" then
		if now - (lastReady[player] or -math.huge) >= 0.5 then
			lastReady[player] = now
			session:SendState(player)
			if not worldMode then session:SendLobby(player) end
			profiles:SendProfile(player)
		end
	else
		local accepted, reason
		if worldMode and worldActions[action] then
			accepted, reason = session:HandleAction(player, action, payload or {})
		elseif not worldMode and (action == "Invite" or action == "InviteRespond" or action == "InviteCancel") then
			accepted, reason = session:HandleLobbyAction(player, action, payload or {})
		elseif action == "BuySword" or action == "EquipSword" or action == "ChooseFaction" then
			accepted, reason = profiles:HandleAction(player, action, payload or {})
			if accepted then refreshAppearance(player) end
		else
			accepted, reason = combat:HandleAction(player, action, payload or {})
		end
		local text = not accepted and feedback[reason]
		if not accepted and reason == "Cooldown" and (action == "Attack" or action == "Harvest") then
			text = "Wait for your sword swing to recover."
		end
		if not accepted and action == "Potion" and reason == "Cooldown" then
			local state = combat:GetState(player)
			local remaining = state and math.max(0, math.ceil((state.PotionReadyAt or 0) - workspace:GetServerTimeNow())) or 0
			text = string.format("Potion disponible dans %d s.", remaining)
		end
		if text and now - (lastFeedback[player] or -math.huge) >= 1.5 then
			lastFeedback[player] = now
			remotes.Effects:FireClient(player, "Toast", { Text = text })
		end
	end
end)

session:Start()
RunService.Heartbeat:Connect(function(dt)
	combat:Step(dt)
	session:Step(dt)
	profiles:Step(dt)
end)

game:BindToClose(function()
	profiles:Close()
end)

print(worldMode and "[Fer & Fioles] Kingdom world ready: sword combat, resources, flags and outposts."
	or "[Fer & Fioles] Lobby ready: PvP invitations, cosmetics and potions Z/X/C.")
