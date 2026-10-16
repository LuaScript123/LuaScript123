-- Run through: python3 tools/test-world.py
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
function Node:IsA(className) return self.ClassName == className or className == "Instance" or (className == "BasePart" and self.ClassName == "Part") end
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
function Node:PivotTo(position)
    self.Pivot = position
    local root = self:FindFirstChild("HumanoidRootPart")
    if root then root.Position = position.Position end
end
function Node:IsDescendantOf(parent)
    local cursor = self.Parent
    while cursor do if cursor == parent then return true end; cursor = cursor.Parent end
    return false
end
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
local vectorMeta = {}
vectorMeta.__index = function(v, key)
    if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
end
vectorMeta.__sub = function(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z}, vectorMeta) end
vectorMeta.__add = function(a,b) return setmetatable({X=a.X+b.X,Y=a.Y+b.Y,Z=a.Z+b.Z}, vectorMeta) end
local Vector3 = { new = function(x,y,z) return setmetatable({X=x,Y=y,Z=z}, vectorMeta) end }
Vector3.zero = Vector3.new(0,0,0)
local CFrame = { new = function(x,y,z) return {Position=type(x)=="table" and x or Vector3.new(x,y,z)} end }
local typeof = function(value) return getmetatable(value)==vectorMeta and "Vector3" or type(value) end
local RaycastParams = {new=function() return {} end}
local Enum = {RaycastFilterType={Exclude="Exclude"}}
function services.Workspace:Raycast(...) return self.Obstruction end
local Modules = {}
local require = function(module) return assert(Modules[module.Name], "Unknown module: " .. tostring(module.Name)) end
local shared = instance("Folder", "MedievalShared")
shared.Parent = services.ReplicatedStorage
for _, name in ipairs({ "Config", "WorldRules" }) do
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
	humanoid.Died = signal()
	humanoid.Parent = model
	local root = instance("Part", "HumanoidRootPart")
	root.Position = Vector3.zero
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
	local combat = { States = {}, Registrations = {}, Dressed = {}, Enabled = false, Efforts = 0 }
	function combat:DressCharacter(subject, model) self.Dressed[subject] = model end
	function combat:Register(subject, model, teamId)
		local state = { Subject = subject, Model = model, TeamId = teamId, Dead = false,
			Humanoid = model:FindFirstChild("Humanoid"), Root = model:FindFirstChild("HumanoidRootPart"),
            Stamina = 100, LastDamagedAt = -math.huge, LastAttackAt = -math.huge, LastWorkAt = -math.huge }
		self.States[subject] = state
		self.Registrations[subject] = (self.Registrations[subject] or 0) + 1
		return state
	end
	function combat:Unregister(subject) self.States[subject] = nil end
	function combat:GetState(subject) return self.States[subject] end
	function combat:GetStates() return self.States end
	function combat:SetEnabled(enabled) self.Enabled = enabled end
    function combat:SpendEffort(subject,cost)
        local state = self.States[subject]
        if self.RejectEffort then return false, self.RejectEffort end
        if state.Stamina < cost then return false, "Stamina" end
        state.Stamina -= cost
        state.LastWorkAt = clock
        self.Efforts += 1
        return true
    end
	return combat
end
local function remoteDouble()
	local remote = { Calls = {} }
	function remote:FireAllClients(...) table.insert(self.Calls, table.pack(...)) end
	function remote:FireClient(subject, ...) local call = table.pack(...); call.Subject = subject; table.insert(self.Calls, call) end
	return remote
end

-- INSERT_REAL_MODULES_HERE
local Config, Rules, WorldService = Modules.Config, Modules.WorldRules, Modules.WorldService
local passed = 0
local kingdomA, kingdomB = Config.KingdomOrder[1], Config.KingdomOrder[2]
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function test(name, callback)
    services.Workspace.Obstruction = nil
    callback()
    passed += 1
    print("PASS " .. name)
end
local function makeContext(names)
    local combat = combatDouble()
    local remotes = {World=remoteDouble(),Effects=remoteDouble()}
    local map = {Spawns={},LobbySpawns={CFrame.new(0,3.5,200)},LobbyCenter=Vector3.new(0,0,200),Nodes={
        Tree01={Kind="Tree",Position=Vector3.new(0,2,0)},
        Mine01={Kind="Mine",Position=Vector3.new(8,2,0)},
    },Outposts={Westwatch={Name="Westwatch",Position=Vector3.zero}}}
    for index, id in ipairs(Config.KingdomOrder) do map.Spawns[id]={CFrame.new(index*100,3.5,0)} end
    local world=WorldService.new(remotes,map,combat,{}, {Visuals=false})
    local subjects={}
    for _,name in ipairs(names or {"Alice"}) do
        local subject=player(name)
        world:AddPlayer(subject)
        table.insert(subjects,subject)
    end
    world:Start()
    return {World=world,Combat=combat,Remotes=remotes,Map=map,Players=subjects}
end
local function selectKingdom(context, subject, id)
    completeLoad(subject)
    local ok,reason=context.World:HandleAction(subject,"ChooseKingdom",{KingdomId=id or kingdomA})
    assert(ok,tostring(reason))
    return completeLoad(subject),context.Combat:GetState(subject)
end
local function latest(context)
    return context.Remotes.World.Calls[#context.Remotes.World.Calls][1]
end
local function advance(context,seconds)
    clock += seconds
    context.World:Step(seconds)
    pump()
end
local function at(state,position) state.Root.Position=position end

 test("neutral selection spawn is shielded, dressed and unregistered",function()
    local c=makeContext()
    local p=c.Players[1]
    local model=completeLoad(p)
    equal(p:GetAttribute("Activity"),"Lobby")
    equal(c.Combat:GetState(p),nil)
    equal(model:GetAttribute("Combatant"),false)
    assert(model:FindFirstChild("SelectionProtection"))
    equal(c.Combat.Dressed[p],model)
    equal(c.Combat.Enabled,true)
    equal(latest(c).Inventory.Wood,0)
end)

 test("kingdom choice loads exactly one registered world character",function()
    local c=makeContext()
    local p=c.Players[1]
    local model,state=selectKingdom(c,p)
    equal(p:GetAttribute("Activity"),"World")
    equal(p:GetAttribute("KingdomId"),kingdomA)
    equal(p:GetAttribute("TeamId"),kingdomA)
    equal(state.Model,model)
    equal(c.Combat.Registrations[p],1)
    equal(model:FindFirstChild("SelectionProtection"),nil)
    equal(model.Pivot,c.Map.Spawns[kingdomA][1])
end)

 test("kingdom choice invalidates a pending neutral load without concurrent loads",function()
    local c=makeContext()
    local p=c.Players[1]
    assert(c.World:HandleAction(p,"ChooseKingdom",{KingdomId=kingdomA}))
    equal(p.Loads,1)
    local stale=completeLoad(p)
    equal(stale.Parent,nil)
    equal(stale.WaitCalls,nil,"stale request must be rejected before waiting for children")
    equal(p.Loads,2)
    equal(c.Combat:GetState(p),nil)
    local fresh=completeLoad(p)
    equal(c.Combat:GetState(p).Model,fresh)
    equal(c.Combat.Registrations[p],1)
end)

 test("leaving during a load never registers the late character",function()
    local c=makeContext()
    local p=c.Players[1]
    assert(c.World:HandleAction(p,"ChooseKingdom",{KingdomId=kingdomA}))
    completeLoad(p)
    c.World:RemovePlayer(p)
    p.Parent=nil
    local stale=completeLoad(p)
    equal(stale.Parent,nil)
    equal(c.Combat:GetState(p),nil)
    equal(c.Combat.Registrations[p],nil)
    equal(p.Loads,2)
end)

 test("kingdom changes respect combat lock, cooldown and pending swings",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    state.LastDamagedAt=clock
    local ok,reason=c.World:HandleAction(p,"ChooseKingdom",{KingdomId=kingdomB})
    equal(ok,false);equal(reason,"CombatLocked")
    advance(c,Config.World.KingdomChangeSafeSeconds+1)
    ok,reason=c.World:HandleAction(p,"ChooseKingdom",{KingdomId=kingdomB})
    equal(ok,false);equal(reason,"KingdomCooldown")
    advance(c,Config.World.KingdomChangeCooldown+1)
    state.PendingAttack={}
    ok,reason=c.World:HandleAction(p,"ChooseKingdom",{KingdomId=kingdomB})
    equal(ok,false);equal(reason,"CombatLocked")
    state.PendingAttack=nil
    assert(c.World:HandleAction(p,"ChooseKingdom",{KingdomId=kingdomB}))
    equal(c.Combat:GetState(p),nil)
    equal(p:GetAttribute("KingdomId"),kingdomB)
    completeLoad(p)
    equal(c.Combat:GetState(p).TeamId,kingdomB)
end)

 test("harvest spends stamina and rewards only the final server-approved hit",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    at(state,Vector3.new(0,3.5,0))
    for strike=1,Config.World.Tree.Hits do
        if strike>1 then advance(c,Config.World.HarvestCooldown) end
        assert(c.World:HandleAction(p,"Harvest",{NodeId="Tree01",Amount=999999}))
        equal(c.World._players[p].State.Wood,strike==Config.World.Tree.Hits and Config.World.Tree.Yield or 0)
    end
    equal(c.Combat.Efforts,Config.World.Tree.Hits)
    equal(state.Stamina,100-Config.World.Tree.Hits*Config.World.HarvestStaminaCost)
    equal(c.World._nodes.Tree01.State.HitsRemaining,0)
    equal(latest(c).Inventory.Wood,Config.World.Tree.Yield)
    equal(latest(c).Nodes[2].RespawnAt,100000+c.World._nodes.Tree01.State.RespawnAt)
end)

 test("harvest cooldown rejects before spending effort",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    at(state,Vector3.new(0,3.5,0))
    assert(c.World:HandleAction(p,"Harvest",{NodeId="Tree01"}))
    local ok,reason=c.World:HandleAction(p,"Harvest",{NodeId="Mine01"})
    equal(ok,false);equal(reason,"HarvestCooldown")
    equal(c.Combat.Efforts,1)
    equal(c.World._nodes.Mine01.State.HitsRemaining,Config.World.Mine.Hits)
end)

 test("range and line of sight prevent harvesting without spending",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    local ok,reason=c.World:HandleAction(p,"Harvest",{NodeId="Tree01"})
    equal(ok,false);equal(reason,"TooFar")
    at(state,Vector3.new(0,3.5,0))
    services.Workspace.Obstruction={Instance=instance("Part","Wall")}
    ok,reason=c.World:HandleAction(p,"Harvest",{NodeId="Tree01"})
    equal(ok,false);equal(reason,"Obstructed")
    equal(c.Combat.Efforts,0)
    equal(c.World._nodes.Tree01.State.HitsRemaining,Config.World.Tree.Hits)
end)

 test("stamina rejection leaves node and cooldown unchanged",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    at(state,Vector3.new(0,3.5,0))
    state.Stamina=0
    local ok,reason=c.World:HandleAction(p,"Harvest",{NodeId="Tree01"})
    equal(ok,false);equal(reason,"Stamina")
    equal(c.World._nodes.Tree01.State.HitsRemaining,Config.World.Tree.Hits)
    equal(c.World._players[p].State.LastHarvestAt,-math.huge)
end)

 test("depleted nodes respawn on world time without extra yield",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    at(state,Vector3.new(0,3.5,0))
    for strike=1,Config.World.Tree.Hits do
        if strike>1 then advance(c,Config.World.HarvestCooldown) end
        assert(c.World:HandleAction(p,"Harvest",{NodeId="Tree01"}))
    end
    advance(c,Config.World.HarvestCooldown)
    local ok,reason=c.World:HandleAction(p,"Harvest",{NodeId="Tree01"})
    equal(ok,false);equal(reason,"Depleted")
    advance(c,Config.World.Tree.RespawnSeconds)
    equal(c.World._nodes.Tree01.State.HitsRemaining,Config.World.Tree.Hits)
    equal(c.World._players[p].State.Wood,Config.World.Tree.Yield)
    equal(c.Combat.Efforts,Config.World.Tree.Hits)
end)

 test("capture uses only living world player server positions",function()
    local c=makeContext({"Attacker","Neutral"})
    local attacker=c.Players[1]
    local _,state=selectKingdom(c,attacker)
    completeLoad(c.Players[2])
    at(state,Vector3.new(0,3.5,0))
    advance(c,Config.World.CaptureSeconds/2)
    equal(c.World._outposts.Westwatch.State.Progress,0.5)
    state.Dead=true
    advance(c,Config.World.CaptureSeconds/2)
    equal(c.World._outposts.Westwatch.State.Owner,nil)
    equal(c.World._outposts.Westwatch.State.Progress,0)
    advance(c,Config.World.RespawnSeconds)
    completeLoad(attacker)
    state=c.Combat:GetState(attacker)
    at(state,Vector3.new(0,3.5,0))
    advance(c,Config.World.CaptureSeconds)
    equal(c.World._outposts.Westwatch.State.Owner,kingdomA)
end)

 test("enemy presence contests capture and forged client counts are ignored",function()
    local c=makeContext({"Alice","Bob"})
    local _,a=selectKingdom(c,c.Players[1],kingdomA)
    local _,b=selectKingdom(c,c.Players[2],kingdomB)
    at(a,Vector3.new(0,3.5,0));at(b,Vector3.new(0,3.5,0))
    advance(c,Config.World.CaptureSeconds)
    local point=c.World._outposts.Westwatch.State
    equal(point.Owner,nil);equal(point.Contested,true);equal(point.Progress,0)
    local ok,reason=c.World:HandleAction(c.Players[1],"Capture",{OutpostId="Westwatch",KingdomCounts={[kingdomA]=999}})
    equal(ok,false);equal(reason,"UnknownAction")
    at(b,Vector3.new(100,3.5,100))
    advance(c,Config.World.CaptureSeconds)
    equal(point.Owner,kingdomA);equal(point.Contested,false)
end)

 test("build validates ownership, proximity, sightline and atomic resources",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    local record=c.World._players[p]
    local point=c.World._outposts.Westwatch.State
    point.Owner=kingdomA
    record.State.Wood,record.State.Ore=Config.World.OutpostWoodCost,Config.World.OutpostOreCost
    local ok,reason=c.World:HandleAction(p,"BuildOutpost",{OutpostId="Westwatch"})
    equal(ok,false);equal(reason,"TooFar")
    at(state,Vector3.new(0,3.5,0))
    services.Workspace.Obstruction={Instance=instance("Part","Wall")}
    ok,reason=c.World:HandleAction(p,"BuildOutpost",{OutpostId="Westwatch"})
    equal(ok,false);equal(reason,"Obstructed")
    services.Workspace.Obstruction=nil
    point.Owner=kingdomB
    ok,reason=c.World:HandleAction(p,"BuildOutpost",{OutpostId="Westwatch"})
    equal(ok,false);equal(reason,"NotOwner")
    equal(record.State.Wood,Config.World.OutpostWoodCost)
    point.Owner=kingdomA
    assert(c.World:HandleAction(p,"BuildOutpost",{OutpostId="Westwatch",Cost=0}))
    equal(point.Built,true);equal(record.State.Wood,0);equal(record.State.Ore,0)
    ok,reason=c.World:HandleAction(p,"BuildOutpost",{OutpostId="Westwatch"})
    equal(ok,false);equal(reason,"AlreadyBuilt")
end)

 test("death credits once and respawns after the server deadline",function()
    local c=makeContext({"Alice","Bob"})
    local p,k=c.Players[1],c.Players[2]
    local _,victim=selectKingdom(c,p,kingdomA)
    local _,killer=selectKingdom(c,k,kingdomB)
    victim.Dead=true;victim.Humanoid.Health=0
    c.Combat.OnDeath(victim,killer)
    c.Combat.OnDeath(victim,killer)
    equal(p:FindFirstChild("leaderstats"):FindFirstChild("Deaths").Value,1)
    equal(k:FindFirstChild("leaderstats"):FindFirstChild("Kills").Value,1)
    equal(c.Combat:GetState(p),nil)
    local deadline=c.World._players[p].RespawnAt
    c.World:SendState(p)
    equal(latest(c).RespawnAt,100000+deadline)
    local loads=p.Loads
    advance(c,Config.World.RespawnSeconds-0.1)
    equal(p.Loads,loads)
    advance(c,0.2)
    equal(p.Loads,loads+1)
    local fresh=completeLoad(p)
    equal(c.Combat:GetState(p).Model,fresh)
    equal(p:GetAttribute("KingdomId"),kingdomA)
    c.Combat.OnDeath(victim,killer)
    equal(p:FindFirstChild("leaderstats"):FindFirstChild("Deaths").Value,1)
end)

 test("owned built outpost spawn is revalidated after asynchronous character load",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    local point=c.World._outposts.Westwatch.State
    point.Owner,point.Built=kingdomA,true
    assert(c.World:HandleAction(p,"SetOutpostSpawn",{OutpostId="Westwatch"}))
    local selected=c.World:GetSpawn(p)
    equal(selected.Position.Z,10)
    state.Dead=true;state.Humanoid.Health=0
    c.Combat.OnDeath(state)
    advance(c,Config.World.RespawnSeconds)
    point.Owner,point.Built=kingdomB,false
    local model=completeLoad(p)
    equal(model.Pivot,c.Map.Spawns[kingdomA][1])
    equal(c.World._players[p].SpawnOutpostId,nil)
end)

 test("respawn selection rejects unknown, enemy and unbuilt flags and resets base",function()
    local c=makeContext()
    local p=c.Players[1]
    selectKingdom(c,p)
    local point=c.World._outposts.Westwatch.State
    local ok,reason=c.World:HandleAction(p,"SetOutpostSpawn",{OutpostId="Unknown"})
    equal(ok,false);equal(reason,"UnknownOutpost")
    point.Owner=kingdomB
    ok,reason=c.World:HandleAction(p,"SetOutpostSpawn",{OutpostId="Westwatch"})
    equal(ok,false);equal(reason,"NotOwner")
    point.Owner=kingdomA
    ok,reason=c.World:HandleAction(p,"SetOutpostSpawn",{OutpostId="Westwatch"})
    equal(ok,false);equal(reason,"NotBuilt")
    point.Built=true
    assert(c.World:HandleAction(p,"SetOutpostSpawn",{OutpostId="Westwatch"}))
    equal(c.World._players[p].SpawnOutpostId,"Westwatch")
    assert(c.World:HandleAction(p,"SetOutpostSpawn",{OutpostId=""}))
    equal(c.World._players[p].SpawnOutpostId,nil)
end)

 test("invalidated registrations cannot harvest, capture or switch kingdoms",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    at(state,Vector3.new(0,3.5,0))
    p.Character=character("Replacement")
    local ok,reason=c.World:HandleAction(p,"Harvest",{NodeId="Tree01"})
    equal(ok,false);equal(reason,"Dead")
    ok,reason=c.World:HandleAction(p,"ChooseKingdom",{KingdomId=kingdomB})
    equal(ok,false);equal(reason,"Dead")
    advance(c,Config.World.CaptureSeconds)
    equal(c.World._outposts.Westwatch.State.Owner,nil)
    equal(c.Combat:GetState(p),nil)
    equal(c.Combat.Efforts,0)
end)

 test("missing children cause a bounded retry and never a partial registration",function()
    local c=makeContext()
    local p=c.Players[1]
    assert(c.World:HandleAction(p,"ChooseKingdom",{KingdomId=kingdomA}))
    completeLoad(p) -- abort selection load, begin world load
    local thread=p.LoadThread
    p.LoadThread=nil
    local broken=instance("Model","Broken")
    broken.Parent=instance("Workspace")
    p.Character=broken
    p.CharacterAdded:Fire(broken)
    resumeThread(thread)
    pump()
    equal(c.Combat:GetState(p),nil)
    equal(broken.Parent,nil)
    equal(c.World._players[p].RespawnAt,clock+Config.World.RespawnSeconds)
    local loads=p.Loads
    advance(c,Config.World.RespawnSeconds)
    equal(p.Loads,loads+1)
    completeLoad(p)
    equal(c.Combat.Registrations[p],1)
end)

 test("external character replacement discards privileges and schedules safe reload",function()
    local c=makeContext()
    local p=c.Players[1]
    selectKingdom(c,p)
    local replacement=character("Unauthorized")
    p.Character=replacement
    p.CharacterAdded:Fire(replacement)
    equal(replacement.Parent,nil)
    equal(c.Combat:GetState(p),nil)
    assert(c.World._players[p].RespawnAt)
    advance(c,Config.World.RespawnSeconds)
    local fresh=completeLoad(p)
    equal(c.Combat:GetState(p).Model,fresh)
    equal(c.Combat.Registrations[p],2)
end)

 test("node and player inventories are session-local and reset on rejoin",function()
    local c=makeContext()
    local p=c.Players[1]
    selectKingdom(c,p)
    c.World._players[p].State.Wood=99
    c.World:RemovePlayer(p)
    c.World:AddPlayer(p)
    equal(c.World._players[p].State.Wood,0)
    equal(c.World._players[p].State.KingdomId,nil)
    completeLoad(p)
    equal(p:GetAttribute("Activity"),"Lobby")
    equal(c.Combat:GetState(p),nil)
end)

 test("malformed identifiers and nonfinite positions cannot spend resources",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    local ok,reason=c.World:HandleAction(p,"Harvest",{NodeId={}})
    equal(ok,false);equal(reason,"Malformed")
    at(state,Vector3.new(0/0,0,0))
    ok,reason=c.World:HandleAction(p,"Harvest",{NodeId="Tree01"})
    equal(ok,false);equal(reason,"Dead")
    equal(c.Combat.Efforts,0)
    equal(c.World._players[p].State.Wood,0)
end)

 test("world snapshots contain per-player resources and absolute deadlines",function()
    local c=makeContext({"Alice","Bob"})
    local a,b=c.Players[1],c.Players[2]
    selectKingdom(c,a)
    completeLoad(b)
    c.World._players[a].State.Wood=31
    c.World:SendState(a)
    local snapshot=latest(c)
    equal(snapshot.KingdomId,kingdomA)
    equal(snapshot.Inventory.Wood,31)
    equal(snapshot.KingdomChangeReadyAt,100000+c.World._players[a].State.LastKingdomAt+Config.World.KingdomChangeCooldown)
    equal(snapshot.Kingdoms[1].Players,1)
    equal(#snapshot.Outposts,1)
    equal(#snapshot.Nodes,2)
    c.World:SendState(b)
    equal(latest(c).KingdomId,nil)
    equal(latest(c).Inventory.Wood,0)
    equal(latest(c).KingdomChangeReadyAt,0)
end)

test("detached root parts cannot retain interaction or capture privileges",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    at(state,Vector3.new(0,3.5,0))
    state.Root.Parent=instance("Model","OtherCharacter")
    local ok,reason=c.World:HandleAction(p,"Harvest",{NodeId="Tree01"})
    equal(ok,false);equal(reason,"Dead")
    advance(c,Config.World.CaptureSeconds)
    equal(c.World._outposts.Westwatch.State.Owner,nil)
    equal(c.Combat.Efforts,0)
end)

test("heartbeat recovers a missing humanoid without inventing kill statistics",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    state.Humanoid:Destroy()
    advance(c,0.1)
    equal(c.Combat:GetState(p),nil)
    equal(p:FindFirstChild("leaderstats"):FindFirstChild("Deaths").Value,0)
    advance(c,Config.World.RespawnSeconds)
    local fresh=completeLoad(p)
    equal(c.Combat:GetState(p).Model,fresh)
end)

test("heartbeat accounts for death before the deferred combat callback exactly once",function()
    local c=makeContext({"Alice","Bob"})
    local p,k=c.Players[1],c.Players[2]
    local _,victim=selectKingdom(c,p,kingdomA)
    local _,killer=selectKingdom(c,k,kingdomB)
    victim.LastAttacker,victim.LastHitAt=killer,clock
    victim.Humanoid.Health=0
    victim.Dead=true
    advance(c,0.1)
    equal(c.Combat:GetState(p),nil)
    equal(p:FindFirstChild("leaderstats"):FindFirstChild("Deaths").Value,1)
    equal(k:FindFirstChild("leaderstats"):FindFirstChild("Kills").Value,1)
    c.Combat.OnDeath(victim,killer)
    equal(p:FindFirstChild("leaderstats"):FindFirstChild("Deaths").Value,1)
    equal(k:FindFirstChild("leaderstats"):FindFirstChild("Kills").Value,1)
end)

test("capture snapshots are bounded instead of sending every heartbeat",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    at(state,Vector3.new(0,3.5,0))
    local calls=#c.Remotes.World.Calls
    for _=1,12 do advance(c,0.016) end
    equal(#c.Remotes.World.Calls,calls)
    advance(c,0.016)
    equal(#c.Remotes.World.Calls,calls+1)
    for _=1,12 do advance(c,0.016) end
    equal(#c.Remotes.World.Calls,calls+1)
end)

test("contested flags cannot spend fortification resources",function()
    local c=makeContext()
    local p=c.Players[1]
    local _,state=selectKingdom(c,p)
    at(state,Vector3.new(0,3.5,0))
    local record=c.World._players[p]
    record.State.Wood,record.State.Ore=Config.World.OutpostWoodCost,Config.World.OutpostOreCost
    local point=c.World._outposts.Westwatch.State
    point.Owner,point.Contested=kingdomA,true
    local ok,reason=c.World:HandleAction(p,"BuildOutpost",{OutpostId="Westwatch"})
    equal(ok,false);equal(reason,"Contested")
    equal(point.Built,false)
    equal(record.State.Wood,Config.World.OutpostWoodCost)
    equal(record.State.Ore,Config.World.OutpostOreCost)
end)

print(string.format("%d world service lifecycle tests passed (explicit doubles; no engine simulation).",passed))
