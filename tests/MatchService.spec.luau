-- Run through: python3 tools/test-match.py
-- Only the clock, asynchronous character loading, Instances and combat boundary
-- are doubled. The generator inserts the complete, unchanged production modules.
-- No engine physics, network delivery or Roblox character API is claimed here.
local clock = 0
local scheduled = {}
local deferred = {}
local function resumeThread(thread, ...)
	local ok, yielded = coroutine.resume(thread, ...)
	assert(ok, tostring(yielded))
	if coroutine.status(thread) ~= "dead" and type(yielded) == "table" and yielded.WakeAt then
		table.insert(scheduled, { Thread = thread, At = yielded.WakeAt })
	end
end
local task = {}
function task.spawn(callback, ...)
	local thread = coroutine.create(callback)
	resumeThread(thread, ...)
	return thread
end
function task.defer(callback, ...)
	local args = table.pack(...)
	table.insert(deferred, function() callback(table.unpack(args, 1, args.n)) end)
end
function task.wait(seconds)
	return coroutine.yield({ WakeAt = clock + (seconds or 0.01) })
end
local function pump()
	local work = true
	while work do
		work = false
		local callbacks = deferred
		deferred = {}
		for _, callback in ipairs(callbacks) do task.spawn(callback); work = true end
		for index = #scheduled, 1, -1 do
			if scheduled[index].At <= clock then
				local entry = table.remove(scheduled, index)
				resumeThread(entry.Thread)
				work = true
			end
		end
	end
end
local os = { clock = function() return clock end }
local warn = function(...) print("WARN", ...) end
local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local record = { Callback = callback, Active = true }
			table.insert(listeners, record)
			return { Disconnect = function() record.Active = false end }
		end,
		Fire = function(_, ...)
			for _, record in ipairs(listeners) do
				if record.Active then record.Callback(...) end
			end
		end,
	}
end
local Node = {}
local nodeMeta = {
	__index = function(self, key)
		if key == "Parent" then return rawget(self, "_parent") end
		return Node[key]
	end,
	__newindex = function(self, key, value)
		if key == "Parent" then
			rawset(self, "_parent", value)
			if value then table.insert(value.Children, self) end
		else rawset(self, key, value) end
	end,
}
local function instance(className, name)
	return setmetatable({ ClassName = className, Name = name or className, Children = {}, Attributes = {}, Value = 0 }, nodeMeta)
end
function Node:IsA(className) return self.ClassName == className or className == "Instance" end
function Node:FindFirstChild(name)
	for _, child in ipairs(self.Children) do
		if child.Parent == self and child.Name == name then return child end
	end
	return nil
end
function Node:WaitForChild(name)
	self.WaitCalls = (self.WaitCalls or 0) + 1
	return self:FindFirstChild(name)
end
function Node:FindFirstChildOfClass(className)
	for _, child in ipairs(self:GetChildren()) do if child:IsA(className) then return child end end
	return nil
end
function Node:GetChildren()
	local children = {}
	for _, child in ipairs(self.Children) do if child.Parent == self then table.insert(children, child) end end
	return children
end
function Node:SetAttribute(name, value) self.Attributes[name] = value end
function Node:GetAttribute(name) return self.Attributes[name] end
function Node:PivotTo(position) self.Pivot = position end
function Node:Destroy()
	for _, child in ipairs(self:GetChildren()) do child:Destroy() end
	self.Parent = nil
end
local Players = instance("Players")
function Players:GetPlayers() return self:GetChildren() end
local services = { Players = Players, Teams = instance("Teams"), ReplicatedStorage = instance("ReplicatedStorage") }
local game = { GetService = function(_, name) return assert(services[name], "Unimplemented service: " .. name) end }
local Instance = { new = instance }
local BrickColor = { new = function(color) return color end }
local Color3 = { fromRGB = function(...) return { ... } end }
local Vector3 = { zero = {} }
local Modules = {}
local require = function(module) return assert(Modules[module.Name], "Unknown module: " .. tostring(module.Name)) end
local shared = instance("Folder", "MedievalShared")
shared.Parent = services.ReplicatedStorage
for _, name in ipairs({ "Config", "MatchRules" }) do
	local module = instance("ModuleScript", name)
	module.Parent = shared
end
local function player(name)
	local result = instance("Player", name)
	result.DisplayName = name
	result.CharacterAdded = signal()
	result.CharacterRemoving = signal()
	result.Loads = 0
	result.Parent = Players
	function result:LoadCharacterAsync()
		self.Loads += 1
		assert(not self.LoadThread, "concurrent character loads for one player")
		self.LoadThread = coroutine.running()
		coroutine.yield("AwaitCharacterLoad")
	end
	return result
end
local function character(name)
	local model = instance("Model", name)
	local humanoid = instance("Humanoid", "Humanoid")
	humanoid.Health = 100
	humanoid.DisplayName = name
	humanoid.Parent = model
	local root = instance("Part", "HumanoidRootPart")
	root.Parent = model
	model.Parent = instance("Workspace")
	return model
end
local function completeLoad(subject)
	local thread = assert(subject.LoadThread, "player has no pending load: " .. subject.Name)
	subject.LoadThread = nil
	local model = character(subject.Name .. "Character" .. tostring(subject.Loads))
	subject.Character = model
	subject.CharacterAdded:Fire(model)
	resumeThread(thread)
	pump()
	return model
end
local function combatDouble()
	local combat = { States = {}, Registrations = {}, Enabled = false }
	function combat:Register(subject, model, teamId)
		local state = { Subject = subject, Model = model, TeamId = teamId, Dead = false,
			Humanoid = model:FindFirstChild("Humanoid"), Root = model:FindFirstChild("HumanoidRootPart") }
		self.States[subject] = state
		self.Registrations[subject] = (self.Registrations[subject] or 0) + 1
		return state
	end
	function combat:Unregister(subject) self.States[subject] = nil end
	function combat:GetState(subject) return self.States[subject] end
	function combat:GetStates() return self.States end
	function combat:SetEnabled(enabled) self.Enabled = enabled end
	return combat
end
local function remoteDouble()
	local remote = { Calls = {} }
	function remote:FireAllClients(...) table.insert(self.Calls, table.pack(...)) end
	function remote:FireClient(subject, ...) table.insert(self.Calls, table.pack(...)) end
	return remote
end

-- INSERT_REAL_MODULES_HERE

local Config = Modules.Config
local MatchService = Modules.MatchService
local Rules = Modules.MatchRules
local passed = 0
local function equal(actual, expected, message)
	assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, callback)
	callback()
	passed += 1
	print("PASS " .. name)
end
local function count(dictionary)
	local total = 0
	for _ in pairs(dictionary) do total += 1 end
	return total
end
local function makeContext(names)
	local combat = combatDouble()
	local remotes = { Action = remoteDouble(), State = remoteDouble(), Effects = remoteDouble() }
	local spawns = {}
	for _, teamId in ipairs(Config.TeamOrder) do spawns[teamId] = { teamId .. "Spawn1", teamId .. "Spawn2" } end
	local match = MatchService.new(remotes, { Spawns = spawns }, combat)
	local bots = { PrepareCalls = 0, Created = 0, Models = {} }
	function bots:Cleanup()
		for _, model in ipairs(self.Models) do combat:Unregister(model); model:Destroy() end
		self.Models = {}
	end
	function bots:Prepare(roster, round, epoch)
		self.PrepareCalls += 1
		for id, member in pairs(roster.Members) do
			if member.IsBot then
				local model = character(id)
				table.insert(self.Models, model)
				assert(match:RegisterBot(id, model, member.TeamId, round, epoch), "bot must register in its allocated slot")
				self.Created += 1
			end
		end
	end
	match:SetBotService(bots)
	local humans = {}
	for _, name in ipairs(names) do
		local human = player(name)
		table.insert(humans, human)
		match:AddPlayer(human)
	end
	local context = { Match = match, Combat = combat, Humans = humans, Bots = bots, Remotes = remotes }
	function context:Advance(seconds)
		clock += seconds
		pump()
		self.Match:Step(seconds)
		pump()
	end
	function context:Kill(victim, killer)
		local state = assert(self.Combat:GetState(victim), "missing victim combat state")
		state.Dead = true
		state.Humanoid.Health = 0
		self.Combat.OnDeath(state, killer and self.Combat:GetState(killer) or nil)
	end
	match:Start()
	return context
end

local context = makeContext({ "Alice", "Bob", "Celine", "David" })
local match = context.Match
local humans = context.Humans
local teamA = Config.TeamOrder[1]
local teamB = Config.TeamOrder[2]

test("real MatchService starts in intermission without spawning spectators", function()
	equal(match.Phase, "Intermission")
	equal(context.Combat.Enabled, false)
	for _, human in ipairs(humans) do equal(human.Loads, 0) end
end)

test("preparation allocates exactly four actors and waits for asynchronous loads", function()
	context:Advance(Config.Game.IntermissionSeconds)
	equal(match.Phase, "Preparing")
	equal(count(match.Roster.Members), 4)
	equal(match.Roster.Locked, true)
	for _, human in ipairs(humans) do equal(human.Loads, 1) end
	for index = 1, 3 do completeLoad(humans[index]) end
	context:Advance(0.1)
	equal(match.Phase, "Preparing", "three loaded characters cannot start a battle")
	equal(context.Combat.Enabled, false)
	equal(count(context.Combat.States), 3)
	equal(context.Bots.Created, 0)
end)

test("battle starts only after the fourth valid combatant loads", function()
	completeLoad(humans[4])
	context:Advance(0.1)
	equal(match.Phase, "Battle")
	equal(context.Combat.Enabled, true)
	equal(count(context.Combat.States), 4)
	local alive = Rules.CountAlive(match.Roster)
	equal(alive[teamA], 2)
	equal(alive[teamB], 2)
	for _, human in ipairs(humans) do
		assert(context.Combat:GetState(human).SpawnProtectedUntil >= clock, "protection starts when the entire roster is ready")
	end
end)

test("one death is permanent after both four and ten seconds", function()
	context:Kill(humans[1], humans[2])
	context:Advance(4)
	equal(match.Phase, "Battle")
	equal(humans[1].Loads, 1)
	equal(match:SpawnPlayer(humans[1]), false, "public spawning must refuse a dead actor during Battle")
	context:Advance(6)
	equal(humans[1].Loads, 1)
	equal(Rules.CountAlive(match.Roster)[teamA], 1)
	equal(humans[1]:GetAttribute("Eliminated"), true)
	equal(humans[1]:GetAttribute("Spectating"), true)
	equal(context.Bots.Created, 0, "death must not recruit a replacement bot")
end)

test("an unsolicited character load cannot revive an eliminated member", function()
	local replacement = character("UnsolicitedReset")
	humans[1].Character = replacement
	humans[1].CharacterAdded:Fire(replacement)
	equal(replacement.Parent, nil, "unsolicited character must be destroyed")
	equal(Rules.Get(match.Roster, humans[1]).Eliminated, true)
	equal(Rules.CountAlive(match.Roster)[teamA], 1)
end)

local late = player("LateArrival")
test("a late arrival remains outside the locked round", function()
	match:AddPlayer(late)
	equal(late.Loads, 0)
	equal(late:GetAttribute("Spectating"), true)
	equal(Rules.Get(match.Roster, late), nil)
	equal(context.Combat:GetState(late), nil)
	equal(count(match.Roster.Members), 4)
end)

test("eliminating the second teammate awards the other team one round", function()
	context:Kill(humans[3], humans[2])
	context:Advance(0.1)
	equal(match.Phase, "Intermission")
	equal(match.Winner, teamB)
	equal(match.Scores[teamB], 1)
	equal(match.Scores[teamA], 0)
	equal(context.Combat.Enabled, false)
	equal(count(context.Combat.States), 0)
end)

test("a new round loads four fresh characters and resets elimination", function()
	context:Advance(Config.Game.IntermissionSeconds)
	equal(match.Phase, "Preparing")
	equal(match.Round, 2)
	equal(count(match.Roster.Members), 4)
	for _, human in ipairs(humans) do
		equal(human.Loads, 2)
		equal(human:GetAttribute("Eliminated"), false)
		completeLoad(human)
	end
	equal(late.Loads, 0, "a fifth waiting player is not inserted into a full roster")
	context:Advance(0.1)
	equal(match.Phase, "Battle")
	equal(Rules.CountAlive(match.Roster)[teamA], 2)
	equal(Rules.CountAlive(match.Roster)[teamB], 2)
end)

test("disconnecting a participant eliminates its slot without reinforcement", function()
	match:RemovePlayer(humans[1])
	humans[1].Parent = nil
	context:Advance(10)
	equal(match.Phase, "Battle")
	equal(count(match.Roster.Members), 4)
	equal(Rules.CountAlive(match.Roster)[teamA], 1)
	equal(Rules.Get(match.Roster, humans[1]).Eliminated, true)
	equal(late.Loads, 0)
	equal(Rules.Get(match.Roster, late), nil)
	equal(context.Bots.Created, 0)
end)

test("a waiting player can fill the disconnected slot during the next preparation", function()
	context:Kill(humans[3], humans[2])
	context:Advance(0.1)
	equal(match.Phase, "Intermission")
	context:Advance(Config.Game.IntermissionSeconds)
	equal(match.Phase, "Preparing")
	equal(count(match.Roster.Members), 4)
	equal(Rules.Get(match.Roster, humans[1]), nil)
	assert(Rules.Get(match.Roster, late), "late arrival must enter the next available round")
	equal(late.Loads, 1)
	for index = 2, 4 do completeLoad(humans[index]) end
	completeLoad(late)
	context:Advance(0.1)
	equal(match.Phase, "Battle")
	equal(count(context.Combat.States), 4)
end)

test("bot-filled slots still wait for a human and never refill an eliminated bot", function()
	local solo = makeContext({ "Solo" })
	solo:Advance(Config.Game.IntermissionSeconds)
	equal(solo.Match.Phase, "Preparing")
	equal(solo.Bots.Created, 3)
	equal(count(solo.Match.Roster.Members), 4)
	solo:Advance(0.1)
	equal(solo.Match.Phase, "Preparing", "ready bots cannot start without the loading human")
	completeLoad(solo.Humans[1])
	solo:Advance(0.1)
	equal(solo.Match.Phase, "Battle")
	solo:Kill(solo.Bots.Models[1], solo.Humans[1])
	solo:Advance(10)
	equal(solo.Match.Phase, "Battle")
	equal(solo.Bots.Created, 3)
	equal(count(solo.Match.Roster.Members), 4)
end)

test("a deferred final death still counts its kill and death exactly once", function()
	local delayed = makeContext({ "DeferredA", "DeferredB", "DeferredC", "DeferredD" })
	delayed:Advance(Config.Game.IntermissionSeconds)
	for _, human in ipairs(delayed.Humans) do completeLoad(human) end
	delayed:Advance(0.1)
	local killer = delayed.Humans[2]
	delayed:Kill(delayed.Humans[1], killer)
	local victim = delayed.Humans[3]
	local victimState = assert(delayed.Combat:GetState(victim))
	local killerState = assert(delayed.Combat:GetState(killer))
	-- CombatService marks death immediately and defers its OnDeath callback.
	victimState.Dead = true
	victimState.Humanoid.Health = 0
	delayed:Advance(0.1)
	equal(delayed.Match.Phase, "Intermission", "Step may end the round before the notification runs")
	equal(delayed.Match.Winner, teamB)
	local function statistic(subject, name)
		return subject:FindFirstChild("leaderstats"):FindFirstChild(name).Value
	end
	equal(statistic(killer, "Kills"), 1)
	equal(statistic(victim, "Deaths"), 0)
	delayed.Combat.OnDeath(victimState, killerState)
	equal(statistic(killer, "Kills"), 2)
	equal(statistic(victim, "Deaths"), 1)
	equal(#delayed.Remotes.Effects.Calls, 2, "each actual kill produces one killfeed entry")
	delayed.Combat.OnDeath(victimState, killerState)
	equal(statistic(killer, "Kills"), 2)
	equal(statistic(victim, "Deaths"), 1)
	equal(#delayed.Remotes.Effects.Calls, 2)
	equal(delayed.Match.Scores[teamB], 1)
end)

test("an old load finishing in a new preparation cannot abort or populate that round", function()
	local loading = makeContext({ "LoadingA", "LoadingB", "LoadingC", "LoadingD" })
	loading:Advance(Config.Game.IntermissionSeconds)
	for index = 1, 3 do completeLoad(loading.Humans[index]) end
	local slow = loading.Humans[4]
	equal(slow.Loads, 1)
	loading:Advance(Config.Game.PreparingTimeoutSeconds)
	equal(loading.Match.Phase, "Intermission", "incomplete preparation must time out")
	equal(count(loading.Combat.States), 0)
	loading:Advance(Config.Game.IntermissionSeconds)
	equal(loading.Match.Phase, "Preparing")
	equal(loading.Match.Round, 2)
	equal(slow.Loads, 1, "new character load must wait for the in-flight old call")
	local staleModel = completeLoad(slow)
	equal(staleModel.Parent, nil, "stale result must be destroyed")
	equal(staleModel.WaitCalls or 0, 0, "stale models must be rejected before waiting for missing children")
	equal(loading.Combat:GetState(slow), nil, "old model must not register in the new roster")
	equal(slow.Loads, 2, "the serialized loader must proceed to the new request")
	assert(slow.LoadThread, "fresh request must now be waiting for its own result")
	loading:Advance(0.1)
	equal(loading.Match.Phase, "Preparing", "stale CharacterAdded must not abort the fresh preparation")
	for _, human in ipairs(loading.Humans) do completeLoad(human) end
	loading:Advance(0.1)
	equal(loading.Match.Phase, "Battle")
	equal(count(loading.Combat.States), 4)
	for _, human in ipairs(loading.Humans) do
		equal(human.Loads, 2)
		equal(loading.Combat:GetState(human).Model:GetAttribute("MatchRound"), 2)
	end
end)

test("same-step double elimination produces a draw in the real match service", function()
	local knockout = makeContext({ "DrawA", "DrawB", "DrawC", "DrawD" })
	knockout:Advance(Config.Game.IntermissionSeconds)
	for _, human in ipairs(knockout.Humans) do completeLoad(human) end
	knockout:Advance(0.1)
	for _, state in pairs(knockout.Combat.States) do
		state.Dead = true
		state.Humanoid.Health = 0
	end
	knockout:Advance(0.1)
	equal(knockout.Match.Phase, "Intermission")
	equal(knockout.Match.Winner, nil)
	equal(knockout.Match.Scores[teamA], 0)
	equal(knockout.Match.Scores[teamB], 0)
end)

print(tostring(passed) .. " real MatchService lifecycle tests passed; 0 failed")
