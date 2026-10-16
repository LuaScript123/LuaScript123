-- One locked 2v2 roster per round. Nobody joins or respawns during Battle.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MedievalShared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("MatchRules"))

local MatchService = {}
MatchService.__index = MatchService

local function statistic(player, name)
    local folder = player:FindFirstChild("leaderstats")
    return folder and folder:FindFirstChild(name)
end

local function memberName(member)
    if not member.IsBot then return member.Id.DisplayName end
    return "Garde " .. Config.Teams[member.TeamId].Name
end

function MatchService.new(remotes, map, combat)
    local self = setmetatable({}, MatchService)
    self.Remotes, self.Map, self.Combat = remotes, map, combat
    self.Phase, self.Round = "Intermission", 0
    self.Scores = { Dawn = 0, Ember = 0 }
    self.Message = "Préparez-vous pour le prochain duel en équipe."
    self.TimeLeft = Config.Game.IntermissionSeconds
    self.Roster = nil
    self._players, self._teams, self._spawns, self._subjects = {}, {}, {}, {}
    self._deaths = setmetatable({}, { __mode = "k" })
    self._epoch, self._joinOrder, self._snapshotElapsed = 0, 0, 0
    self._started = false
    for _, teamId in ipairs(Config.TeamOrder) do
        local definition = Config.Teams[teamId]
        local team = Teams:FindFirstChild(definition.Name)
        if not team or not team:IsA("Team") then
            team = Instance.new("Team")
            team.Name = definition.Name
            team.Parent = Teams
        end
        team.AutoAssignable = false
        team.TeamColor = BrickColor.new(Color3.fromRGB(table.unpack(definition.Color)))
        self._teams[teamId], self._spawns[teamId] = team, 0
    end
    -- This callback is shared by every human and bot; BotService never replaces it.
    combat.OnDeath = function(victim, killer) self:_onDeath(victim, killer) end
    return self
end

function MatchService:SetBotService(bots)
    self._bots = bots
end

function MatchService:GetSpawn(teamId)
    local spawns = self.Map.Spawns[teamId]
    if spawns and #spawns > 0 then
        self._spawns[teamId] = (self._spawns[teamId] or 0) % #spawns + 1
        return spawns[self._spawns[teamId]]
    end
    local direction = teamId == Config.TeamOrder[1] and -1 or 1
    return CFrame.new(self.Map.Center + Vector3.new(direction * 40, 5, 0))
end

function MatchService:_setTeam(player, teamId)
    player.Team = teamId and self._teams[teamId] or nil
    player.Neutral = teamId == nil
    player:SetAttribute("TeamId", teamId)
end

function MatchService:_currentRequest(player, record, request)
    return request ~= nil and self._players[player] == record and player.Parent == Players
        and self.Phase == "Preparing" and self._epoch == request.Epoch and self.Round == request.Round
        and self.Roster == request.Roster and record.Generation == request.Generation
        and Rules.Get(request.Roster, player) ~= nil and not Rules.Get(request.Roster, player).Eliminated
end

function MatchService:AddPlayer(player)
    if self._players[player] or player.Parent ~= Players then return end
    self._joinOrder += 1
    local record = { Generation = 0, JoinOrder = self._joinOrder, LoadRunning = false }
    self._players[player] = record
    self:_setTeam(player, nil)
    player:SetAttribute("Spectating", true)
    player:SetAttribute("Eliminated", false)
    local stats = player:FindFirstChild("leaderstats")
    if not stats then
        stats = Instance.new("Folder")
        stats.Name, stats.Parent = "leaderstats", player
    end
    for _, name in ipairs({ "Kills", "Deaths" }) do
        if not stats:FindFirstChild(name) then
            local value = Instance.new("IntValue")
            value.Name, value.Parent = name, stats
        end
    end
    record.AddedConnection = player.CharacterAdded:Connect(function(model)
        if self._players[player] ~= record then return end
        if self:_currentRequest(player, record, record.ActiveRequest) then return end
        if record.ActiveRequest then
            -- A timed-out LoadCharacterAsync may finish in a LATER preparation.
            -- Ignore that result without aborting the newer queued request.
            model:Destroy()
            return
        end
        -- Unsolicited/default loads cannot revive an eliminated member or insert
        -- a fifth fighter. In particular Reset outside a round grants no respawn.
        if self.Roster then
            local member = Rules.Get(self.Roster, player)
            if member and member.Model ~= model then
                if self.Phase == "Battle" then self:_eliminate(player)
                elseif self.Phase == "Preparing" then self._abortReason = "Un personnage a été remplacé." end
            end
        end
        model:Destroy()
    end)
    record.RemovingConnection = player.CharacterRemoving:Connect(function(model)
        if self._players[player] ~= record or not self.Roster then return end
        local member = Rules.Get(self.Roster, player)
        if not member or member.Model ~= model or member.Eliminated then return end
        if self.Phase == "Battle" then self:_eliminate(player)
        elseif self.Phase == "Preparing" then self._abortReason = "Un personnage a disparu pendant la préparation." end
    end)
    if player.Character then player.Character:Destroy() end
    -- Late arrivals wait without a combat character until the NEXT preparation.
    self:SendState(player)
end

function MatchService:RemovePlayer(player)
    local record = self._players[player]
    if not record then return end
    record.Generation += 1
    record.Request = nil
    if self.Roster and Rules.Get(self.Roster, player) then
        self:_eliminate(player)
        if self.Phase == "Preparing" then self._abortReason = "Un joueur a quitté la préparation." end
    end
    record.AddedConnection:Disconnect()
    record.RemovingConnection:Disconnect()
    self._players[player] = nil
    self.Combat:Unregister(player)
end

function MatchService:SpawnPlayer(player)
    local record = self._players[player]
    local member = self.Roster and Rules.Get(self.Roster, player)
    if self.Phase ~= "Preparing" or not record or not member or member.Eliminated then
        return false, "NotPreparing"
    end
    if member.Ready or record.Request or self:_currentRequest(player, record, record.ActiveRequest) then
        return false, "AlreadyLoading"
    end
    record.Generation += 1
    record.Request = {
        Generation = record.Generation, Epoch = self._epoch, Round = self.Round,
        Roster = self.Roster, TeamId = member.TeamId,
    }
    if record.LoadRunning then return true end
    record.LoadRunning = true
    -- Serialize LoadCharacterAsync per player. Results must match BOTH phase
    -- and epoch; a late result from an aborted preparation is never registered.
    task.spawn(function()
        while self._players[player] == record and player.Parent == Players and record.Request do
            local request = record.Request
            record.Request, record.ActiveRequest = nil, request
            local model
            local ok, problem = pcall(function()
                player:LoadCharacterAsync()
                model = player.Character
                -- Reject stale loads before any child wait. CharacterAdded may
                -- already have destroyed this old result while a newer request
                -- is queued; waiting on it would consume the next timeout too.
                if not self:_currentRequest(player, record, request) then return end
                if not model then error("Personnage absent.") end
                local humanoid = model:WaitForChild("Humanoid", 10)
                local root = model:WaitForChild("HumanoidRootPart", 10)
                if not self:_currentRequest(player, record, request) then return end
                if not humanoid or not root or model ~= player.Character or humanoid.Health <= 0 then
                    error("Personnage incomplet ou éliminé pendant son chargement.")
                end
                for _, child in ipairs(model:GetChildren()) do
                    if child:IsA("ForceField") then child:Destroy() end
                end
                model:SetAttribute("MatchRound", request.Round)
                model:SetAttribute("Eliminated", false)
                model:PivotTo(self:GetSpawn(request.TeamId))
                local state = self.Combat:Register(player, model, request.TeamId)
                if not state then error("Enregistrement du combattant impossible.") end
                local currentMember = Rules.Get(request.Roster, player)
                currentMember.Model, currentMember.Subject = model, player
                record.Model = model
                Rules.SetReady(request.Roster, player, true)
            end)
            local current = self:_currentRequest(player, record, request)
            if not ok and current then
                warn("Préparation de " .. player.Name .. ": " .. tostring(problem))
                self._abortReason = "Le chargement d'un joueur a échoué. Nouvelle tentative bientôt."
            end
            if not current and model and model.Parent then model:Destroy() end
            record.ActiveRequest = nil
        end
        record.LoadRunning = false
    end)
    return true
end

function MatchService:RegisterBot(id, model, teamId, round, epoch)
    local member = self.Roster and Rules.Get(self.Roster, id)
    if self.Phase ~= "Preparing" or self.Round ~= round or self._epoch ~= epoch
        or not member or not member.IsBot or member.TeamId ~= teamId or member.Model or member.Eliminated then
        return false
    end
    model:SetAttribute("MatchRound", round)
    model:SetAttribute("Eliminated", false)
    local state = self.Combat:Register(model, model, teamId)
    if not state then return false end
    member.Model, member.Subject = model, model
    self._subjects[model] = id
    Rules.SetReady(self.Roster, id, true)
    return true
end

function MatchService:_eliminate(id)
    if not self.Roster or not Rules.Eliminate(self.Roster, id) then return false end
    local member = Rules.Get(self.Roster, id)
    if member.Model then member.Model:SetAttribute("Eliminated", true) end
    if not member.IsBot and member.Id.Parent == Players then
        member.Id:SetAttribute("Eliminated", true)
        member.Id:SetAttribute("Spectating", true)
    end
    return true
end

function MatchService:_onDeath(victim, killer)
    local id = self._subjects[victim.Subject]
    local member = id and self.Roster and Rules.Get(self.Roster, id)
    if not member or member.Model ~= victim.Model or victim.Model:GetAttribute("MatchRound") ~= self.Round then return end
    if self.Phase == "Preparing" then
        self:_eliminate(id)
        self._abortReason = "Un combattant est mort pendant la préparation."
        return
    end
    -- Combat defers death notifications. Step can already have reconciled the
    -- final victim and ended this round before its notification runs. Accept
    -- that trailing callback only for an eliminated member of this same roster;
    -- a survivor resetting during intermission cannot add another death/kill.
    local trailingDeath = self.Phase == "Intermission" and self.Roster.Started and member.Eliminated
    if (self.Phase ~= "Battle" and not trailingDeath) or self._deaths[victim.Model] then return end
    self._deaths[victim.Model] = true
    self:_eliminate(id)
    if not member.IsBot and self._players[member.Id] then
        local deaths = statistic(member.Id, "Deaths")
        if deaths then deaths.Value += 1 end
    end
    local killerId = killer and self._subjects[killer.Subject]
    local killerMember = killerId and Rules.Get(self.Roster, killerId)
    if killerMember and killerMember.Model == killer.Model and killerMember.TeamId ~= member.TeamId then
        if not killerMember.IsBot and self._players[killerMember.Id] then
            local kills = statistic(killerMember.Id, "Kills")
            if kills then kills.Value += 1 end
        end
        self.Remotes.Effects:FireAllClients("Killfeed", {
            Killer = memberName(killerMember), Victim = memberName(member), TeamId = killerMember.TeamId,
        })
    end
    -- Resolve in Step after checking ALL four health values. Same-frame double
    -- eliminations can then draw instead of prematurely awarding the first team.
    self:SendState()
end

function MatchService:_unregisterAll()
    local subjects = {}
    for subject in pairs(self.Combat:GetStates()) do table.insert(subjects, subject) end
    for _, subject in ipairs(subjects) do self.Combat:Unregister(subject) end
end

function MatchService:_intermission(message, winner)
    self.Phase, self.Winner, self.Message = "Intermission", winner, message
    self._epoch += 1
    self._deadline = os.clock() + Config.Game.IntermissionSeconds
    self.TimeLeft = Config.Game.IntermissionSeconds
    self._battleStartedAt = nil
    self.Combat:SetEnabled(false)
    self:_unregisterAll()
    for player, record in pairs(self._players) do
        record.Generation += 1
        record.Request = nil
        player:SetAttribute("Spectating", true)
    end
    self:SendState()
end

function MatchService:_abortPreparation(message)
    self:_intermission(message or "Préparation interrompue. Nouvelle tentative bientôt.", nil)
    self.Roster, self._subjects, self._abortReason = nil, {}, nil
    if self._bots then self._bots:Cleanup() end
    for player, record in pairs(self._players) do
        record.Model = nil
        player:SetAttribute("Eliminated", false)
        self:_setTeam(player, nil)
        if player.Character then player.Character:Destroy() end
    end
    self:SendState()
end

function MatchService:_beginPreparing()
    self._epoch += 1
    self.Round += 1
    self.Phase, self.Winner, self._abortReason = "Preparing", nil, nil
    self.Message = "Préparation des quatre combattants…"
    self._deadline = os.clock() + Config.Game.PreparingTimeoutSeconds
    self.TimeLeft = Config.Game.PreparingTimeoutSeconds
    self.Roster, self._subjects = nil, {}
    self.Combat:SetEnabled(false)
    self:_unregisterAll()
    if self._bots then self._bots:Cleanup() end
    local humans = {}
    for player, record in pairs(self._players) do
        record.Generation += 1
        record.Request, record.Model = nil, nil
        player:SetAttribute("Spectating", true)
        player:SetAttribute("Eliminated", false)
        self:_setTeam(player, nil)
        if player.Character then player.Character:Destroy() end
        if player.Parent == Players then table.insert(humans, player) end
    end
    table.sort(humans, function(a, b) return self._players[a].JoinOrder < self._players[b].JoinOrder end)
    local roster = Rules.New(Config.TeamOrder, Config.Game.TeamSize)
    self.Roster = roster
    local counts = {}
    for _, teamId in ipairs(Config.TeamOrder) do counts[teamId] = 0 end
    local maximum = Config.Game.TeamSize * #Config.TeamOrder
    for index = 1, math.min(#humans, maximum) do
        local player = humans[index]
        local teamId = Config.TeamOrder[(index - 1) % #Config.TeamOrder + 1]
        Rules.Add(roster, player, teamId)
        Rules.Get(roster, player).IsBot = false
        counts[teamId] += 1
        self._subjects[player] = player
        self:_setTeam(player, teamId)
        player:SetAttribute("Spectating", false)
    end
    local botCount = 0
    if Config.Game.FillWithBots then
        for _, teamId in ipairs(Config.TeamOrder) do
            for slot = counts[teamId] + 1, Config.Game.TeamSize do
                local id = "bot:" .. self._epoch .. ":" .. teamId .. ":" .. slot
                Rules.Add(roster, id, teamId)
                Rules.Get(roster, id).IsBot = true
                botCount += 1
            end
        end
    end
    if not Rules.Lock(roster) then
        self:_abortPreparation("Quatre combattants sont nécessaires. En attente de joueurs.")
        return
    end
    for id, member in pairs(roster.Members) do
        if not member.IsBot then self:SpawnPlayer(id) end
    end
    if botCount > 0 then
        if not self._bots then
            self._abortReason = "Les gardes ne sont pas disponibles."
        else
            local ok, problem = pcall(function() self._bots:Prepare(roster, self.Round, self._epoch) end)
            if not ok then
                warn("Préparation des gardes : " .. tostring(problem))
                self._abortReason = "Le chargement des gardes a échoué."
            end
        end
    end
    self:SendState()
end

function MatchService:_beginBattle()
    if not Rules.Begin(self.Roster) then return end
    local now = os.clock()
    self.Phase, self.Message = "Battle", "Deux contre deux. Aucun retour après la mort."
    self._battleStartedAt, self._deadline, self.TimeLeft = now, nil, nil
    -- Reposition everyone and rebase protection together after loading. A player
    -- who loaded early cannot cross the arena while the other three are loading.
    for _, member in pairs(self.Roster.Members) do
        local state = self.Combat:GetState(member.Subject)
        member.Model:PivotTo(self:GetSpawn(member.TeamId))
        state.Root.AssemblyLinearVelocity = Vector3.zero
        state.Root.AssemblyAngularVelocity = Vector3.zero
        state.SpawnProtectedUntil = now + Config.Game.SpawnProtectionSeconds
        state.PendingAttack = nil
        state.NextAttributeAt = 0
        member.Model:SetAttribute("SpawnProtected", true)
    end
    self.Combat:SetEnabled(true)
    self:SendState()
end

function MatchService:Start()
    if self._started then return end
    self._started = true
    self:_intermission("Préparez-vous pour le prochain duel en équipe.", nil)
end

function MatchService:SendState(player)
    local alive = self.Roster and Rules.CountAlive(self.Roster) or { Dawn = 0, Ember = 0 }
    local roster = {}
    if self.Roster then
        for _, member in pairs(self.Roster.Members) do
            table.insert(roster, {
                Name = memberName(member), TeamId = member.TeamId, Alive = not member.Eliminated,
                IsBot = member.IsBot, UserId = not member.IsBot and member.Id.UserId or nil, Model = member.Model,
            })
        end
    end
    local snapshot = {
        Phase = self.Phase, Round = self.Round,
        TimeLeft = self.Phase ~= "Battle" and math.max(0, math.ceil(self._deadline and self._deadline - os.clock() or self.TimeLeft)) or nil,
        Elapsed = self.Phase == "Battle" and math.floor(os.clock() - self._battleStartedAt) or nil,
        Alive = alive, Scores = { Dawn = self.Scores.Dawn, Ember = self.Scores.Ember },
        TeamSize = Config.Game.TeamSize, Winner = self.Winner, Message = self.Message, Roster = roster,
    }
    if player then
        if player.Parent == Players then self.Remotes.State:FireClient(player, snapshot) end
    else
        self.Remotes.State:FireAllClients(snapshot)
    end
end

function MatchService:Step(dt)
    if not self._started then return end
    local now = os.clock()
    if self.Phase == "Intermission" then
        self.TimeLeft = math.max(0, math.ceil(self._deadline - now))
        if now >= self._deadline then self:_beginPreparing() end
    elseif self.Phase == "Preparing" then
        self.TimeLeft = math.max(0, math.ceil(self._deadline - now))
        for id, member in pairs(self.Roster.Members) do
            if member.Eliminated or (not member.IsBot and not self._players[id]) then
                self._abortReason = "Un combattant a quitté la préparation."
            elseif member.Ready then
                local state = self.Combat:GetState(member.Subject)
                if not state or state.Dead or not member.Model.Parent or state.Humanoid.Health <= 0 then
                    self._abortReason = "Un combattant n'est plus prêt."
                end
            end
        end
        if self._abortReason then self:_abortPreparation(self._abortReason)
        elseif Rules.IsReady(self.Roster) then self:_beginBattle()
        elseif now >= self._deadline then self:_abortPreparation("Le chargement a pris trop de temps. Nouvelle tentative bientôt.") end
    elseif self.Phase == "Battle" then
        for id, member in pairs(self.Roster.Members) do
            if not member.Eliminated then
                local state = self.Combat:GetState(member.Subject)
                if not state or state.Dead or not member.Model.Parent or state.Humanoid.Health <= 0
                    or (not member.IsBot and not self._players[id]) then
                    self:_eliminate(id)
                end
            end
        end
        local finished, winner = Rules.Resolve(self.Roster)
        if finished then
            if winner then self.Scores[winner] += 1 end
            self:_intermission(winner and (Config.Teams[winner].Name .. " remportent la manche !") or "Double élimination : égalité !", winner)
        end
    end
    self._snapshotElapsed += dt
    if self._snapshotElapsed >= 0.5 then
        self._snapshotElapsed = 0
        self:SendState()
    end
end

return MatchService
