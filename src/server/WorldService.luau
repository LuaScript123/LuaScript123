-- Session-only kingdom warfare. Clients request actions; this service owns all
-- world resources, ownership, placement, character lifetime and proximity checks.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("MedievalShared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("WorldRules"))

local WorldService = {}
WorldService.__index = WorldService

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function finitePosition(position)
    return typeof(position) == "Vector3" and finite(position.X) and finite(position.Y) and finite(position.Z)
end
local function identifier(value)
    return type(value) == "string" and #value > 0 and #value <= 48
end
local function statistic(player, name)
    local folder = player:FindFirstChild("leaderstats")
    return folder and folder:FindFirstChild(name)
end
local function orderedKeys(values)
    local keys = {}
    for id in pairs(values) do table.insert(keys, id) end
    table.sort(keys)
    return keys
end
local function anchor(model)
    return model and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
end
local function label(model, name, height)
    local part = anchor(model)
    if not part then return nil end
    local gui = Instance.new("BillboardGui")
    gui.Name, gui.Adornee = name, part
    gui.Size, gui.StudsOffset = UDim2.fromOffset(230, 66), Vector3.new(0, height or 5, 0)
    gui.AlwaysOnTop, gui.MaxDistance = false, 100
    local text = Instance.new("TextLabel")
    text.Size, text.BackgroundTransparency = UDim2.fromScale(1, 1), 1
    text.Font, text.TextSize = Enum.Font.GothamBold, 15
    text.TextColor3, text.TextStrokeTransparency = Color3.fromRGB(245, 232, 196), 0.3
    text.TextWrapped, text.Parent = true, gui
    gui.Parent = model
    return text
end

-- Optional clock/scheduler/visual overrides allow deterministic lifecycle tests;
-- production uses the real Roblox character, physics and network APIs.
function WorldService.new(remotes, map, combat, profiles, dependencies)
    local deps = dependencies or {}
    local self = setmetatable({}, WorldService)
    self.Remotes, self.Map, self.Combat, self.Profiles = remotes, map, combat, profiles
    self._clock, self._serverTime = deps.Clock or os.clock, deps.ServerTime or function() return Workspace:GetServerTimeNow() end
    self._spawn = deps.Spawn or task.spawn
    self._visuals = deps.Visuals ~= false
    self._players, self._teams, self._spawnIndices = {}, {}, {}
    self._nodes, self._outposts = {}, {}
    self._deaths = setmetatable({}, { __mode = "k" })
    self._started, self._snapshotElapsed, self._lobbySpawn = false, 0, 0
    for _, id in ipairs(Config.KingdomOrder) do
        local definition = Config.Kingdoms[id]
        local team = Teams:FindFirstChild(definition.Name)
        if not team or not team:IsA("Team") then
            team = Instance.new("Team")
            team.Name, team.Parent = definition.Name, Teams
        end
        team.AutoAssignable = false
        team.TeamColor = BrickColor.new(Color3.fromRGB(table.unpack(definition.Color)))
        self._teams[id] = team
    end
    for id, view in pairs(map.Nodes or {}) do
        local entry = { View = view, State = Rules.NewNode(view.Kind, Config), Parts = {} }
        self._nodes[id] = entry
        if self._visuals and view.Model then
            for _, part in ipairs(view.Model:GetDescendants()) do
                if part:IsA("BasePart") then
                    table.insert(entry.Parts, { Part = part, Transparency = part.Transparency, CanCollide = part.CanCollide, CanQuery = part.CanQuery })
                end
            end
            entry.Label = label(view.Model, "ResourceStatus", 5)
        end
        self:_renderNode(entry)
    end
    for id, view in pairs(map.Outposts or {}) do
        local entry = { View = view, State = Rules.NewOutpost() }
        self._outposts[id] = entry
        if self._visuals then entry.Label = label(view.Model, "OutpostStatus", 10) end
        self:_renderOutpost(entry)
    end
    combat.OnDeath = function(victim, killer) self:_onDeath(victim, killer) end
    return self
end

function WorldService:_renderNode(entry)
    if not self._visuals then return end
    local alive = entry.State.HitsRemaining > 0
    for _, original in ipairs(entry.Parts) do
        original.Part.Transparency = alive and original.Transparency or 1
        original.Part.CanCollide = alive and original.CanCollide or false
        original.Part.CanQuery = alive and original.CanQuery or false
    end
    if entry.Label then
        entry.Label.Text = alive and string.format("%s · %d hits\n[E] Gather", entry.State.Kind, entry.State.HitsRemaining) or "Regrowing…"
    end
end

function WorldService:_renderOutpost(entry)
    if not self._visuals then return end
    local point, view = entry.State, entry.View
    local definition = point.Owner and Config.Kingdoms[point.Owner]
    if view.Flag then view.Flag.Color = Color3.fromRGB(table.unpack(definition and definition.Color or { 178, 169, 141 })) end
    for _, part in ipairs(view.Structure or {}) do
        part.Transparency, part.CanCollide, part.CanQuery = point.Built and 0 or 1, point.Built, point.Built
    end
    if entry.Label then
        local status = point.Contested and "CONTESTED" or (point.Claimant and string.format("%s %d%%", Config.Kingdoms[point.Claimant].Name, math.floor(point.Progress * 100))
            or (point.Built and "Fortified · respawn available" or "Hold the flag · build with wood & ore"))
        entry.Label.Text = view.Name .. " · " .. (definition and definition.Name or "Neutral") .. "\n" .. status
    end
end

function WorldService:_setKingdom(player, kingdomId)
    player.Team, player.Neutral = kingdomId and self._teams[kingdomId] or nil, kingdomId == nil
    player:SetAttribute("KingdomId", kingdomId)
    player:SetAttribute("TeamId", kingdomId)
    player:SetAttribute("Activity", kingdomId and "World" or "Lobby")
    player:SetAttribute("Spectating", false)
    player:SetAttribute("Eliminated", false)
end

function WorldService:_currentRequest(player, record, request)
    return request ~= nil and self._players[player] == record and player.Parent == Players
        and request.Generation == record.Generation and request.KingdomId == record.State.KingdomId
end

function WorldService:GetSpawn(player)
    local record = self._players[player]
    local kingdomId = record and record.State.KingdomId
    if kingdomId then
        local entry = record.SpawnOutpostId and self._outposts[record.SpawnOutpostId]
        if entry and entry.State.Owner == kingdomId and entry.State.Built then
            return entry.View.Spawn or CFrame.new(entry.View.Position + Vector3.new(0, 3.5, 10))
        end
        -- Lost/unbuilt points never permit an enemy spawn, even if selection
        -- happened before ownership changed during an asynchronous load.
        record.SpawnOutpostId = nil
        local spawns = self.Map.Spawns[kingdomId]
        if spawns and #spawns > 0 then
            self._spawnIndices[kingdomId] = (self._spawnIndices[kingdomId] or 0) % #spawns + 1
            return spawns[self._spawnIndices[kingdomId]]
        end
    else
        local spawns = self.Map.LobbySpawns
        if spawns and #spawns > 0 then
            self._lobbySpawn = self._lobbySpawn % #spawns + 1
            return spawns[self._lobbySpawn]
        end
    end
    return CFrame.new(self.Map.LobbyCenter or Vector3.new(0, 3.5, 420))
end

function WorldService:_clearCharacter(player, record, destroy)
    record.Model = nil
    if record.LobbyDeathConnection then record.LobbyDeathConnection:Disconnect(); record.LobbyDeathConnection = nil end
    self.Combat:Unregister(player)
    if destroy and player.Character then player.Character:Destroy() end
end

function WorldService:_scheduleRespawn(player, record)
    record.Generation += 1
    record.Request = nil
    self:_clearCharacter(player, record, false)
    record.RespawnAt = self._clock() + Config.World.RespawnSeconds
end

function WorldService:_load(player)
    local record = self._players[player]
    if not record or player.Parent ~= Players then return false, "UnknownPlayer" end
    if record.Request or self:_currentRequest(player, record, record.ActiveRequest) then return false, "AlreadyLoading" end
    record.Generation += 1
    record.Request = { Generation = record.Generation, KingdomId = record.State.KingdomId }
    record.RespawnAt = nil
    if record.LoadRunning then return true end
    record.LoadRunning = true
    self._spawn(function()
        while self._players[player] == record and player.Parent == Players and record.Request do
            local request = record.Request
            record.Request, record.ActiveRequest = nil, request
            local model
            local ok, problem = pcall(function()
                player:LoadCharacterAsync()
                model = player.Character
                if not self:_currentRequest(player, record, request) then return end
                if not model then error("Character is missing") end
                local humanoid = model:WaitForChild("Humanoid", 10)
                local root = model:WaitForChild("HumanoidRootPart", 10)
                if not self:_currentRequest(player, record, request) then return end
                if model ~= player.Character or not model.Parent or not humanoid or not root or humanoid.Health <= 0 then
                    error("Character is incomplete or died while loading")
                end
                for _, child in ipairs(model:GetChildren()) do if child:IsA("ForceField") then child:Destroy() end end
                model:SetAttribute("Eliminated", false)
                model:SetAttribute("KingdomId", request.KingdomId)
                model:PivotTo(self:GetSpawn(player))
                if request.KingdomId then
                    if not self.Combat:Register(player, model, request.KingdomId) then error("Combat registration failed") end
                else
                    model:SetAttribute("Combatant", false)
                    humanoid.MaxHealth, humanoid.Health, humanoid.WalkSpeed = Config.Player.MaxHealth, Config.Player.MaxHealth, Config.Player.WalkSpeed
                    local shield = Instance.new("ForceField")
                    shield.Name, shield.Visible, shield.Parent = "SelectionProtection", false, model
                    if self.Combat.DressCharacter then self.Combat:DressCharacter(player, model) end
                    record.LobbyDeathConnection = humanoid.Died:Connect(function()
                        if self._players[player] == record and record.Model == model then
                            self:_scheduleRespawn(player, record)
                            self:SendState(player)
                        end
                    end)
                end
                record.Model = model
            end)
            local current = self:_currentRequest(player, record, request)
            if not ok and current then
                warn("World character load for " .. player.Name .. ": " .. tostring(problem))
                self:_scheduleRespawn(player, record)
                if model and model.Parent then model:Destroy() end
            elseif not current and model and model.Parent and record.Model ~= model then
                model:Destroy()
            end
            record.ActiveRequest = nil
        end
        record.LoadRunning = false
        if self._players[player] == record then self:SendState(player) end
    end)
    return true
end

function WorldService:AddPlayer(player)
    if self._players[player] or player.Parent ~= Players then return end
    local record = { State = Rules.NewPlayer(), Generation = 0, LoadRunning = false }
    self._players[player] = record
    self:_setKingdom(player, nil)
    local stats = player:FindFirstChild("leaderstats")
    if not stats then stats = Instance.new("Folder"); stats.Name, stats.Parent = "leaderstats", player end
    for _, name in ipairs({ "Kills", "Deaths" }) do
        if not stats:FindFirstChild(name) then
            local value = Instance.new("IntValue")
            value.Name, value.Parent = name, stats
        end
    end
    record.AddedConnection = player.CharacterAdded:Connect(function(model)
        if self._players[player] ~= record then return end
        if self:_currentRequest(player, record, record.ActiveRequest) then return end
        if record.ActiveRequest then model:Destroy(); return end
        -- CharacterAutoLoads is disabled. A replaced character cannot inherit a
        -- previous registration, inventory privileges or delayed death callback.
        if record.Model then self:_scheduleRespawn(player, record) end
        model:Destroy()
        record.RespawnAt = record.RespawnAt or self._clock() + Config.World.RespawnSeconds
    end)
    record.RemovingConnection = player.CharacterRemoving:Connect(function(model)
        if self._players[player] == record and record.Model == model then
            self:_scheduleRespawn(player, record)
        end
    end)
    self:_clearCharacter(player, record, true)
    self:_load(player)
    self:SendState()
end

function WorldService:RemovePlayer(player)
    local record = self._players[player]
    if not record then return end
    record.Generation += 1
    record.Request = nil
    record.AddedConnection:Disconnect()
    record.RemovingConnection:Disconnect()
    self:_clearCharacter(player, record, false)
    self._players[player] = nil
    self:SendState()
end

function WorldService:_alive(player)
    local record = self._players[player]
    local state = self.Combat:GetState(player)
    if not record or not record.State.KingdomId or player:GetAttribute("Activity") ~= "World" then return nil, "ChooseKingdom" end
    if not state or state.Dead or record.Model ~= state.Model or player.Character ~= state.Model or not state.Model.Parent
        or state.Humanoid.Health <= 0 or state.Humanoid.Parent ~= state.Model or state.Root.Parent ~= state.Model or not finitePosition(state.Root.Position)
        or state.TeamId ~= record.State.KingdomId then return nil, "Dead" end
    return state
end

function WorldService:_inReach(state, view, distance)
    if not finitePosition(view.Position) or (state.Root.Position - view.Position).Magnitude > distance then return false, "TooFar" end
    local target = view.Position + (view.Kind and Vector3.zero or Vector3.new(0, 2, 0))
    local parameters = RaycastParams.new()
    parameters.FilterType = Enum.RaycastFilterType.Exclude
    parameters.FilterDescendantsInstances = { state.Model }
    parameters.RespectCanCollide = false
    local result = Workspace:Raycast(state.Root.Position, target - state.Root.Position, parameters)
    if result and (not view.Model or not result.Instance:IsDescendantOf(view.Model)) then return false, "Obstructed" end
    return true
end

function WorldService:HandleAction(player, action, payload)
    local record = self._players[player]
    if not record then return false, "UnknownPlayer" end
    if type(payload) ~= "table" then return false, "Malformed" end
    local now = self._clock()
    if action == "ChooseKingdom" then
        if not identifier(payload.KingdomId) then return false, "Malformed" end
        if record.State.KingdomId then
            local state, reason = self:_alive(player)
            if not state then return false, reason end
            local lastCombat = math.max(state.LastDamagedAt or -math.huge, state.LastAttackAt or -math.huge, state.LastWorkAt or -math.huge)
            if state.PendingAttack or now - lastCombat < Config.World.KingdomChangeSafeSeconds then return false, "CombatLocked" end
        end
        local accepted, reason = Rules.ChooseKingdom(record.State, payload.KingdomId, Config, now)
        if not accepted then return false, reason end
        record.Generation += 1
        record.Request, record.SpawnOutpostId = nil, nil
        self:_setKingdom(player, record.State.KingdomId)
        self:_clearCharacter(player, record, true)
        self:_load(player)
        self:SendState()
        return true
    end
    local state, reason = self:_alive(player)
    if not state then return false, reason end
    if action == "Harvest" then
        if not identifier(payload.NodeId) then return false, "Malformed" end
        local entry = self._nodes[payload.NodeId]
        if not entry then return false, "UnknownNode" end
        local allowed, failure = Rules.CanHarvest(record.State, entry.State, Config, now)
        if not allowed then return false, failure end
        allowed, failure = self:_inReach(state, entry.View, Config.World.HarvestRange)
        if not allowed then return false, failure end
        allowed, failure = self.Combat:SpendEffort(player, Config.World.HarvestStaminaCost)
        if not allowed then return false, failure end
        -- No yield between the rule check, stamina spend and authoritative hit.
        local accepted, result = Rules.Harvest(record.State, entry.State, Config, now)
        if not accepted then return false, result end
        self:_renderNode(entry)
        self:SendState()
        return true
    elseif action == "BuildOutpost" then
        if not identifier(payload.OutpostId) then return false, "Malformed" end
        local entry = self._outposts[payload.OutpostId]
        if not entry then return false, "UnknownOutpost" end
        local allowed, failure = self:_inReach(state, entry.View, Config.World.BuildRange)
        if not allowed then return false, failure end
        local accepted, buildReason = Rules.BuildOutpost(record.State, entry.State, Config)
        if not accepted then return false, buildReason end
        self:_renderOutpost(entry)
        self:SendState()
        return true
    elseif action == "SetOutpostSpawn" then
        if type(payload.OutpostId) ~= "string" or #payload.OutpostId > 48 then return false, "Malformed" end
        if payload.OutpostId == "" then record.SpawnOutpostId = nil
        else
            local entry = self._outposts[payload.OutpostId]
            if not entry then return false, "UnknownOutpost" end
            if entry.State.Owner ~= record.State.KingdomId then return false, "NotOwner" end
            if not entry.State.Built then return false, "NotBuilt" end
            record.SpawnOutpostId = payload.OutpostId
        end
        self:SendState(player)
        return true
    end
    return false, "UnknownAction"
end

function WorldService:_onDeath(victim, killer)
    local player = victim.Subject
    local record = self._players[player]
    if not record or record.Model ~= victim.Model or self._deaths[victim.Model] or not record.State.KingdomId then return end
    self._deaths[victim.Model] = true
    local deaths = statistic(player, "Deaths")
    if deaths then deaths.Value += 1 end
    if killer and killer.Subject ~= player then
        local killerRecord = self._players[killer.Subject]
        if killerRecord and killerRecord.Model == killer.Model and killer.TeamId ~= victim.TeamId then
            local kills = statistic(killer.Subject, "Kills")
            if kills then kills.Value += 1 end
            if self.Remotes.Effects then self.Remotes.Effects:FireAllClients("Killfeed", {
                Killer = killer.Subject.DisplayName, Victim = player.DisplayName, TeamId = killer.TeamId,
            }) end
        end
    end
    self:_scheduleRespawn(player, record)
    self:SendState()
end

function WorldService:Start()
    if self._started then return end
    self._started = true
    self.Combat:SetEnabled(true)
    self:SendState()
end

function WorldService:SendState(player)
    local now = self._clock()
    local offset = self._serverTime() - now
    local kingdoms, outposts, nodes = {}, {}, {}
    local counts = {}
    for _, record in pairs(self._players) do
        local id = record.State.KingdomId
        if id then counts[id] = (counts[id] or 0) + 1 end
    end
    for _, id in ipairs(Config.KingdomOrder) do
        local definition = Config.Kingdoms[id]
        table.insert(kingdoms, { Id = id, Name = definition.Name, Color = definition.Color, Players = counts[id] or 0 })
    end
    for _, id in ipairs(orderedKeys(self._outposts)) do
        local entry = self._outposts[id]
        local point = entry.State
        table.insert(outposts, { Id = id, Name = entry.View.Name, Owner = point.Owner, Claimant = point.Claimant,
            Progress = point.Progress, Contested = point.Contested, Built = point.Built, Position = entry.View.Position })
    end
    for _, id in ipairs(orderedKeys(self._nodes)) do
        local entry = self._nodes[id]
        table.insert(nodes, { Id = id, Kind = entry.State.Kind, Position = entry.View.Position, HitsRemaining = entry.State.HitsRemaining,
            RespawnAt = entry.State.RespawnAt > 0 and entry.State.RespawnAt + offset or 0 })
    end
    local function send(subject, record)
        if subject.Parent ~= Players then return end
        self.Remotes.World:FireClient(subject, { KingdomId = record.State.KingdomId,
            KingdomChangeReadyAt = record.State.KingdomId and math.max(now, record.State.LastKingdomAt + Config.World.KingdomChangeCooldown) + offset or 0,
            Inventory = { Wood = record.State.Wood, Ore = record.State.Ore }, Kingdoms = kingdoms, Outposts = outposts, Nodes = nodes,
            SpawnOutpostId = record.SpawnOutpostId, RespawnAt = record.RespawnAt and record.RespawnAt + offset or nil })
    end
    if player then
        if self._players[player] then send(player, self._players[player]) end
    else
        for subject, record in pairs(self._players) do send(subject, record) end
    end
end

function WorldService:Step(dt)
    if not self._started or not finite(dt) or dt < 0 then return end
    local now, changed = self._clock(), false
    for player, record in pairs(self._players) do
        local model = record.Model
        if model then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            local state = self.Combat:GetState(player)
            if record.State.KingdomId and state and state.Model == model
                and (state.Dead or (humanoid and humanoid.Health <= 0)) then
                -- Combat reports deaths through a deferred callback. The world
                -- may step first, so account for this same death now; the model
                -- identity/death guard rejects the delayed duplicate callback.
                local killer = state.LastAttacker
                if killer and now - (state.LastHitAt or -math.huge) > 10 then killer = nil end
                self:_onDeath(state, killer)
            elseif not model.Parent or player.Character ~= model or not humanoid or not root or humanoid.Health <= 0
                or (record.State.KingdomId and (not state or state.Model ~= model or state.Root ~= root or state.Humanoid ~= humanoid)) then
                self:_scheduleRespawn(player, record)
                changed = true
            end
        end
        if not record.Model and not record.Request and not self:_currentRequest(player, record, record.ActiveRequest)
            and (not record.RespawnAt or now >= record.RespawnAt) then self:_load(player) end
    end
    for _, entry in pairs(self._nodes) do
        if Rules.RefreshNode(entry.State, Config, now) then self:_renderNode(entry); changed = true end
    end
    for _, entry in pairs(self._outposts) do
        local counts = {}
        for player, record in pairs(self._players) do
            local state = self:_alive(player)
            if state and (state.Root.Position - entry.View.Position).Magnitude <= Config.World.CaptureRadius then
                local kingdom = record.State.KingdomId
                counts[kingdom] = (counts[kingdom] or 0) + 1
            end
        end
        if Rules.StepCapture(entry.State, counts, Config, dt) then self:_renderOutpost(entry); changed = true end
    end
    self._snapshotElapsed += dt
    self._snapshotDirty = self._snapshotDirty or changed
    -- Capture progress changes every heartbeat. Bound full-world snapshots to
    -- five per second while a point changes, and once per second when idle.
    if (self._snapshotDirty and self._snapshotElapsed >= 0.2) or self._snapshotElapsed >= 1 then
        self._snapshotElapsed, self._snapshotDirty = 0, false
        self:SendState()
    end
end

return WorldService
