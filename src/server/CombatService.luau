local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("MedievalShared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Rules = require(Shared:WaitForChild("CombatRules"))

local CombatService = {}
CombatService.__index = CombatService

local function isPlayer(subject)
    return typeof(subject) == "Instance" and subject:IsA("Player")
end

local function finiteVector(vector)
    return typeof(vector) == "Vector3"
        and Rules.IsFinite(vector.X)
        and Rules.IsFinite(vector.Y)
        and Rules.IsFinite(vector.Z)
end

local function horizontalDirection(vector)
    if not finiteVector(vector) then
        return nil
    end
    -- A bound also avoids overflow when normalizing malicious remote input.
    if math.abs(vector.X) > 1000000 or math.abs(vector.Y) > 1000000 or math.abs(vector.Z) > 1000000 then
        return nil
    end
    local flat = Vector3.new(vector.X, 0, vector.Z)
    if flat.Magnitude < 0.001 then
        return nil
    end
    return flat.Unit
end

local function swordPart(model, name, size, color, material)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.Color = color
    part.Material = material
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Massless = true
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = model
    return part
end

local function weldTo(part, anchor, frame)
    part.CFrame = anchor.CFrame * frame
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = anchor
    weld.Part1 = part
    weld.Parent = part
    return part
end

local function selectedAppearance(subject)
    local swordId = Catalog.DefaultSword
    local factionId = Catalog.DefaultFaction
    if isPlayer(subject) then
        local equipped = subject:GetAttribute("EquippedSword")
        local faction = subject:GetAttribute("KingdomId") or subject:GetAttribute("FactionId")
        if type(equipped) == "string" and Catalog.Swords[equipped] then
            swordId = equipped
        end
        if type(faction) == "string" and Catalog.Factions[faction] then
            factionId = faction
        end
    end
    return swordId, factionId
end

local function clearAppearance(model)
    -- Motors live under a rig's hand, rather than under the cosmetic model.
    -- Remove them first so no joint retains a destroyed Part1 after a refresh.
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant.Name == "FerSwordGrip" and descendant:IsA("Motor6D") then
            descendant:Destroy()
        end
    end
    for _, child in ipairs(model:GetChildren()) do
        if child.Name == "FerSword" or child.Name == "FerFaction" then
            child:Destroy()
        end
    end
end

local function buildSword(model, swordId)
    local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
    if not hand or not hand:IsA("BasePart") then
        return nil
    end
    local sword = Instance.new("Model")
    sword.Name = "FerSword"
    sword:SetAttribute("SwordId", swordId)
    local cosmetic = Catalog.Swords[swordId]
    local bladeColor = Color3.fromRGB(table.unpack(cosmetic.Blade))
    local guardColor = Color3.fromRGB(table.unpack(cosmetic.Guard))
    local accentColor = Color3.fromRGB(table.unpack(cosmetic.Accent))
    local handle = swordPart(sword, "Grip", Vector3.new(0.23, 0.75, 0.23), accentColor, Enum.Material.Wood)
    local isR6 = hand.Name == "Right Arm"
    local gripFrame = CFrame.new(0, isR6 and -0.85 or -0.15, -0.35) * CFrame.Angles(-math.pi / 2, 0, 0)
    handle.CFrame = hand.CFrame * gripFrame
    for _, specification in ipairs({
        { "Pommel", Vector3.new(0.36, 0.2, 0.36), -0.42, guardColor, Enum.Material.Metal },
        { "Guard", Vector3.new(1.05, 0.16, 0.3), 0.45, guardColor, Enum.Material.Metal },
        { "Blade", Vector3.new(0.36, 2.8, 0.12), 1.9, bladeColor, Enum.Material.Metal },
        { "Tip", Vector3.new(0.24, 0.38, 0.12), 3.48, bladeColor:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Metal },
    }) do
        local part = swordPart(sword, specification[1], specification[2], specification[4], specification[5])
        weldTo(part, handle, CFrame.new(0, specification[3], 0))
    end
    -- Every blade, tip and grip has the same dimensions. These decorations
    -- remain inside the common silhouette and have no hitbox or combat stats.
    local jewel = swordPart(sword, "Emblem", Vector3.new(0.2, 0.3, 0.18), accentColor, Enum.Material.Metal)
    local jewelFrame = CFrame.new(0, 0.52, -0.16)
    if cosmetic.Style == "Cross" then
        local cross = swordPart(sword, "Cross", Vector3.new(0.42, 0.09, 0.08), accentColor, Enum.Material.Metal)
        weldTo(cross, handle, CFrame.new(0, 0.54, -0.23))
    elseif cosmetic.Style == "Fang" then
        jewelFrame = jewelFrame * CFrame.Angles(0, 0, math.pi / 4)
    elseif cosmetic.Style == "Wolf" then
        for _, side in ipairs({ -1, 1 }) do
            local fang = swordPart(sword, "Fang", Vector3.new(0.09, 0.3, 0.08), accentColor, Enum.Material.Metal)
            weldTo(fang, handle, CFrame.new(side * 0.28, 0.55, -0.18) * CFrame.Angles(0, 0, side * 0.35))
        end
    elseif cosmetic.Style == "Eye" then
        jewel.Shape = Enum.PartType.Ball
        jewel.Size = Vector3.new(0.26, 0.26, 0.18)
        jewel.Material = Enum.Material.Neon
    end
    weldTo(jewel, handle, jewelFrame)
    sword.PrimaryPart = handle
    sword.Parent = model
    local joint = Instance.new("Motor6D")
    joint.Name = "FerSwordGrip"
    joint.Part0 = hand
    joint.Part1 = handle
    joint.C0 = gripFrame
    joint.Parent = hand
    return sword, joint, gripFrame
end

local function buildFaction(model, factionId)
    local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
    if not torso or not torso:IsA("BasePart") then
        return nil
    end
    local faction = Catalog.Factions[factionId]
    local armor = Instance.new("Model")
    armor.Name = "FerFaction"
    armor:SetAttribute("FactionId", factionId)
    local color = Color3.fromRGB(table.unpack(faction.Color))
    local trim = Color3.fromRGB(table.unpack(faction.Trim))
    local width = torso.Size.X
    local height = torso.Size.Y
    local front = -torso.Size.Z / 2 - 0.08
    local function detail(name, size, frame, detailColor, material)
        local part = swordPart(armor, name, size, detailColor or trim, material or Enum.Material.Metal)
        weldTo(part, torso, frame)
        return part
    end
    detail("Cuirass", Vector3.new(width * 0.96, height * 0.86, 0.15), CFrame.new(0, 0, front), color)
    detail("Belt", Vector3.new(width, 0.14, 0.17), CFrame.new(0, -height * 0.32, front - 0.06))
    if factionId == "Redcliff" then
        detail("StandardVertical", Vector3.new(0.15, height * 0.65, 0.08), CFrame.new(0, 0.04, front - 0.12))
        detail("StandardHorizontal", Vector3.new(width * 0.55, 0.15, 0.08), CFrame.new(0, height * 0.12, front - 0.12))
    elseif factionId == "Korblox" then
        for _, side in ipairs({ -1, 1 }) do
            detail("IceStripe", Vector3.new(0.13, height * 0.6, 0.08), CFrame.new(side * width * 0.2, 0.02, front - 0.12) * CFrame.Angles(0, 0, side * 0.5))
        end
        detail("Crystal", Vector3.new(0.27, 0.27, 0.12), CFrame.new(0, height * 0.15, front - 0.14) * CFrame.Angles(0, 0, math.pi / 4), trim, Enum.Material.Neon)
    elseif factionId == "Greywolf" then
        detail("WolfBadge", Vector3.new(width * 0.28, height * 0.3, 0.1), CFrame.new(0, height * 0.12, front - 0.12))
        for _, side in ipairs({ -1, 1 }) do
            detail("WolfFang", Vector3.new(0.12, height * 0.23, 0.1), CFrame.new(side * width * 0.12, -height * 0.1, front - 0.12) * CFrame.Angles(0, 0, side * 0.2))
        end
    elseif factionId == "Overseer" then
        local eye = detail("Eye", Vector3.new(width * 0.45, height * 0.25, 0.13), CFrame.new(0, height * 0.12, front - 0.12), trim, Enum.Material.Neon)
        eye.Shape = Enum.PartType.Ball
        local pupil = detail("Pupil", Vector3.new(0.15, height * 0.19, 0.1), CFrame.new(0, height * 0.12, front - 0.2), color)
        pupil.Shape = Enum.PartType.Ball
    end
    armor.Parent = model
    return armor
end

local function buildAppearance(subject, model)
    clearAppearance(model)
    local swordId, factionId = selectedAppearance(subject)
    local sword, joint, grip = buildSword(model, swordId)
    local faction = buildFaction(model, factionId)
    return sword, joint, grip, faction
end

function CombatService.new(remotes)
    return setmetatable({
        _remotes = remotes,
        _states = {},
        _enabled = false,
        OnDeath = nil,
    }, CombatService)
end

function CombatService:DressCharacter(player, model)
    if typeof(model) ~= "Instance" or not model:IsA("Model") then
        return nil, "InvalidCharacter"
    end
    local state = self._states[player]
    if state and state.Model == model then
        return nil, "RegisteredCombatant"
    end
    -- Lobby equipment is visual only. Do not register the character, write
    -- attributes for resources, heal it or change its movement properties.
    return buildAppearance(player, model)
end

function CombatService:_effect(kind, payload)
    self._remotes.Effects:FireAllClients(kind, payload)
end

function CombatService:_sync(state, now)
    if not state.Model.Parent then
        return
    end
    state.Model:SetAttribute("Combatant", true)
    state.Model:SetAttribute("TeamId", state.TeamId)
    state.Model:SetAttribute("Stamina", math.floor(state.Stamina * 10 + 0.5) / 10)
    state.Model:SetAttribute("MaxStamina", Config.Combat.MaxStamina)
    state.Model:SetAttribute("Sprinting", state.Sprinting)
    state.Model:SetAttribute("SpawnProtected", not state.Dead and now < state.SpawnProtectedUntil)
    state.Model:SetAttribute("PotionReadyAt", state.PotionReadyAt or 0)
    state.Model:SetAttribute("PotionCooldown", Config.PotionCooldown)
    local serverNow = Workspace:GetServerTimeNow()
    state.Model:SetAttribute("AttackReadyAt", serverNow + math.max(0, state.LastAttackAt + Config.Combat.AttackCooldown - now))
    local lastCombat = math.max(state.LastDamagedAt, state.LastAttackAt, state.LastWorkAt)
    state.Model:SetAttribute("HealthRegenReadyAt", serverNow + math.max(0, lastCombat + Config.Player.HealthRegenDelay - now))
    for _, size in ipairs(Config.PotionOrder) do
        state.Model:SetAttribute("Potions" .. size, state.Potions[size])
    end
end

function CombatService:_markDead(state)
    if state.Dead then
        return
    end
    state.Dead = true
    state.Sprinting = false
    state.PendingAttack = nil
    self:_sync(state, os.clock())
    local killer = state.LastAttacker
    if killer and os.clock() - (state.LastHitAt or -math.huge) > 10 then
        killer = nil
    end
    self:_effect("Death", { Actor = state.Model, Position = state.Root.Position, TeamId = state.TeamId })
    -- Match callbacks may schedule respawns or end the round. They run outside
    -- the damage iteration, which leaves this service's table stable.
    task.defer(function()
        if self.OnDeath then
            local ok, problem = pcall(self.OnDeath, state, killer)
            if not ok then
                warn("Combat death callback failed: " .. tostring(problem))
            end
        end
    end)
end

function CombatService:Register(subject, model, teamId)
    self:Unregister(subject)
    if typeof(model) ~= "Instance" or not model:IsA("Model") or Config.Teams[teamId] == nil then
        return nil
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
        return nil
    end
    local now = os.clock()
    local state = Rules.NewState(Config, now)
    state.Subject = subject
    state.Model = model
    state.Humanoid = humanoid
    state.Root = root
    state.TeamId = teamId
    state.RateTokens = Config.Combat.MaxActionRate
    state.RateUpdatedAt = now
    state.NextAttributeAt = 0
    state.PotionReadyAt = 0
    state.Sword, state.SwordJoint, state.SwordGrip, state.Faction = buildAppearance(subject, model)
    humanoid.MaxHealth = Config.Player.MaxHealth
    humanoid.Health = Config.Player.MaxHealth
    humanoid.WalkSpeed = Config.Player.WalkSpeed
    state.LastObservedHealth = humanoid.Health
    state.DeathConnection = humanoid.Died:Connect(function()
        self:_markDead(state)
    end)
    local previousHealth = humanoid.Health
    state.DamageConnection = humanoid.HealthChanged:Connect(function(health)
        if health < previousHealth then state.LastDamagedAt = os.clock() end
        previousHealth = health
    end)
    self._states[subject] = state
    if isPlayer(subject) then
        subject:SetAttribute("TeamId", teamId)
    end
    self:_sync(state, now)
    return state
end

function CombatService:Unregister(subject)
    local state = self._states[subject]
    if not state then
        return
    end
    self._states[subject] = nil
    if state.DeathConnection then
        state.DeathConnection:Disconnect()
    end
    if state.DamageConnection then state.DamageConnection:Disconnect() end
    if state.SwordTween then
        state.SwordTween:Cancel()
        state.SwordTween = nil
    end
    if state.SwordJoint then
        state.SwordJoint:Destroy()
    end
    if state.Sword then
        state.Sword:Destroy()
    end
    if state.Faction then
        state.Faction:Destroy()
    end
    if state.Model.Parent then
        state.Model:SetAttribute("Combatant", false)
        state.Model:SetAttribute("Sprinting", false)
    end
end

function CombatService:GetState(subject)
    return self._states[subject]
end

function CombatService:GetStates()
    return self._states
end

function CombatService:SetEnabled(enabled)
    self._enabled = enabled == true
    if not self._enabled then
        for _, state in pairs(self._states) do
            state.PendingAttack = nil
            state.Sprinting = false
            if state.Humanoid.Parent and not state.Dead then
                state.Humanoid.WalkSpeed = Config.Player.WalkSpeed
            end
            self:_sync(state, os.clock())
        end
    end
end

function CombatService:_swing(state, side)
    if not state.SwordJoint or not state.SwordJoint.Parent then
        return
    end
    if state.SwordTween then
        state.SwordTween:Cancel()
    end
    -- The same horizontal path and its mirror are the only attacks. Rotation
    -- around the grip's local Z axis sweeps the blade left/right on R6 and R15.
    -- It holds at the finish, which is the next attack's starting position.
    -- Only this Motor6D moves: character locomotion stays entirely available.
    state.SwordJoint.C0 = state.SwordGrip * CFrame.Angles(0, 0, 1.15 * side)
    local finish = state.SwordGrip * CFrame.Angles(0, 0, -1.15 * side)
    state.SwordTween = TweenService:Create(state.SwordJoint, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { C0 = finish })
    state.SwordTween:Play()
end

function CombatService:Act(subject, action, payload)
    local state = self._states[subject]
    if not state then
        return false, "UnknownCombatant"
    end
    local now = os.clock()
    state.RateTokens = math.min(Config.Combat.MaxActionRate, state.RateTokens + (now - state.RateUpdatedAt) * Config.Combat.MaxActionRate)
    state.RateUpdatedAt = now
    if state.RateTokens < 1 then
        return false, "RateLimited"
    end
    state.RateTokens = state.RateTokens - 1
    if type(action) ~= "string" or type(payload) ~= "table" then
        return false, "Malformed"
    end
    if state.Dead or state.Humanoid.Health <= 0 or not state.Model.Parent or not state.Root.Parent then
        return false, "Dead"
    end
    if action == "Sprint" and payload.Active == false then
        state.Sprinting = false
        state.Humanoid.WalkSpeed = Config.Player.WalkSpeed
        self:_sync(state, now)
        return true
    end
    if not self._enabled then
        return false, "Intermission"
    end
    if action == "Attack" then
        local direction = horizontalDirection(payload.Aim)
        if not direction then
            return false, "InvalidAim"
        end
        local allowed, reason = Rules.ConsumeAttack(state, Config, now)
        if not allowed then
            return false, reason
        end
        state.PendingAttack = { At = now + Config.Combat.AttackWindup, Direction = direction }
        self:_swing(state, state.SwingSide)
        self:_effect("Swing", { Actor = state.Model, Position = state.Root.Position, Direction = direction, TeamId = state.TeamId, Side = state.SwingSide })
    elseif action == "Sprint" then
        if type(payload.Active) ~= "boolean" then
            return false, "Malformed"
        end
        if state.Stamina <= 0 then
            return false, "Stamina"
        end
        state.Sprinting = payload.Active
        state.Humanoid.WalkSpeed = state.Sprinting and Config.Player.SprintSpeed or Config.Player.WalkSpeed
    elseif action == "Potion" then
        local consumed, result = Rules.ConsumePotion(state, Config, payload.Size, state.Humanoid.Health, state.Humanoid.MaxHealth, now)
        if not consumed then
            return false, result
        end
        state.Humanoid.Health = result
        state.PotionReadyAt = Workspace:GetServerTimeNow() + Config.PotionCooldown
        self:_effect("Potion", { Actor = state.Model, Position = state.Root.Position, Size = payload.Size, TeamId = state.TeamId })
    else
        return false, "UnknownAction"
    end
    self:_sync(state, now)
    return true
end

function CombatService:HandleAction(player, action, payload)
    return self:Act(player, action, payload)
end

function CombatService:SpendEffort(subject, cost)
    local state = self._states[subject]
    if not self._enabled or not state or state.Dead or state.Humanoid.Health <= 0
        or not state.Model.Parent or not state.Root.Parent then
        return false, "Dead"
    end
    if state.PendingAttack then return false, "Cooldown" end
    local now = os.clock()
    local accepted, reason = Rules.ConsumeEffort(state, Config, now, cost)
    if not accepted then return false, reason end
    self:_swing(state, state.SwingSide)
    self:_effect("Swing", {
        Actor = state.Model, Position = state.Root.Position,
        Direction = state.Root.CFrame.LookVector, TeamId = state.TeamId, Side = state.SwingSide,
    })
    self:_sync(state, now)
    return true
end

function CombatService:_resolveAttack(attacker, direction, now)
    if not self._enabled or attacker.Dead or attacker.Humanoid.Health <= 0 or not attacker.Root.Parent then
        return
    end
    local origin = attacker.Root.Position
    if not finiteVector(origin) then
        return
    end
    local candidates = {}
    for _, target in pairs(self._states) do
        if Rules.CanDamage(attacker, target, now) and target.Model.Parent and target.Root.Parent and target.Humanoid.Health > 0 then
            local offset = target.Root.Position - origin
            if finiteVector(offset) then
                local flat = Vector3.new(offset.X, 0, offset.Z)
                local dot = flat.Magnitude > 0.001 and direction:Dot(flat.Unit) or 1
                local distance = offset.Magnitude
                if Rules.InAttackArc(distance, dot, Config) then
                    candidates[#candidates + 1] = { State = target, Distance = distance }
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        return a.Distance < b.Distance
    end)
    local rayParameters = RaycastParams.new()
    rayParameters.FilterType = Enum.RaycastFilterType.Exclude
    rayParameters.FilterDescendantsInstances = { attacker.Model }
    local eye = origin + Vector3.new(0, 1, 0)
    for _, candidate in ipairs(candidates) do
        local target = candidate.State
        local ray = Workspace:Raycast(eye, target.Root.Position + Vector3.new(0, 1, 0) - eye, rayParameters)
        if not ray or ray.Instance:IsDescendantOf(target.Model) then
            local previousAttacker = target.LastAttacker
            local previousHitAt = target.LastHitAt
            local before = target.Humanoid.Health
            target.LastAttacker = attacker
            target.LastHitAt = now
            target.Humanoid:TakeDamage(Config.Combat.AttackDamage)
            local damage = math.max(0, before - target.Humanoid.Health)
            if damage > 0 then
                -- Record this synchronously; Roblox may defer HealthChanged.
                target.LastDamagedAt = now
                target.LastObservedHealth = target.Humanoid.Health
                self:_effect("Hit", { Actor = attacker.Model, Target = target.Model, Position = target.Root.Position, Damage = damage, TeamId = attacker.TeamId })
                if target.Humanoid.Health <= 0 then
                    self:_markDead(target)
                end
            else
                target.LastAttacker = previousAttacker
                target.LastHitAt = previousHitAt
            end
            -- One accepted swing can hurt only one enemy.
            return
        end
    end
end

function CombatService:Step(dt)
    if not Rules.IsFinite(dt) or dt <= 0 then
        return
    end
    local now = os.clock()
    for _, state in pairs(self._states) do
        if state.Model.Parent and state.Root.Parent and state.Humanoid.Parent then
            if state.Humanoid.Health <= 0 then
                self:_markDead(state)
            elseif not state.Dead then
                if state.Humanoid.Health < state.LastObservedHealth then
                    state.LastDamagedAt = now
                end
                state.LastObservedHealth = state.Humanoid.Health
                if state.PendingAttack and now >= state.PendingAttack.At then
                    local attack = state.PendingAttack
                    state.PendingAttack = nil
                    self:_resolveAttack(state, attack.Direction, now)
                end
                local velocity = state.Root.AssemblyLinearVelocity
                local moving = finiteVector(velocity) and Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 0.75
                local wasSprinting = state.Sprinting
                Rules.TickStamina(state, Config, dt, now, moving)
                local restored = Rules.RecoverHealth(state, Config, dt, now, state.Humanoid.Health, state.Humanoid.MaxHealth)
                if restored > state.Humanoid.Health then state.Humanoid.Health = restored end
                state.LastObservedHealth = state.Humanoid.Health
                if wasSprinting ~= state.Sprinting then
                    state.Humanoid.WalkSpeed = state.Sprinting and Config.Player.SprintSpeed or Config.Player.WalkSpeed
                end
                if now >= state.NextAttributeAt then
                    self:_sync(state, now)
                    state.NextAttributeAt = now + 0.1
                end
            end
        end
    end
end

return CombatService
