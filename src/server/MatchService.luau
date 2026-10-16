-- Human-only, consent-based matches. The lobby is independent of the arena.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("MedievalShared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("MatchRules"))
local Invites = require(Shared:WaitForChild("InvitationRules"))

local MatchService = {}
MatchService.__index = MatchService

local function statistic(player, name)
    local folder = player:FindFirstChild("leaderstats")
    return folder and folder:FindFirstChild(name)
end

local function memberName(member)
    return member.Id.DisplayName
end

function MatchService.new(remotes, map, combat, profiles)
    local self = setmetatable({}, MatchService)
    self.Remotes, self.Map, self.Combat, self.Profiles = remotes, map, combat, profiles
    self.Phase, self.Round, self.TimeLeft = "Lobby", 0, nil
    self.Scores = { Dawn = 0, Ember = 0 }
    self.Message = "Invitez des joueurs au combat depuis le lobby."
    self.Roster = nil
    self._players, self._teams, self._spawns, self._subjects = {}, {}, {}, {}
    self._deaths = setmetatable({}, { __mode = "k" })
    self._epoch, self._snapshotElapsed, self._lobbyElapsed = 0, 0, 0
    self._invitations = Invites.New(Config.Invites.CooldownSeconds, Config.Invites.ExpiresSeconds)
    self._started, self._lobbySpawn = false, 0
    for _, teamId in ipairs(Config.TeamOrder) do
        local definition = Config.Teams[teamId]
        local team = Teams:FindFirstChild(definition.Name)
        if not team or not team:IsA("Team") then
            team = Instance.new("Team")
            team.Name, team.Parent = definition.Name, Teams
        end
        team.AutoAssignable = false
        team.TeamColor = BrickColor.new(Color3.fromRGB(table.unpack(definition.Color)))
        self._teams[teamId], self._spawns[teamId] = team, 0
    end
    combat.OnDeath = function(victim, killer) self:_onDeath(victim, killer) end
    return self
end

function MatchService:GetSpawn(teamId)
    if teamId == nil then
        local spawns = self.Map.LobbySpawns
        if spawns and #spawns > 0 then
            self._lobbySpawn = self._lobbySpawn % #spawns + 1
            return spawns[self._lobbySpawn]
        end
        return CFrame.new(self.Map.LobbyCenter or (self.Map.Center + Vector3.new(0, 5, -160)))
    end
    local spawns = self.Map.Spawns[teamId]
    if spawns and #spawns > 0 then
        self._spawns[teamId] = (self._spawns[teamId] or 0) % #spawns + 1
        return spawns[self._spawns[teamId]]
    end
    local direction = teamId == Config.TeamOrder[1] and -1 or 1
    return CFrame.new(self.Map.Center + Vector3.new(direction * 40, 5, 0))
end

function MatchService:_setTeam(player, teamId)
    player.Team, player.Neutral = teamId and self._teams[teamId] or nil, teamId == nil
    player:SetAttribute("TeamId", teamId)
end

function MatchService:_setActivity(player, activity)
    player:SetAttribute("Activity", activity)
    player:SetAttribute("Spectating", false)
    player:SetAttribute("Eliminated", false)
end

function MatchService:_currentRequest(player, record, request)
    if not request or self._players[player] ~= record or player.Parent ~= Players
        or record.Generation ~= request.Generation then return false end
    if request.Kind == "Lobby" then return player:GetAttribute("Activity") == "Lobby" end
    local member = self.Roster == request.Roster and Rules.Get(request.Roster, player)
    return self.Phase == "Preparing" and self._epoch == request.Epoch and self.Round == request.Round
        and member ~= nil and not member.Eliminated
end

function MatchService:_destroyCharacter(player, record)
    -- Only this participant's model is touched. Lobby visitors are never swept.
    record.Model = nil
    if player.Character then player.Character:Destroy() end
end

function MatchService:_load(player, kind)
    local record = self._players[player]
    if not record or player.Parent ~= Players then return false, "UnknownPlayer" end
    local member = self.Roster and Rules.Get(self.Roster, player)
    if kind == "Combat" and (self.Phase ~= "Preparing" or not member or member.Eliminated) then
        return false, "NotPreparing"
    end
    if kind == "Lobby" and player:GetAttribute("Activity") ~= "Lobby" then return false, "NotInLobby" end
    if record.Request or self:_currentRequest(player, record, record.ActiveRequest) then return false, "AlreadyLoading" end
    if kind == "Combat" and member.Ready then return false, "AlreadyLoading" end
    record.Generation += 1
    record.Request = {
        Kind = kind, Generation = record.Generation, Epoch = self._epoch, Round = self.Round,
        Roster = self.Roster, TeamId = member and member.TeamId or nil,
    }
    record.RespawnAt = nil
    if record.LoadRunning then return true end
    record.LoadRunning = true
    task.spawn(function()
        while self._players[player] == record and player.Parent == Players and record.Request do
            local request = record.Request
            record.Request, record.ActiveRequest = nil, request
            local model
            local ok, problem = pcall(function()
                player:LoadCharacterAsync()
                model = player.Character
                -- The CharacterAdded result can belong to an aborted lobby or
                -- preparation. Reject it before waiting for any missing children.
                if not self:_currentRequest(player, record, request) then return end
                if not model then error("Personnage absent.") end
                local humanoid = model:WaitForChild("Humanoid", 10)
                local root = model:WaitForChild("HumanoidRootPart", 10)
                if not self:_currentRequest(player, record, request) then return end
                if not humanoid or not root or model ~= player.Character or humanoid.Health <= 0 then
                    error("Personnage incomplet ou mort pendant le chargement.")
                end
                for _, child in ipairs(model:GetChildren()) do
                    if child:IsA("ForceField") then child:Destroy() end
                end
                model:SetAttribute("Eliminated", false)
                if request.Kind == "Lobby" then
                    model:SetAttribute("Combatant", false)
                    model:SetAttribute("MatchRound", nil)
                    model:PivotTo(self:GetSpawn(nil))
                    humanoid.MaxHealth, humanoid.Health = Config.Player.MaxHealth, Config.Player.MaxHealth
                    humanoid.WalkSpeed = Config.Player.WalkSpeed
                    local shield = Instance.new("ForceField")
                    shield.Name, shield.Visible, shield.Parent = "LobbyProtection", false, model
                    if self.Combat.DressCharacter then self.Combat:DressCharacter(player, model) end
                else
                    model:SetAttribute("MatchRound", request.Round)
                    model:PivotTo(self:GetSpawn(request.TeamId))
                    local state = self.Combat:Register(player, model, request.TeamId)
                    if not state then error("Enregistrement du combattant impossible.") end
                    local currentMember = Rules.Get(request.Roster, player)
                    currentMember.Model, currentMember.Subject = model, player
                    Rules.SetReady(request.Roster, player, true)
                end
                record.Model = model
            end)
            local current = self:_currentRequest(player, record, request)
            if not ok and current then
                warn("Chargement de " .. player.Name .. ": " .. tostring(problem))
                if request.Kind == "Combat" then self._abortReason = "Le chargement d'un joueur a échoué."
                else record.RespawnAt = os.clock() + Config.Game.LobbyRespawnSeconds end
            end
            if not current and model and model.Parent then model:Destroy() end
            record.ActiveRequest = nil
        end
        record.LoadRunning = false
    end)
    return true
end

function MatchService:SpawnPlayer(player)
    return self:_load(player, "Combat")
end

function MatchService:AddPlayer(player)
    if self._players[player] or player.Parent ~= Players then return end
    local record = { Generation = 0, LoadRunning = false }
    self._players[player] = record
    self:_setTeam(player, nil)
    self:_setActivity(player, "Lobby")
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
        if record.ActiveRequest then model:Destroy(); return end
        local member = self.Roster and Rules.Get(self.Roster, player)
        if member and member.Model ~= model then
            if self.Phase == "Battle" then self:_eliminate(player)
            elseif self.Phase == "Preparing" then self._abortReason = "Un personnage a été remplacé." end
        end
        model:Destroy()
        if player:GetAttribute("Activity") == "Lobby" then
            record.Model, record.RespawnAt = nil, os.clock() + Config.Game.LobbyRespawnSeconds
        end
    end)
    record.RemovingConnection = player.CharacterRemoving:Connect(function(model)
        if self._players[player] ~= record then return end
        local member = self.Roster and Rules.Get(self.Roster, player)
        if member and member.Model == model and not member.Eliminated then
            if self.Phase == "Battle" then self:_eliminate(player)
            elseif self.Phase == "Preparing" then self._abortReason = "Un personnage a disparu pendant la préparation." end
        elseif player:GetAttribute("Activity") == "Lobby" and record.Model == model then
            record.Model, record.RespawnAt = nil, os.clock() + Config.Game.LobbyRespawnSeconds
        end
    end)
    self:_destroyCharacter(player, record)
    self:_load(player, "Lobby")
    self:SendState(player)
    self:SendLobby()
end

function MatchService:RemovePlayer(player)
    local record = self._players[player]
    if not record then return end
    record.Generation += 1
    record.Request = nil
    Invites.RemovePlayer(self._invitations, player.UserId)
    record.AddedConnection:Disconnect()
    record.RemovingConnection:Disconnect()
    self._players[player] = nil
    local member = self.Roster and Rules.Get(self.Roster, player)
    if member then
        self._forfeit = true
        if self.Phase == "Preparing" then
            self:_abortPreparation("Un joueur a quitté la préparation.")
        elseif self.Phase == "Battle" then
            self:_eliminate(player)
            local winner = member.TeamId == Config.TeamOrder[1] and Config.TeamOrder[2] or Config.TeamOrder[1]
            self:_finishBattle(winner, "Combat terminé par forfait.", false)
        end
    end
    self.Combat:Unregister(player)
    self:SendLobby()
end

function MatchService:_playerById(userId)
    for player in pairs(self._players) do
        if player.UserId == userId and player.Parent == Players then return player end
    end
    return nil
end

function MatchService:_available(userId)
    local player = self:_playerById(userId)
    return player ~= nil and player:GetAttribute("Activity") == "Lobby" and player:GetAttribute("ProfileLoaded") == true
end

function MatchService:HandleLobbyAction(player, action, payload)
    if not self._players[player] or player.Parent ~= Players then return false, "UnknownPlayer" end
    if type(payload) ~= "table" then return false, "InvalidPayload" end
    local now, accepted, reason = os.clock(), false, nil
    -- Bound malformed-request spam as well as successful invitations. This
    -- bucket is deliberately separate from the visible 15s invitation cooldown.
    local record = self._players[player]
    record.ActionTokens = math.min(12, (record.ActionTokens or 12) + math.max(0, now - (record.ActionAt or now)) * 6)
    record.ActionAt = now
    if record.ActionTokens < 1 then return false, "RateLimited" end
    record.ActionTokens -= 1
    if action == "Invite" then
        if Config.Game.AllowedModes and not Config.Game.AllowedModes[payload.Mode] then return false, "InvalidMode" end
        if not self:_available(player.UserId) then return false, "PlayerUnavailable" end
        local ids
        if payload.Mode == "Duel" then ids = { player.UserId, payload.OpponentUserId }
        elseif payload.Mode == "Teams" then
            ids = { player.UserId, payload.AllyUserId, payload.OpponentUserId, payload.OpponentAllyUserId }
        end
        local invite
        invite, reason = Invites.Create(self._invitations, player.UserId, payload.Mode, ids, now,
            function(userId) return self:_available(userId) end, self.Phase ~= "Lobby")
        accepted = invite ~= nil
    elseif action == "InviteRespond" then
        local invite, ready
        invite, reason, ready = Invites.Respond(self._invitations, player.UserId, payload.InviteId, payload.Accept, now)
        accepted = invite ~= nil
        if ready then
            if self.Phase ~= "Lobby" then reason, accepted = "ArenaBusy", false
            else
                for _, userId in ipairs(invite.Members) do
                    if not self:_available(userId) then reason, accepted = "PlayerUnavailable", false end
                end
                if accepted then self:_beginPreparing(invite) end
            end
        end
    elseif action == "InviteCancel" then
        accepted, reason = Invites.Cancel(self._invitations, player.UserId, payload.InviteId)
    else
        return false, "UnknownAction"
    end
    self:SendLobby()
    return accepted, reason
end

function MatchService:_eliminate(id)
    if not self.Roster or not Rules.Eliminate(self.Roster, id) then return false end
    local member = Rules.Get(self.Roster, id)
    if member.Model then member.Model:SetAttribute("Eliminated", true) end
    if self._players[id] and id.Parent == Players then
        id:SetAttribute("Eliminated", true)
        id:SetAttribute("Spectating", true)
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
    -- Retain a just-ended roster through Results, so an already-deferred final
    -- death gets its statistics exactly once even after Step resolves the match.
    local trailingDeath = self.Phase == "Results" and self.Roster.Started and member.Eliminated
    if (self.Phase ~= "Battle" and not trailingDeath) or self._deaths[victim.Model] then return end
    self._deaths[victim.Model] = true
    self:_eliminate(id)
    local deaths = self._players[id] and statistic(id, "Deaths")
    if deaths then deaths.Value += 1 end
    local killerId = killer and self._subjects[killer.Subject]
    local killerMember = killerId and Rules.Get(self.Roster, killerId)
    if killerMember and killerMember.Model == killer.Model and killerMember.TeamId ~= member.TeamId then
        local kills = self._players[killerId] and statistic(killerId, "Kills")
        if kills then kills.Value += 1 end
        self.Remotes.Effects:FireAllClients("Killfeed", {
            Killer = memberName(killerMember), Victim = memberName(member), TeamId = killerMember.TeamId,
        })
    end
    self:SendState()
end

function MatchService:_unregisterRoster()
    if not self.Roster then return end
    for id in pairs(self.Roster.Members) do self.Combat:Unregister(id) end
end

function MatchService:_returnLobby(message)
    local oldRoster = self.Roster
    self._epoch += 1
    self.Combat:SetEnabled(false)
    self:_unregisterRoster()
    self.Roster, self._subjects, self._abortReason = nil, {}, nil
    self.Phase, self.TimeLeft, self._deadline, self._battleStartedAt = "Lobby", nil, nil, nil
    self.Winner, self.Message = nil, message or "Invitez des joueurs au combat depuis le lobby."
    if oldRoster then
        for player in pairs(oldRoster.Members) do
            local record = self._players[player]
            if record and player.Parent == Players then
                record.Generation += 1
                record.Request = nil
                self:_setActivity(player, "Lobby")
                self:_setTeam(player, nil)
                self:_destroyCharacter(player, record)
                self:_load(player, "Lobby")
            end
        end
    end
    self:SendState()
    self:SendLobby()
end

function MatchService:_abortPreparation(message)
    self._forfeit = true
    self:_returnLobby(message or "Préparation interrompue. Vous pouvez lancer une nouvelle invitation.")
end

function MatchService:_beginPreparing(invite)
    if self.Phase ~= "Lobby" then return false end
    local roster = Rules.New(Config.TeamOrder, invite.Mode == "Duel" and 1 or 2)
    for index, userId in ipairs(invite.Members) do
        local player = self:_playerById(userId)
        if not player or not self:_available(userId) then return false end
        local teamIndex = invite.Mode == "Duel" and index or (index <= 2 and 1 or 2)
        if not Rules.Add(roster, player, Config.TeamOrder[teamIndex]) then return false end
        Rules.Get(roster, player).IsBot = false
    end
    if not Rules.Lock(roster) then return false end
    self._epoch += 1
    self.Round += 1
    self._matchId = HttpService:GenerateGUID(false)
    self.Phase, self.Winner, self._abortReason, self._forfeit, self._awarded = "Preparing", nil, nil, false, false
    self.Message = "Préparation des combattants…"
    self._deadline, self.TimeLeft = os.clock() + Config.Game.PreparingTimeoutSeconds, Config.Game.PreparingTimeoutSeconds
    self.Roster, self._subjects = roster, {}
    self.Combat:SetEnabled(false)
    -- Other pending groups are released when the sole arena becomes occupied.
    Invites.Clear(self._invitations)
    for player, member in pairs(roster.Members) do
        local record = self._players[player]
        record.Generation += 1
        record.Request = nil
        self:_setActivity(player, "Preparing")
        self:_setTeam(player, member.TeamId)
        self._subjects[player] = player
        self:_destroyCharacter(player, record)
        self:SpawnPlayer(player)
    end
    self:SendState()
    self:SendLobby()
    return true
end

function MatchService:_beginBattle()
    if not Rules.Begin(self.Roster) then return end
    local now = os.clock()
    self.Phase, self.Message = "Battle", "Éliminez l'équipe adverse. Une seule vie par combattant."
    self._battleStartedAt, self._deadline, self.TimeLeft = now, nil, nil
    for player, member in pairs(self.Roster.Members) do
        local state = self.Combat:GetState(member.Subject)
        member.Model:PivotTo(self:GetSpawn(member.TeamId))
        state.Root.AssemblyLinearVelocity, state.Root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        state.SpawnProtectedUntil = now + Config.Game.SpawnProtectionSeconds
        state.PendingAttack, state.NextAttributeAt = nil, 0
        member.Model:SetAttribute("SpawnProtected", true)
        self:_setActivity(player, "Battle")
    end
    self.Combat:SetEnabled(true)
    self:SendState()
    self:SendLobby()
end

function MatchService:_finishBattle(winner, message, reward)
    if self.Phase ~= "Battle" then return end
    self.Phase, self.Winner, self.Message = "Results", winner, message
    self._deadline, self.TimeLeft = os.clock() + Config.Game.ResultSeconds, Config.Game.ResultSeconds
    self.Combat:SetEnabled(false)
    self:_unregisterRoster()
    if winner then self.Scores[winner] += 1 end
    for player in pairs(self.Roster.Members) do
        local record = self._players[player]
        if record and player.Parent == Players then player:SetAttribute("Activity", "Results") end
    end
    if reward and not self._forfeit and not self._awarded and self.Profiles then
        local valid = true
        for player in pairs(self.Roster.Members) do
            if not self._players[player] or player.Parent ~= Players then valid = false end
        end
        if valid then
            self._awarded = true
            self.Profiles:AwardMatch(self._matchId, self.Roster.Members, winner)
        end
    end
    self:SendState()
    self:SendLobby()
end

function MatchService:Start()
    if self._started then return end
    self._started = true
    self.Combat:SetEnabled(false)
    self:SendState()
    self:SendLobby()
end

function MatchService:SendState(player)
    local alive = self.Roster and Rules.CountAlive(self.Roster) or { Dawn = 0, Ember = 0 }
    local roster, participants = {}, {}
    if self.Roster then
        for _, member in pairs(self.Roster.Members) do
            table.insert(participants, member.Id.UserId)
            table.insert(roster, {
                Name = memberName(member), TeamId = member.TeamId, Alive = not member.Eliminated,
                IsBot = false, UserId = member.Id.UserId, Model = member.Model,
            })
        end
    end
    local snapshot = {
        Phase = self.Phase, Round = self.Round,
        TimeLeft = self._deadline and math.max(0, math.ceil(self._deadline - os.clock())) or nil,
        Elapsed = self.Phase == "Battle" and math.floor(os.clock() - self._battleStartedAt) or nil,
        Alive = alive, Scores = { Dawn = self.Scores.Dawn, Ember = self.Scores.Ember },
        TeamSize = self.Roster and self.Roster.TeamSize or Config.Game.TeamSize,
        Winner = self.Winner, Message = self.Message, Roster = roster, Participants = participants,
    }
    if player then
        if player.Parent == Players then self.Remotes.State:FireClient(player, snapshot) end
    else self.Remotes.State:FireAllClients(snapshot) end
end

function MatchService:_invitationSnapshot(invite, offset)
    if not invite then return nil end
    local host = self:_playerById(invite.HostId)
    local snapshot = { Id = invite.Id, HostName = host and host.DisplayName or "Joueur", Mode = invite.Mode,
        ExpiresAt = invite.ExpiresAt + offset, Members = {} }
    for index, userId in ipairs(invite.Members) do
        local player = self:_playerById(userId)
        local teamIndex = invite.Mode == "Duel" and index or (index <= 2 and 1 or 2)
        table.insert(snapshot.Members, { UserId = userId, Name = player and player.DisplayName or "Joueur",
            TeamId = Config.TeamOrder[teamIndex], Accepted = invite.Accepted[userId] == true })
    end
    return snapshot
end

function MatchService:SendLobby(player)
    if not self.Remotes.Lobby then return end
    local players = {}
    for subject in pairs(self._players) do
        if subject.Parent == Players then
            table.insert(players, { UserId = subject.UserId, Name = subject.Name, DisplayName = subject.DisplayName,
                Activity = subject:GetAttribute("Activity"), FactionId = subject:GetAttribute("FactionId"),
                Busy = not self:_available(subject.UserId) or Invites.Get(self._invitations, subject.UserId) ~= nil })
        end
    end
    table.sort(players, function(a, b) return a.UserId < b.UserId end)
    local offset = Workspace:GetServerTimeNow() - os.clock()
    local function send(subject)
        if subject.Parent ~= Players then return end
        local invite = Invites.Get(self._invitations, subject.UserId)
        local own = invite and invite.HostId == subject.UserId
        local snapshot = { Players = players, ArenaBusy = self.Phase ~= "Lobby",
            InviteCooldownUntil = math.max(os.clock(), Invites.CooldownUntil(self._invitations, subject.UserId)) + offset,
            Incoming = not own and self:_invitationSnapshot(invite, offset) or nil,
            Outgoing = own and self:_invitationSnapshot(invite, offset) or nil }
        self.Remotes.Lobby:FireClient(subject, snapshot)
    end
    if player then send(player) else for subject in pairs(self._players) do send(subject) end end
end

function MatchService:Step(dt)
    if not self._started then return end
    local now = os.clock()
    if Invites.Expire(self._invitations, now) > 0 then self:SendLobby() end
    for player, record in pairs(self._players) do
        if player:GetAttribute("Activity") == "Lobby" then
            local model = record.Model
            local humanoid = model and model:FindFirstChildOfClass("Humanoid")
            if model and (not model.Parent or not humanoid or humanoid.Health <= 0 or player.Character ~= model) then
                record.Model, record.RespawnAt = nil, now + Config.Game.LobbyRespawnSeconds
            end
            if not record.Model and not record.Request and not self:_currentRequest(player, record, record.ActiveRequest)
                and (not record.RespawnAt or now >= record.RespawnAt) then self:_load(player, "Lobby") end
        end
    end
    if self.Phase == "Preparing" then
        self.TimeLeft = math.max(0, math.ceil(self._deadline - now))
        for id, member in pairs(self.Roster.Members) do
            if member.Eliminated or not self._players[id] or id.Parent ~= Players then
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
        elseif now >= self._deadline then self:_abortPreparation("Le chargement a pris trop de temps. Réessayez une invitation.") end
    elseif self.Phase == "Battle" then
        for id, member in pairs(self.Roster.Members) do
            if not self._players[id] or id.Parent ~= Players then self._forfeit = true end
            if not member.Eliminated then
                local state = self.Combat:GetState(member.Subject)
                if not state or state.Dead or not member.Model.Parent or state.Humanoid.Health <= 0 or not self._players[id] then
                    self:_eliminate(id)
                end
            end
        end
        local finished, winner = Rules.Resolve(self.Roster)
        if finished then
            local message = winner and (Config.Teams[winner].Name .. " remportent le combat !") or "Double élimination : égalité !"
            self:_finishBattle(winner, message, true)
        end
    elseif self.Phase == "Results" and now >= self._deadline then
        self:_returnLobby()
    end
    self._snapshotElapsed += dt
    self._lobbyElapsed += dt
    if self._snapshotElapsed >= 0.5 then self._snapshotElapsed = 0; self:SendState() end
    if self._lobbyElapsed >= 1 then self._lobbyElapsed = 0; self:SendLobby() end
end

return MatchService
