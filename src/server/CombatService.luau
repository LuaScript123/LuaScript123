local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("MedievalShared")
local Config = require(Shared:WaitForChild("Config"))
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

local function buildSword(model)
    local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
    if not hand or not hand:IsA("BasePart") then
        return nil
    end
    local sword = Instance.new("Model")
    sword.Name = "FerSword"
    local handle = swordPart(sword, "Grip", Vector3.new(0.23, 0.75, 0.23), Color3.fromRGB(81, 51, 33), Enum.Material.Wood)
    local isR6 = hand.Name == "Right Arm"
    local gripFrame = CFrame.new(0, isR6 and -0.85 or -0.15, -0.35) * CFrame.Angles(-math.pi / 2, 0, 0)
    handle.CFrame = hand.CFrame * gripFrame
    for _, specification in ipairs({
        { "Pommel", Vector3.new(0.36, 0.2, 0.36), -0.42, Color3.fromRGB(209, 171, 89), Enum.Material.Metal },
        { "Guard", Vector3.new(1.05, 0.16, 0.3), 0.45, Color3.fromRGB(209, 171, 89), Enum.Material.Metal },
        { "Blade", Vector3.new(0.36, 2.8, 0.12), 1.9, Color3.fromRGB(201, 217, 229), Enum.Material.Metal },
        { "Tip", Vector3.new(0.24, 0.38, 0.12), 3.48, Color3.fromRGB(228, 237, 242), Enum.Material.Metal },
    }) do
        local part = swordPart(sword, specification[1], specification[2], specification[4], specification[5])
        part.CFrame = handle.CFrame * CFrame.new(0, specification[3], 0)
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = handle
        weld.Part1 = part
        weld.Parent = part
    end
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

function CombatService.new(remotes)
    return setmetatable({
        _remotes = remotes,
        _states = {},
        _enabled = false,
        OnDeath = nil,
    }, CombatService)
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
    state.Sword, state.SwordJoint, state.SwordGrip = buildSword(model)
    humanoid.MaxHealth = Config.Player.MaxHealth
    humanoid.Health = Config.Player.MaxHealth
    humanoid.WalkSpeed = Config.Player.WalkSpeed
    state.DeathConnection = humanoid.Died:Connect(function()
        self:_markDead(state)
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
    if state.SwordTween then
        state.SwordTween:Cancel()
    end
    if state.SwordJoint then
        state.SwordJoint:Destroy()
    end
    if state.Sword then
        state.Sword:Destroy()
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

function CombatService:_swing(state)
    if not state.SwordJoint or not state.SwordJoint.Parent then
        return
    end
    if state.SwordTween then
        state.SwordTween:Cancel()
    end
    -- Animate only the held sword. Neither locomotion nor the rig's animation
    -- controller is locked during attacks.
    state.SwordJoint.C0 = state.SwordGrip * CFrame.Angles(0, -1.15, 0.25)
    state.SwordTween = TweenService:Create(state.SwordJoint, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = state.SwordGrip })
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
        self:_swing(state)
        self:_effect("Swing", { Actor = state.Model, Position = state.Root.Position, Direction = direction, TeamId = state.TeamId })
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
                if state.PendingAttack and now >= state.PendingAttack.At then
                    local attack = state.PendingAttack
                    state.PendingAttack = nil
                    self:_resolveAttack(state, attack.Direction, now)
                end
                local velocity = state.Root.AssemblyLinearVelocity
                local moving = finiteVector(velocity) and Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 0.75
                local wasSprinting = state.Sprinting
                Rules.TickStamina(state, Config, dt, now, moving)
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
