-- Local R6 guards fill the LOCKED preparation roster. Step never creates a bot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage:WaitForChild("MedievalShared"):WaitForChild("Config"))

local BotService = {}
BotService.__index = BotService

local function bodyPart(model, name, size, position, color, collidable)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = CFrame.new(position)
    part.Color = color
    part.Material = Enum.Material.SmoothPlastic
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.CanCollide = collidable == true
    part.Massless = name ~= "HumanoidRootPart"
    part.Parent = model
    return part
end

local function joint(parent, name, part0, part1, offset0, offset1)
    local motor = Instance.new("Motor6D")
    motor.Name = name
    motor.Part0 = part0
    motor.Part1 = part1
    motor.C0 = CFrame.new(offset0)
    motor.C1 = CFrame.new(offset1)
    motor.Parent = parent
    return motor
end

local function createRig(teamId)
    local definition = Config.Teams[teamId]
    local color = Color3.fromRGB(table.unpack(definition.Color))
    local steel = Color3.fromRGB(95, 105, 113)
    local skin = Color3.fromRGB(218, 179, 139)
    local model = Instance.new("Model")
    model.Name = "Garde_" .. teamId
    model:SetAttribute("IsBot", true)
    model:SetAttribute("TeamId", teamId)

    local root = bodyPart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero, steel, false)
    root.Transparency = 1
    local torso = bodyPart(model, "Torso", Vector3.new(2, 2, 1), Vector3.zero, color, true)
    local head = bodyPart(model, "Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0), skin, false)
    local leftArm = bodyPart(model, "Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0), steel, false)
    local rightArm = bodyPart(model, "Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0), steel, false)
    local leftLeg = bodyPart(model, "Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), steel, false)
    local rightLeg = bodyPart(model, "Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), steel, false)
    joint(root, "RootJoint", root, torso, Vector3.zero, Vector3.zero)
    joint(torso, "Neck", torso, head, Vector3.new(0, 1, 0), Vector3.new(0, -0.5, 0))
    joint(torso, "Left Shoulder", torso, leftArm, Vector3.new(-1.5, 0.5, 0), Vector3.new(0, 0.5, 0))
    joint(torso, "Right Shoulder", torso, rightArm, Vector3.new(1.5, 0.5, 0), Vector3.new(0, 0.5, 0))
    joint(torso, "Left Hip", torso, leftLeg, Vector3.new(-0.5, -1, 0), Vector3.new(0, 1, 0))
    joint(torso, "Right Hip", torso, rightLeg, Vector3.new(0.5, -1, 0), Vector3.new(0, 1, 0))
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.Head
    mesh.Scale = Vector3.new(1.1, 1.1, 1.1)
    mesh.Parent = head
    local helmet = bodyPart(model, "Helmet", Vector3.new(2.15, 0.5, 1.15), Vector3.new(0, 1.95, 0), steel, false)
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = head
    weld.Part1 = helmet
    weld.Parent = helmet

    local humanoid = Instance.new("Humanoid")
    humanoid.Name = "Humanoid"
    humanoid.DisplayName = "Garde " .. definition.Name
    humanoid.RigType = Enum.HumanoidRigType.R6
    humanoid.MaxHealth = Config.Player.MaxHealth
    humanoid.Health = Config.Player.MaxHealth
    humanoid.WalkSpeed = Config.Player.WalkSpeed
    humanoid.HipHeight = 0
    humanoid.BreakJointsOnDeath = false
    humanoid.NameDisplayDistance = 45
    humanoid.HealthDisplayDistance = 45
    humanoid.Parent = model
    model.PrimaryPart = root
    return model, humanoid, root
end

function BotService.new(map, combat, match)
    local self = setmetatable({}, BotService)
    self.Map = map
    self.Combat = combat
    self.Match = match
    self._round = match.Round
    self._slots = {}
    self._destroyed = false
    match:SetBotService(self)
    return self
end

function BotService:_remove(slot)
    if slot.Model then
        self.Combat:Unregister(slot.Model)
        slot.Model:Destroy()
    end
    slot.Model = nil
    slot.Humanoid = nil
    slot.Root = nil
    slot.Target = nil
    slot.Dead = false
end

function BotService:Cleanup()
    for _, slot in pairs(self._slots) do
        self:_remove(slot)
    end
    self._slots = {}
end

function BotService:Prepare(roster, round, epoch)
    if self._destroyed then error("Bot service has been destroyed") end
    self:Cleanup()
    self._round, self._epoch = round, epoch
    local index = 0
    for id, member in pairs(roster.Members) do
        if member.IsBot then
            index += 1
            local slot = { Id = id, TeamId = member.TeamId, Side = index % 2 == 0 and -1 or 1 }
            self._slots[id] = slot
            self:_spawn(slot, os.clock())
        end
    end
end

function BotService:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    self:Cleanup()
end

function BotService:_spawn(slot, now)
    local model, humanoid, root = createRig(slot.TeamId)
    model:SetAttribute("MatchRound", self.Match.Round)
    model.Name = "Garde_" .. slot.Id
    model:PivotTo(self.Match:GetSpawn(slot.TeamId))
    model.Parent = Workspace
    slot.Model = model
    slot.Humanoid = humanoid
    slot.Root = root
    root:SetNetworkOwner(nil)
    slot.Dead = false
    slot.NextThink = 0
    slot.NextAttack = now + 1
    slot.NextPotion = now + 1
    slot.NextJump = now + 1
    slot.LastPosition = root.Position
    slot.LastProgress = now
    slot.RaycastParams = RaycastParams.new()
    slot.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
    slot.RaycastParams.FilterDescendantsInstances = { model }
    slot.RaycastParams.RespectCanCollide = true
    if not self.Match:RegisterBot(slot.Id, model, slot.TeamId, self._round, self._epoch) then
        self:_remove(slot)
        error("Bot registration rejected for a stale or invalid preparation")
    end
end

function BotService:_target(slot)
    local nearest = nil
    local bestDistance = math.huge
    for _, state in pairs(self.Combat:GetStates()) do
        if state.TeamId ~= slot.TeamId and not state.Dead and state.Humanoid.Health > 0
            and state.Root.Parent and state.Model.Parent then
            local distance = (state.Root.Position - slot.Root.Position).Magnitude
            if distance < bestDistance then
                nearest = state
                bestDistance = distance
            end
        end
    end
    return nearest
end

function BotService:_think(slot, now)
    if self.Match.Phase ~= "Battle" then
        slot.Humanoid:MoveTo(slot.Root.Position)
        self.Combat:Act(slot.Model, "Sprint", { Active = false })
        return
    end
    local ownState = self.Combat:GetState(slot.Model)
    if not ownState or ownState.Dead then
        return
    end
    local target = self:_target(slot)
    slot.Target = target
    if not target then
        slot.Humanoid:MoveTo(slot.Root.Position)
        self.Combat:Act(slot.Model, "Sprint", { Active = false })
        return
    end

    if now >= slot.NextPotion then
        local missing = slot.Humanoid.MaxHealth - slot.Humanoid.Health
        for _, size in ipairs({ "Large", "Medium", "Small" }) do
            if missing >= Config.Potions[size].Heal - 5
                and (slot.Model:GetAttribute("Potions" .. size) or 0) > 0 then
                self.Combat:Act(slot.Model, "Potion", { Size = size })
                slot.NextPotion = now + Config.PotionCooldown + 0.1
                break
            end
        end
    end

    local offset = target.Root.Position - slot.Root.Position
    local planar = Vector3.new(offset.X, 0, offset.Z)
    local distance = planar.Magnitude
    if distance < 0.05 then
        return
    end
    local direction = planar.Unit
    self.Combat:Act(slot.Model, "Sprint", { Active = distance > 24 and ownState.Stamina > 30 })

    if (slot.Root.Position - slot.LastPosition).Magnitude >= 2 then
        slot.LastPosition = slot.Root.Position
        slot.LastProgress = now
    end
    local obstruction = Workspace:Raycast(slot.Root.Position + Vector3.new(0, 0.5, 0), direction * math.min(distance, 7), slot.RaycastParams)
    local blocked = obstruction and not obstruction.Instance:IsDescendantOf(target.Model)
    local goal = target.Root.Position - direction * 4
    if blocked or now - slot.LastProgress > 1.5 then
        if now - slot.LastProgress > 1.5 then
            slot.Side *= -1
            slot.LastProgress = now
        end
        local sideways = Vector3.new(-direction.Z, 0, direction.X) * slot.Side
        if Workspace:Raycast(slot.Root.Position, sideways * 7, slot.RaycastParams) then
            slot.Side *= -1
            sideways *= -1
        end
        goal = slot.Root.Position + sideways * 10 + direction * 3
        if now >= slot.NextJump then
            slot.Humanoid.Jump = true
            slot.NextJump = now + 1.2
        end
    end
    if distance > 5 or blocked then
        slot.Humanoid:MoveTo(goal)
    else
        slot.Humanoid:MoveTo(slot.Root.Position)
        slot.Root.CFrame = CFrame.lookAt(slot.Root.Position, slot.Root.Position + direction)
    end
    if distance <= Config.Combat.AttackRange - 0.5 and math.abs(offset.Y) < 5 and not blocked and now >= slot.NextAttack then
        self.Combat:Act(slot.Model, "Attack", { Aim = direction })
        slot.NextAttack = now + Config.Combat.AttackCooldown + 0.14
    end
end

function BotService:Step(_dt)
    if self._destroyed then
        return
    end
    local now = os.clock()
    for _, slot in pairs(self._slots) do
        -- Death is irreversible for this slot; no stock refill, replacement,
        -- despawn-on-human-arrival, or delayed respawn can occur in Battle.
        if slot.Model and (not slot.Model.Parent or slot.Humanoid.Health <= 0) then slot.Dead = true end
        if slot.Model and not slot.Dead and now >= slot.NextThink then
            slot.NextThink = now + 0.2
            if self._round == self.Match.Round then self:_think(slot, now) end
        end
    end
end

return BotService
