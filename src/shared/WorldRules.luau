-- Pure rules for the original kingdom world. All timing and tuning come from
-- the authoritative server; these values are not verified reference-game data.
local Rules = {}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function quantity(value)
    return finite(value) and value >= 0 and value % 1 == 0
end

local function timestamp(value)
    return finite(value) and value >= 0
end

local function knownKingdom(id, config)
    return type(id) == "string" and config.Kingdoms[id] ~= nil
end

local function worldPlayer(player)
    return type(player) == "table" and quantity(player.Wood) and quantity(player.Ore)
        and (finite(player.LastHarvestAt) or player.LastHarvestAt == -math.huge)
        and (finite(player.LastKingdomAt) or player.LastKingdomAt == -math.huge)
end

local function nodeDefinition(kind, config)
    if kind ~= "Tree" and kind ~= "Mine" then return nil end
    local definition = config.World[kind]
    if type(definition) ~= "table" or not quantity(definition.Hits) or definition.Hits == 0
        or not quantity(definition.Yield) or not finite(definition.RespawnSeconds)
        or definition.RespawnSeconds < 0 then return nil end
    return definition
end

local function validNode(node, config)
    if type(node) ~= "table" then return nil end
    local definition = nodeDefinition(node.Kind, config)
    if not definition or not quantity(node.HitsRemaining) or node.HitsRemaining > definition.Hits
        or not timestamp(node.RespawnAt) then return nil end
    return definition
end

function Rules.NewPlayer()
    return {
        KingdomId = nil, Wood = 0, Ore = 0,
        LastHarvestAt = -math.huge, LastKingdomAt = -math.huge,
    }
end

function Rules.ChooseKingdom(player, kingdomId, config, now)
    if not worldPlayer(player) then return false, "InvalidPlayer" end
    if not timestamp(now) then return false, "InvalidTime" end
    if not knownKingdom(kingdomId, config) then return false, "UnknownKingdom" end
    if player.KingdomId == kingdomId then return false, "AlreadyKingdom" end
    if now - player.LastKingdomAt < config.World.KingdomChangeCooldown then
        return false, "KingdomCooldown"
    end
    player.KingdomId, player.LastKingdomAt = kingdomId, now
    return true
end

function Rules.NewNode(kind, config)
    local definition = nodeDefinition(kind, config)
    if not definition then return nil, "UnknownNodeKind" end
    return { Kind = kind, HitsRemaining = definition.Hits, RespawnAt = 0 }
end

function Rules.CanHarvest(player, node, config, now)
    if not worldPlayer(player) then return false, "InvalidPlayer" end
    if not timestamp(now) then return false, "InvalidTime" end
    if not knownKingdom(player.KingdomId, config) then return false, "ChooseKingdom" end
    local definition = validNode(node, config)
    if not definition then return false, "InvalidNode" end
    if node.HitsRemaining == 0 then return false, "Depleted" end
    if now - player.LastHarvestAt < config.World.HarvestCooldown then
        return false, "HarvestCooldown"
    end
    local resource = node.Kind == "Tree" and "Wood" or "Ore"
    -- Validate both final mutations before accepting the strike. This also
    -- keeps malformed server state from spending a hit and losing its reward.
    if not quantity(player[resource] + definition.Yield)
        or not timestamp(now + definition.RespawnSeconds) then return false, "InvalidPlayer" end
    return true
end

function Rules.Harvest(player, node, config, now)
    local accepted, reason = Rules.CanHarvest(player, node, config, now)
    if not accepted then return false, reason end
    local definition = nodeDefinition(node.Kind, config)
    local depleted = node.HitsRemaining == 1
    local resource = node.Kind == "Tree" and "Wood" or "Ore"
    local amount = depleted and definition.Yield or 0
    -- No yield occurs between the hit, cooldown and reward mutations.
    node.HitsRemaining -= 1
    player.LastHarvestAt = now
    if depleted then
        node.RespawnAt = now + definition.RespawnSeconds
        player[resource] += amount
    end
    return true, { Depleted = depleted, Resource = resource, Amount = amount }
end

function Rules.RefreshNode(node, config, now)
    if not timestamp(now) then return false end
    local definition = validNode(node, config)
    if not definition or node.HitsRemaining ~= 0 or now < node.RespawnAt then return false end
    node.HitsRemaining, node.RespawnAt = definition.Hits, 0
    return true
end

function Rules.NewOutpost()
    return { Owner = nil, Claimant = nil, Progress = 0, Contested = false, Built = false }
end

local function validOutpost(point, config)
    return type(point) == "table" and finite(point.Progress) and point.Progress >= 0 and point.Progress <= 1
        and type(point.Contested) == "boolean" and type(point.Built) == "boolean"
        and (point.Owner == nil or knownKingdom(point.Owner, config))
        and (point.Claimant == nil or knownKingdom(point.Claimant, config))
end

function Rules.StepCapture(point, kingdomCounts, config, dt)
    if not finite(dt) or dt <= 0 or not validOutpost(point, config)
        or type(kingdomCounts) ~= "table" or not finite(config.World.CaptureSeconds)
        or config.World.CaptureSeconds <= 0 then return false end
    local present, onlyKingdom = 0, nil
    for kingdomId, count in pairs(kingdomCounts) do
        if knownKingdom(kingdomId, config) and quantity(count) and count > 0 then
            present += 1
            onlyKingdom = kingdomId
        end
    end
    local owner, claimant, progress = point.Owner, point.Claimant, point.Progress
    local contested, built = point.Contested, point.Built
    point.Contested = present > 1
    if present < 2 then
        local advance = dt / config.World.CaptureSeconds
        if present == 1 and onlyKingdom ~= point.Owner then
            if point.Claimant ~= onlyKingdom then
                point.Claimant, point.Progress = onlyKingdom, 0
            end
            point.Progress = math.min(1, point.Progress + advance)
            if point.Progress >= 1 then
                point.Owner, point.Claimant, point.Progress = onlyKingdom, nil, 0
                point.Built = false
            end
        else
            point.Progress = math.max(0, point.Progress - advance)
            if point.Progress == 0 then point.Claimant = nil end
        end
    end
    return owner ~= point.Owner or claimant ~= point.Claimant or progress ~= point.Progress
        or contested ~= point.Contested or built ~= point.Built
end

function Rules.BuildOutpost(player, point, config)
    if not worldPlayer(player) then return false, "InvalidPlayer" end
    if not validOutpost(point, config) then return false, "InvalidOutpost" end
    if not knownKingdom(player.KingdomId, config) or point.Owner ~= player.KingdomId then
        return false, "NotOwner"
    end
    if point.Built then return false, "AlreadyBuilt" end
    if point.Contested then return false, "Contested" end
    local woodCost, oreCost = config.World.OutpostWoodCost, config.World.OutpostOreCost
    if not quantity(woodCost) or not quantity(oreCost) then return false, "InvalidCost" end
    if player.Wood < woodCost then return false, "InsufficientWood" end
    if player.Ore < oreCost then return false, "InsufficientOre" end
    player.Wood, player.Ore = player.Wood - woodCost, player.Ore - oreCost
    point.Built = true
    return true
end

return Rules
