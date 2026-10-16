-- The only server entry point. No client request supplies damage or inventory.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

Players.CharacterAutoLoads = false

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "MedievalRemotes"
local remotes = {}
for _, name in ipairs({ "Action", "State", "Effects", "Lobby", "Profile" }) do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotesFolder
	remotes[name] = remote
end
remotesFolder.Parent = ReplicatedStorage

local MapBuilder = require(script.Parent.MapBuilder)
local CombatService = require(script.Parent.CombatService)
local MatchService = require(script.Parent.MatchService)
local ProfileService = require(script.Parent.ProfileService)

local map = MapBuilder.Build()
local combat = CombatService.new(remotes)
local profiles = ProfileService.new(remotes)
local match = MatchService.new(remotes, map, combat, profiles)
local lastReady = {}
local lastFeedback = {}
local buckets = {}
local appearanceConnections = {}
local appearanceQueued = {}
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
	match:AddPlayer(player)
end
Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(function(player)
	lastReady[player] = nil
	lastFeedback[player] = nil
	buckets[player] = nil
	appearanceQueued[player] = nil
	for _, connection in ipairs(appearanceConnections[player] or {}) do connection:Disconnect() end
	appearanceConnections[player] = nil
	match:RemovePlayer(player)
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
			match:SendState(player)
			match:SendLobby(player)
			profiles:SendProfile(player)
		end
	else
		local accepted, reason
		if action == "Invite" or action == "InviteRespond" or action == "InviteCancel" then
			accepted, reason = match:HandleLobbyAction(player, action, payload or {})
		elseif action == "BuySword" or action == "EquipSword" or action == "ChooseFaction" then
			accepted, reason = profiles:HandleAction(player, action, payload or {})
			if accepted then refreshAppearance(player) end
		else
			accepted, reason = combat:HandleAction(player, action, payload or {})
		end
		local text = not accepted and feedback[reason]
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

match:Start()
RunService.Heartbeat:Connect(function(dt)
	combat:Step(dt)
	match:Step(dt)
	profiles:Step(dt)
end)

game:BindToClose(function()
	profiles:Close()
end)

print("[Fer & Fioles] Lobby pret : invitations PvP, cosmetiques et potions Z/X/C.")
