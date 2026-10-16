-- The only server entry point. No client request supplies damage or inventory.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

Players.CharacterAutoLoads = false

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "MedievalRemotes"
local remotes = {}
for _, name in ipairs({ "Action", "State", "Effects" }) do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotesFolder
	remotes[name] = remote
end
remotesFolder.Parent = ReplicatedStorage

local MapBuilder = require(script.Parent.MapBuilder)
local CombatService = require(script.Parent.CombatService)
local MatchService = require(script.Parent.MatchService)
local BotService = require(script.Parent.BotService)

local map = MapBuilder.Build()
local combat = CombatService.new(remotes)
local match = MatchService.new(remotes, map, combat)
local bots = BotService.new(map, combat, match)
local lastReady = {}
local lastFeedback = {}
local feedback = {
	Stamina = "Pas assez d'endurance.",
	FullHealth = "Votre sante est deja au maximum.",
	Empty = "Vous n'avez plus cette potion.",
	Intermission = "Le combat commence a la prochaine manche.",
}

Players.PlayerAdded:Connect(function(player)
	match:AddPlayer(player)
end)
Players.PlayerRemoving:Connect(function(player)
	lastReady[player] = nil
	lastFeedback[player] = nil
	match:RemovePlayer(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	match:AddPlayer(player)
end

remotes.Action.OnServerEvent:Connect(function(player, action, payload)
	if type(action) ~= "string" or #action > 20 or (payload ~= nil and type(payload) ~= "table") then
		return
	end
	if action == "Ready" then
		local now = os.clock()
		if now - (lastReady[player] or -math.huge) >= 0.5 then
			lastReady[player] = now
			match:SendState(player)
		end
	else
		local accepted, reason = combat:HandleAction(player, action, payload or {})
		local text = not accepted and feedback[reason]
		if not accepted and action == "Potion" and reason == "Cooldown" then
			local state = combat:GetState(player)
			local remaining = state and math.max(0, math.ceil((state.PotionReadyAt or 0) - workspace:GetServerTimeNow())) or 0
			text = string.format("Potion disponible dans %d s.", remaining)
		end
		local now = os.clock()
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
	bots:Step(dt)
end)

game:BindToClose(function()
	bots:Destroy()
end)

print("[Fer & Fioles] Serveur pret : epee, endurance, potions Z/X/C.")
