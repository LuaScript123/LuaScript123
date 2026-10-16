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
local guid = 0
local services = { Players = Players, Teams = instance("Teams"), ReplicatedStorage = instance("ReplicatedStorage"),
    Workspace = { GetServerTimeNow = function() return 100000 + clock end },
    HttpService = { GenerateGUID = function() guid += 1; return "match-guid:" .. tostring(guid) end } }

local game = { GetService = function(_, name) return assert(services[name], "Unimplemented service: " .. name) end }
local Instance = { new = instance }
local BrickColor = { new = function(color) return color end }
local Color3 = { fromRGB = function(...) return { ... } end }
local Vector3 = { zero = {} }
local Modules = {}
local require = function(module) return assert(Modules[module.Name], "Unknown module: " .. tostring(module.Name)) end
local shared = instance("Folder", "MedievalShared")
shared.Parent = services.ReplicatedStorage
for _, name in ipairs({ "Config", "MatchRules", "InvitationRules" }) do
	local module = instance("ModuleScript", name)
	module.Parent = shared
end
local userSerial = 0
local function player(name)
	userSerial += 1
	local result = instance("Player", name)
	result.DisplayName = name
	result.UserId = userSerial
	result:SetAttribute("ProfileLoaded", true)
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
	local combat = { States = {}, Registrations = {}, Dressed = {}, Enabled = false }
	function combat:DressCharacter(subject, model) self.Dressed[subject] = model end
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
	function remote:FireClient(subject, ...) local call = table.pack(...); call.Subject = subject; table.insert(self.Calls, call) end
	return remote
end

-- INSERT_REAL_MODULES_HERE
local Config, Rules, MatchService = Modules.Config, Modules.MatchRules, Modules.MatchService
local passed = 0
local teamA, teamB = Config.TeamOrder[1], Config.TeamOrder[2]
local function equal(a, b, message) assert(a == b, (message or "unexpected value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, callback) callback(); passed += 1; print("PASS " .. name) end
local function count(values) local n = 0; for _ in pairs(values) do n += 1 end; return n end
local function makeContext(names)
    local combat = combatDouble()
    local remotes = {Action = remoteDouble(), State = remoteDouble(), Effects = remoteDouble(), Lobby = remoteDouble()}
    local profiles = {Awards = {}}
    function profiles:AwardMatch(id, roster, winner) table.insert(self.Awards, {Id = id, Roster = roster, Winner = winner}); return true end
    local spawns = {}
    for _, teamId in ipairs(Config.TeamOrder) do spawns[teamId] = {teamId .. "Spawn1", teamId .. "Spawn2"} end
    local match = MatchService.new(remotes, {Spawns = spawns, LobbySpawns = {"LobbySpawn1", "LobbySpawn2"}}, combat, profiles)
    local ctx = {Match = match, Combat = combat, Remotes = remotes, Profiles = profiles, Humans = {}}
    for _, name in ipairs(names) do local human = player(name); table.insert(ctx.Humans, human); match:AddPlayer(human); completeLoad(human) end
    function ctx:Advance(seconds) clock += seconds; pump(); self.Match:Step(seconds); pump() end
    function ctx:Lobby(who)
        for index = #self.Remotes.Lobby.Calls, 1, -1 do local call = self.Remotes.Lobby.Calls[index]; if call.Subject == who then return call[1] end end
        error("missing lobby snapshot")
    end
    function ctx:Invite(mode, members)
        members = members or self.Humans
        local payload = {Mode = mode, OpponentUserId = (mode == "Duel" and members[2] or members[3]).UserId}
        if mode == "Teams" then payload.AllyUserId = members[2].UserId; payload.OpponentAllyUserId = members[4].UserId end
        local accepted, reason = self.Match:HandleLobbyAction(members[1], "Invite", payload)
        assert(accepted, "invite refused: " .. tostring(reason))
        local invite = assert(self:Lobby(members[1]).Outgoing)
        return invite.Id
    end
    function ctx:Prepare(mode, members)
        members = members or self.Humans
        local id = self:Invite(mode, members)
        local last = mode == "Duel" and 2 or 4
        for index = 2, last do assert(self.Match:HandleLobbyAction(members[index], "InviteRespond", {InviteId = id, Accept = true})) end
        equal(self.Match.Phase, "Preparing")
    end
    function ctx:Battle(mode, members)
        members = members or self.Humans; self:Prepare(mode, members)
        local last = mode == "Duel" and 2 or 4
        for index = 1, last do completeLoad(members[index]) end
        self:Advance(0.1); equal(self.Match.Phase, "Battle")
    end
    function ctx:Kill(victim, killer)
        local state = assert(self.Combat:GetState(victim)); state.Dead = true; state.Humanoid.Health = 0
        self.Combat.OnDeath(state, killer and self.Combat:GetState(killer) or nil)
    end
    match:Start()
    return ctx
end

local context = makeContext({"Alice", "Bob", "Celine", "David"})
local match, humans = context.Match, context.Humans

test("humans spawn in a physical protected lobby with no automatic battle", function()
    equal(match.Phase, "Lobby"); equal(context.Combat.Enabled, false)
    for _, human in ipairs(humans) do
        equal(human.Loads, 1); equal(human:GetAttribute("Activity"), "Lobby"); equal(human:GetAttribute("Spectating"), false)
        equal(context.Combat:GetState(human), nil); equal(context.Combat.Dressed[human], human.Character)
        assert(human.Character:FindFirstChild("LobbyProtection"))
    end
    context:Advance(120); equal(match.Phase, "Lobby"); equal(match.Roster, nil)
    for _, human in ipairs(humans) do equal(human.Loads, 1) end
end)

test("two versus two starts loading only after every invited human consents", function()
    local id = context:Invite("Teams")
    for index = 2, 3 do
        assert(match:HandleLobbyAction(humans[index], "InviteRespond", {InviteId = id, Accept = true}))
        equal(match.Phase, "Lobby")
        for _, human in ipairs(humans) do equal(human.Loads, 1) end
    end
    assert(match:HandleLobbyAction(humans[4], "InviteRespond", {InviteId = id, Accept = true}))
    equal(match.Phase, "Preparing"); equal(count(match.Roster.Members), 4); equal(match.Roster.Locked, true)
    equal(Rules.Get(match.Roster, humans[1]).TeamId, teamA); equal(Rules.Get(match.Roster, humans[2]).TeamId, teamA)
    equal(Rules.Get(match.Roster, humans[3]).TeamId, teamB); equal(Rules.Get(match.Roster, humans[4]).TeamId, teamB)
    for _, human in ipairs(humans) do equal(human.Loads, 2); equal(human:GetAttribute("Activity"), "Preparing") end
end)

test("the arena remains disabled until all four asynchronous loads are valid", function()
    for index = 1, 3 do completeLoad(humans[index]) end
    context:Advance(0.1); equal(match.Phase, "Preparing"); equal(context.Combat.Enabled, false); equal(count(context.Combat.States), 3)
    completeLoad(humans[4]); context:Advance(0.1)
    equal(match.Phase, "Battle"); equal(context.Combat.Enabled, true); equal(count(context.Combat.States), 4)
    equal(Rules.CountAlive(match.Roster)[teamA], 2); equal(Rules.CountAlive(match.Roster)[teamB], 2)
    for _, human in ipairs(humans) do
        equal(human:GetAttribute("Activity"), "Battle")
        assert(context.Combat:GetState(human).SpawnProtectedUntil >= clock + Config.Game.SpawnProtectionSeconds - 0.001)
    end
end)

test("an eliminated member remains dead and cannot request a battle respawn", function()
    context:Kill(humans[1], humans[3]); context:Advance(4)
    equal(match.Phase, "Battle"); equal(match:SpawnPlayer(humans[1]), false)
    context:Advance(6); equal(humans[1].Loads, 2); equal(Rules.CountAlive(match.Roster)[teamA], 1)
    equal(humans[1]:GetAttribute("Eliminated"), true); equal(humans[1]:GetAttribute("Spectating"), true)
    equal(count(match.Roster.Members), 4)
end)

test("unsolicited character loads cannot revive dead members", function()
    local replacement = character("UnsolicitedReset"); humans[1].Character = replacement; humans[1].CharacterAdded:Fire(replacement)
    equal(replacement.Parent, nil); equal(Rules.Get(match.Roster, humans[1]).Eliminated, true)
    equal(Rules.CountAlive(match.Roster)[teamA], 1)
end)

local late = player("LateVisitor")
local lateModel

test("a late visitor stays alive in the lobby outside the locked arena roster", function()
    match:AddPlayer(late); lateModel = completeLoad(late)
    equal(late:GetAttribute("Activity"), "Lobby"); equal(late:GetAttribute("Spectating"), false)
    equal(context.Combat:GetState(late), nil); equal(Rules.Get(match.Roster, late), nil)
    equal(count(match.Roster.Members), 4); equal(late.Loads, 1)
    assert(lateModel.Parent)
end)

test("elimination rewards one completed match and Results touch only participants", function()
    context:Kill(humans[2], humans[3]); context:Advance(0.1)
    equal(match.Phase, "Results"); equal(match.Winner, teamB); equal(match.Scores[teamB], 1)
    equal(context.Combat.Enabled, false); equal(count(context.Combat.States), 0)
    equal(#context.Profiles.Awards, 1); equal(context.Profiles.Awards[1].Winner, teamB)
    for _, human in ipairs(humans) do equal(human:GetAttribute("Activity"), "Results") end
    equal(late:GetAttribute("Activity"), "Lobby"); equal(late.Character, lateModel); assert(lateModel.Parent)
    context:Advance(1); equal(#context.Profiles.Awards, 1)
end)

test("results return participants to the lobby without recruiting or restarting", function()
    context:Advance(Config.Game.ResultSeconds)
    equal(match.Phase, "Lobby"); equal(match.Roster, nil)
    for _, human in ipairs(humans) do
        equal(human:GetAttribute("Activity"), "Lobby"); equal(human:GetAttribute("Spectating"), false)
        equal(human:GetAttribute("TeamId"), nil); completeLoad(human); equal(human.Loads, 3)
    end
    equal(late.Loads, 1); equal(late.Character, lateModel); assert(lateModel.Parent)
    context:Advance(120); equal(match.Phase, "Lobby"); equal(count(context.Combat.States), 0)
    equal(#context.Profiles.Awards, 1)
end)

test("a duel contains exactly its two consenting humans with no bots or lobby visitors", function()
    local ctx = makeContext({"DuelA", "DuelB", "VisitorA", "VisitorB"})
    ctx:Battle("Duel")
    equal(ctx.Match.Roster.TeamSize, 1); equal(count(ctx.Match.Roster.Members), 2); equal(count(ctx.Combat.States), 2)
    for index = 1, 2 do equal(Rules.Get(ctx.Match.Roster, ctx.Humans[index]).IsBot, false) end
    for index = 3, 4 do equal(ctx.Humans[index].Loads, 1); equal(ctx.Humans[index]:GetAttribute("Activity"), "Lobby") end
    ctx:Kill(ctx.Humans[1], ctx.Humans[2]); ctx:Advance(0.1)
    equal(ctx.Match.Phase, "Results"); equal(ctx.Match.Winner, teamB); equal(#ctx.Profiles.Awards, 1)
end)

test("lobby invite snapshots use server deadlines and show incoming only to their recipients", function()
    local ctx = makeContext({"ClockA", "ClockB", "ClockVisitor"}); local id = ctx:Invite("Duel")
    local own, incoming, visitor = ctx:Lobby(ctx.Humans[1]), ctx:Lobby(ctx.Humans[2]), ctx:Lobby(ctx.Humans[3])
    equal(own.Outgoing.Id, id); equal(own.Incoming, nil); equal(incoming.Incoming.Id, id); equal(incoming.Outgoing, nil)
    equal(own.InviteCooldownUntil, 100000 + clock + 15); equal(own.Outgoing.ExpiresAt, 100000 + clock + 25)
    equal(visitor.Incoming, nil); equal(visitor.Outgoing, nil); equal(visitor.ArenaBusy, false)
    equal(own.Outgoing.Members[1].TeamId, teamA); equal(own.Outgoing.Members[2].TeamId, teamB)
end)

test("decline, cancel and expiry keep players in the lobby and do not load combat characters", function()
    for _, outcome in ipairs({"Decline", "Cancel", "Expire"}) do
        local ctx = makeContext({outcome .. "A", outcome .. "B"}); local id = ctx:Invite("Duel")
        if outcome == "Decline" then assert(ctx.Match:HandleLobbyAction(ctx.Humans[2], "InviteRespond", {InviteId = id, Accept = false}))
        elseif outcome == "Cancel" then assert(ctx.Match:HandleLobbyAction(ctx.Humans[1], "InviteCancel", {InviteId = id}))
        else ctx:Advance(25) end
        equal(ctx.Match.Phase, "Lobby"); equal(ctx.Match.Roster, nil); equal(ctx:Lobby(ctx.Humans[2]).Incoming, nil)
        for _, human in ipairs(ctx.Humans) do equal(human.Loads, 1) end
        equal(#ctx.Profiles.Awards, 0)
    end
end)

test("an arena occupied by one group cancels other pending invites without moving them", function()
    local ctx = makeContext({"GroupA", "GroupB", "WaitingA", "WaitingB"})
    local waiting = {ctx.Humans[3], ctx.Humans[4]}; local waitingId = ctx:Invite("Duel", waiting)
    ctx:Prepare("Duel")
    equal(ctx:Lobby(waiting[1]).Outgoing, nil); equal(ctx:Lobby(waiting[2]).Incoming, nil)
    local accepted, reason = ctx.Match:HandleLobbyAction(waiting[2], "InviteRespond", {InviteId = waitingId, Accept = true})
    equal(accepted, false); equal(reason, "UnknownInvite")
    accepted, reason = ctx.Match:HandleLobbyAction(waiting[2], "Invite", {Mode = "Duel", OpponentUserId = waiting[1].UserId})
    equal(accepted, false); equal(reason, "ArenaBusy")
    for _, human in ipairs(waiting) do equal(human.Loads, 1); equal(human:GetAttribute("Activity"), "Lobby") end
end)

test("disconnecting a battle participant forfeits without awarding farming coins", function()
    local ctx = makeContext({"LeaveA", "LeaveB", "LeaveC", "LeaveD"}); ctx:Battle("Teams")
    ctx.Match:RemovePlayer(ctx.Humans[1]); ctx.Humans[1].Parent = nil
    equal(ctx.Match.Phase, "Results"); equal(ctx.Match.Winner, teamB); equal(#ctx.Profiles.Awards, 0)
    ctx:Advance(Config.Game.ResultSeconds); equal(ctx.Match.Phase, "Lobby"); equal(#ctx.Profiles.Awards, 0)
    for index = 2, 4 do equal(ctx.Humans[index]:GetAttribute("Activity"), "Lobby") end
end)

test("disconnecting during preparation aborts safely and awards nobody", function()
    local ctx = makeContext({"PrepareLeaveA", "PrepareLeaveB", "SafeVisitor"}); local visitor = ctx.Humans[3].Character
    ctx:Prepare("Duel"); completeLoad(ctx.Humans[1])
    ctx.Match:RemovePlayer(ctx.Humans[2]); ctx.Humans[2].Parent = nil
    equal(ctx.Match.Phase, "Lobby"); equal(ctx.Match.Roster, nil); equal(count(ctx.Combat.States), 0)
    equal(#ctx.Profiles.Awards, 0); equal(ctx.Humans[3].Character, visitor); assert(visitor.Parent)
end)

test("stale loads finishing during a new preparation cannot abort or populate it", function()
    local ctx = makeContext({"SlowA", "SlowB", "SlowC", "SlowD"}); ctx:Prepare("Teams")
    for index = 1, 3 do completeLoad(ctx.Humans[index]) end
    ctx:Advance(Config.Game.PreparingTimeoutSeconds)
    equal(ctx.Match.Phase, "Lobby"); equal(count(ctx.Combat.States), 0); equal(#ctx.Profiles.Awards, 0)
    ctx:Prepare("Teams")
    equal(ctx.Match.Round, 2)
    for _, human in ipairs(ctx.Humans) do
        local stale = completeLoad(human)
        equal(stale.Parent, nil); equal(stale.WaitCalls or 0, 0, "stale model must be refused before WaitForChild")
        equal(ctx.Combat:GetState(human), nil)
        assert(human.LoadThread, "new serialized load must follow the old one")
    end
    ctx:Advance(0.1); equal(ctx.Match.Phase, "Preparing")
    for _, human in ipairs(ctx.Humans) do completeLoad(human) end
    ctx:Advance(0.1); equal(ctx.Match.Phase, "Battle"); equal(count(ctx.Combat.States), 4)
    for _, human in ipairs(ctx.Humans) do equal(ctx.Combat:GetState(human).Model:GetAttribute("MatchRound"), 2) end
end)

test("same step double elimination produces a draw and one server reward request", function()
    local ctx = makeContext({"DrawA", "DrawB"}); ctx:Battle("Duel")
    for _, state in pairs(ctx.Combat.States) do state.Dead = true; state.Humanoid.Health = 0 end
    ctx:Advance(0.1)
    equal(ctx.Match.Phase, "Results"); equal(ctx.Match.Winner, nil); equal(ctx.Match.Scores[teamA], 0); equal(ctx.Match.Scores[teamB], 0)
    equal(#ctx.Profiles.Awards, 1); equal(ctx.Profiles.Awards[1].Winner, nil)
end)

test("a deferred final death counts kill and death exactly once through Results", function()
    local ctx = makeContext({"DeferredA", "DeferredB"}); ctx:Battle("Duel")
    local victim, killer = ctx.Humans[1], ctx.Humans[2]
    local victimState, killerState = ctx.Combat:GetState(victim), ctx.Combat:GetState(killer)
    victimState.Dead = true; victimState.Humanoid.Health = 0; ctx:Advance(0.1)
    equal(ctx.Match.Phase, "Results")
    local function stat(who, name) return who:FindFirstChild("leaderstats"):FindFirstChild(name).Value end
    equal(stat(victim, "Deaths"), 0)
    ctx.Combat.OnDeath(victimState, killerState); ctx.Combat.OnDeath(victimState, killerState)
    equal(stat(victim, "Deaths"), 1); equal(stat(killer, "Kills"), 1)
    equal(#ctx.Remotes.Effects.Calls, 1); equal(#ctx.Profiles.Awards, 1); equal(ctx.Match.Scores[teamB], 1)
end)

test("profile availability is rechecked before the last consent starts combat", function()
    local ctx = makeContext({"ReadyA", "ReadyB"}); local id = ctx:Invite("Duel")
    ctx.Humans[1]:SetAttribute("ProfileLoaded", false)
    local accepted, reason = ctx.Match:HandleLobbyAction(ctx.Humans[2], "InviteRespond", {InviteId = id, Accept = true})
    equal(accepted, false); equal(reason, "PlayerUnavailable"); equal(ctx.Match.Phase, "Lobby")
    equal(ctx.Humans[1].Loads, 1); equal(ctx.Humans[2].Loads, 1)
end)

test("malformed, duplicate and missing team ids cannot reserve a partial roster", function()
    local ctx = makeContext({"BadA", "BadB", "BadC", "BadD"}); local a, b, c, d = table.unpack(ctx.Humans)
    for _, payload in ipairs({
        {Mode = "Teams", OpponentUserId = c.UserId, OpponentAllyUserId = d.UserId},
        {Mode = "Teams", AllyUserId = b.UserId, OpponentUserId = c.UserId},
        {Mode = "Teams", AllyUserId = b.UserId, OpponentUserId = c.UserId, OpponentAllyUserId = b.UserId},
        {Mode = "Duel", OpponentUserId = a.UserId}, {Mode = "Farm", OpponentUserId = b.UserId},
        {Mode = "Duel", OpponentUserId = 999999},
    }) do equal(ctx.Match:HandleLobbyAction(a, "Invite", payload), false) end
    equal(ctx.Match.Phase, "Lobby"); equal(ctx.Match.Roster, nil)
    for _, human in ipairs(ctx.Humans) do equal(ctx:Lobby(human).Outgoing, nil); equal(ctx:Lobby(human).Incoming, nil) end
    ctx:Prepare("Teams"); equal(count(ctx.Match.Roster.Members), 4)
end)

test("a lobby death reloads only that visitor and never creates a combat state", function()
    local ctx = makeContext({"LobbyDead", "LobbyAlive"}); local other = ctx.Humans[2].Character
    ctx.Humans[1].Character:FindFirstChild("Humanoid").Health = 0
    ctx:Advance(0.1); ctx:Advance(Config.Game.LobbyRespawnSeconds)
    equal(ctx.Humans[1].Loads, 2); completeLoad(ctx.Humans[1])
    equal(ctx.Humans[1]:GetAttribute("Activity"), "Lobby"); equal(ctx.Humans[1]:GetAttribute("Spectating"), false)
    equal(ctx.Combat:GetState(ctx.Humans[1]), nil); equal(ctx.Humans[2].Character, other)
    equal(ctx.Humans[2].Loads, 1); equal(ctx.Match.Phase, "Lobby")
end)

print(tostring(passed) .. " real MatchService lifecycle tests passed; 0 failed")
