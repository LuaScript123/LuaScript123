-- Exercises the same pure world rules called by the authoritative service.
-- Config values are this project's provisional tuning, not wiki measurements.
local Rules = require("../src/shared/WorldRules")
local Config = require("../src/shared/Config")
local passed = 0

local function equal(actual, expected, context)
    assert(actual == expected, (context or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " ~= " .. tostring(expected))
end
local function test(name, callback)
    callback()
    passed += 1
    print("PASS " .. name)
end
local function citizen(kingdom)
    local player = Rules.NewPlayer()
    assert(Rules.ChooseKingdom(player, kingdom or "Redcliff", Config, 0))
    return player
end
local function ownerPoint(kingdom)
    local point = Rules.NewOutpost()
    point.Owner = kingdom or "Redcliff"
    return point
end
local function deplete(player, node, start)
    local result
    for hit = 1, node.HitsRemaining do
        local accepted
        accepted, result = Rules.Harvest(player, node, Config, start + (hit - 1) * Config.World.HarvestCooldown)
        assert(accepted)
    end
    return result
end

test("new world players have independent empty session inventories and no kingdom", function()
    local first, second = Rules.NewPlayer(), Rules.NewPlayer()
    equal(first.KingdomId, nil)
    equal(first.Wood, 0)
    equal(first.Ore, 0)
    first.Wood = 20
    equal(second.Wood, 0)
    assert(Rules.ChooseKingdom(second, "Redcliff", Config, 0), "first choice must be immediately available")
end)

test("all configured kingdoms are selectable without spending resources", function()
    for _, kingdomId in ipairs(Config.KingdomOrder) do
        local player = Rules.NewPlayer()
        player.Wood, player.Ore = 30, 20
        assert(Rules.ChooseKingdom(player, kingdomId, Config, 10))
        equal(player.KingdomId, kingdomId)
        equal(player.LastKingdomAt, 10)
        equal(player.Wood, 30)
        equal(player.Ore, 20)
    end
end)

test("unknown kingdoms and malformed inputs cannot reserve a choice cooldown", function()
    local player = Rules.NewPlayer()
    for _, id in ipairs({ "", "Dawn", "Unknown", 42, false, {} }) do
        local accepted, reason = Rules.ChooseKingdom(player, id, Config, 4)
        equal(accepted, false)
        equal(reason, "UnknownKingdom")
        equal(player.KingdomId, nil)
        equal(player.LastKingdomAt, -math.huge)
    end
    equal(Rules.ChooseKingdom(nil, "Redcliff", Config, 0), false)
    equal(Rules.ChooseKingdom({}, "Redcliff", Config, 0), false)
    for _, now in ipairs({ -1, math.huge, -math.huge, 0 / 0, "10" }) do
        equal(Rules.ChooseKingdom(player, "Redcliff", Config, now), false)
    end
    equal(player.KingdomId, nil)
    assert(Rules.ChooseKingdom(player, "Redcliff", Config, 0))
end)

test("kingdom change cooldown rejects repeated choices atomically and expires at its boundary", function()
    local player = citizen()
    local accepted, reason = Rules.ChooseKingdom(player, "Korblox", Config, Config.World.KingdomChangeCooldown - 0.001)
    equal(accepted, false)
    equal(reason, "KingdomCooldown")
    equal(player.KingdomId, "Redcliff")
    equal(player.LastKingdomAt, 0)
    assert(Rules.ChooseKingdom(player, "Korblox", Config, Config.World.KingdomChangeCooldown))
    equal(player.KingdomId, "Korblox")
end)

test("reselecting the current kingdom never refreshes the cooldown", function()
    local player = citizen()
    local accepted, reason = Rules.ChooseKingdom(player, "Redcliff", Config, Config.World.KingdomChangeCooldown + 5)
    equal(accepted, false)
    equal(reason, "AlreadyKingdom")
    equal(player.LastKingdomAt, 0)
    assert(Rules.ChooseKingdom(player, "Greywolf", Config, Config.World.KingdomChangeCooldown + 5))
end)

test("tree and mine nodes start independently with the configured hit counts", function()
    local tree, otherTree, mine = Rules.NewNode("Tree", Config), Rules.NewNode("Tree", Config), Rules.NewNode("Mine", Config)
    equal(tree.HitsRemaining, Config.World.Tree.Hits)
    equal(mine.HitsRemaining, Config.World.Mine.Hits)
    equal(tree.RespawnAt, 0)
    tree.HitsRemaining = 1
    equal(otherTree.HitsRemaining, Config.World.Tree.Hits)
    for _, kind in ipairs({ "Ore", "", false, 4, {} }) do equal(Rules.NewNode(kind, Config), nil) end
end)

test("a kingdom is required to gather and a permission check never changes state", function()
    local player, node = Rules.NewPlayer(), Rules.NewNode("Tree", Config)
    local accepted, reason = Rules.CanHarvest(player, node, Config, 0)
    equal(accepted, false)
    equal(reason, "ChooseKingdom")
    assert(Rules.ChooseKingdom(player, "Redcliff", Config, 0))
    assert(Rules.CanHarvest(player, node, Config, 0))
    assert(Rules.CanHarvest(player, node, Config, 0))
    equal(player.LastHarvestAt, -math.huge)
    equal(player.Wood, 0)
    equal(node.HitsRemaining, Config.World.Tree.Hits)
end)

test("trees pay wood exactly once on the accepted final strike", function()
    local player, node = citizen(), Rules.NewNode("Tree", Config)
    for hit = 1, Config.World.Tree.Hits do
        local accepted, result = Rules.Harvest(player, node, Config, hit * Config.World.HarvestCooldown)
        assert(accepted)
        equal(result.Resource, "Wood")
        equal(result.Depleted, hit == Config.World.Tree.Hits)
        equal(result.Amount, hit == Config.World.Tree.Hits and Config.World.Tree.Yield or 0)
        equal(player.Wood, result.Amount)
        equal(player.Ore, 0)
    end
    equal(node.HitsRemaining, 0)
    local before = player.Wood
    local accepted, reason = Rules.Harvest(player, node, Config, 10000)
    equal(accepted, false)
    equal(reason, "Depleted")
    equal(player.Wood, before)
end)

test("mine depletion rewards ore without awarding wood", function()
    local player, node = citizen(), Rules.NewNode("Mine", Config)
    local result = deplete(player, node, 0)
    equal(result.Resource, "Ore")
    equal(result.Amount, Config.World.Mine.Yield)
    equal(player.Ore, Config.World.Mine.Yield)
    equal(player.Wood, 0)
end)

test("harvest cooldown is shared across nodes and refusal preserves hits and inventory", function()
    local player = citizen()
    local tree, mine = Rules.NewNode("Tree", Config), Rules.NewNode("Mine", Config)
    assert(Rules.Harvest(player, tree, Config, 10))
    local accepted, reason = Rules.Harvest(player, mine, Config, 10 + Config.World.HarvestCooldown - 0.001)
    equal(accepted, false)
    equal(reason, "HarvestCooldown")
    equal(mine.HitsRemaining, Config.World.Mine.Hits)
    equal(player.LastHarvestAt, 10)
    equal(player.Ore, 0)
    assert(Rules.Harvest(player, mine, Config, 10 + Config.World.HarvestCooldown))
end)

test("the player landing a shared node's final hit gets the entire reward", function()
    local first, second, node = citizen(), citizen("Korblox"), Rules.NewNode("Tree", Config)
    for hit = 1, Config.World.Tree.Hits - 1 do
        assert(Rules.Harvest(first, node, Config, hit * Config.World.HarvestCooldown))
    end
    assert(Rules.Harvest(second, node, Config, Config.World.Tree.Hits * Config.World.HarvestCooldown))
    equal(first.Wood, 0)
    equal(second.Wood, Config.World.Tree.Yield)
    equal(Rules.Harvest(first, node, Config, 100), false)
    equal(first.Wood, 0)
end)

test("depleted nodes restore only when their respawn deadline is reached", function()
    for _, kind in ipairs({ "Tree", "Mine" }) do
        local player, node = citizen(), Rules.NewNode(kind, Config)
        deplete(player, node, 10)
        local deadline = 10 + (Config.World[kind].Hits - 1) * Config.World.HarvestCooldown + Config.World[kind].RespawnSeconds
        equal(node.RespawnAt, deadline)
        equal(Rules.RefreshNode(node, Config, deadline - 0.001), false)
        equal(node.HitsRemaining, 0)
        equal(Rules.RefreshNode(node, Config, deadline), true)
        equal(node.HitsRemaining, Config.World[kind].Hits)
        equal(node.RespawnAt, 0)
        equal(Rules.RefreshNode(node, Config, deadline + 1), false)
        assert(Rules.Harvest(player, node, Config, deadline))
    end
end)

test("invalid harvest times, nodes or inventories cannot change any resource", function()
    local player, node = citizen(), Rules.NewNode("Tree", Config)
    for _, now in ipairs({ -1, math.huge, -math.huge, 0 / 0, "1" }) do
        equal(Rules.Harvest(player, node, Config, now), false)
        equal(Rules.RefreshNode(node, Config, now), false)
    end
    for _, badNode in ipairs({ false, {}, { Kind = "Tree", HitsRemaining = -1, RespawnAt = 0 }, { Kind = "Tree", HitsRemaining = 1.5, RespawnAt = 0 }, { Kind = "Tree", HitsRemaining = 1, RespawnAt = math.huge } }) do
        equal(Rules.Harvest(player, badNode, Config, 0), false)
        equal(Rules.RefreshNode(badNode, Config, 10), false)
    end
    equal(node.HitsRemaining, Config.World.Tree.Hits)
    equal(player.LastHarvestAt, -math.huge)
    for _, value in ipairs({ -1, 0.5, math.huge, 0 / 0, "50" }) do
        player.Wood = value
        equal(Rules.Harvest(player, node, Config, 0), false)
    end
    equal(node.HitsRemaining, Config.World.Tree.Hits)
    equal(player.LastHarvestAt, -math.huge)
end)

test("an uncontested kingdom captures after the configured interval", function()
    local point = Rules.NewOutpost()
    assert(Rules.StepCapture(point, { Redcliff = 1 }, Config, Config.World.CaptureSeconds / 2))
    equal(point.Owner, nil)
    equal(point.Claimant, "Redcliff")
    near(point.Progress, 0.5)
    assert(Rules.StepCapture(point, { Redcliff = 1 }, Config, Config.World.CaptureSeconds / 2))
    equal(point.Owner, "Redcliff")
    equal(point.Claimant, nil)
    equal(point.Progress, 0)
    equal(point.Built, false)
end)

test("multiple players of one kingdom do not accelerate the capture timer", function()
    local single, crowd = Rules.NewOutpost(), Rules.NewOutpost()
    Rules.StepCapture(single, { Redcliff = 1 }, Config, 3)
    Rules.StepCapture(crowd, { Redcliff = 10 }, Config, 3)
    near(single.Progress, crowd.Progress)
end)

test("two hostile kingdoms contest and freeze capture until one leaves", function()
    local point = Rules.NewOutpost()
    Rules.StepCapture(point, { Redcliff = 1 }, Config, 3)
    local progress = point.Progress
    assert(Rules.StepCapture(point, { Redcliff = 1, Korblox = 1 }, Config, 10))
    equal(point.Contested, true)
    equal(point.Owner, nil)
    equal(point.Claimant, "Redcliff")
    equal(point.Progress, progress)
    equal(Rules.StepCapture(point, { Redcliff = 2, Korblox = 2 }, Config, 10), false)
    assert(Rules.StepCapture(point, { Redcliff = 1 }, Config, 1))
    equal(point.Contested, false)
    assert(point.Progress > progress)
end)

test("empty outposts lose challenger progress and clear the claimant at zero", function()
    local point = Rules.NewOutpost()
    Rules.StepCapture(point, { Redcliff = 1 }, Config, 6)
    Rules.StepCapture(point, {}, Config, 3)
    near(point.Progress, 3 / Config.World.CaptureSeconds)
    equal(point.Claimant, "Redcliff")
    Rules.StepCapture(point, {}, Config, Config.World.CaptureSeconds)
    equal(point.Progress, 0)
    equal(point.Claimant, nil)
    equal(Rules.StepCapture(point, {}, Config, 1), false)
end)

test("owner-only presence decays an enemy claim without dropping ownership", function()
    local point = ownerPoint()
    point.Built = true
    Rules.StepCapture(point, { Korblox = 1 }, Config, 6)
    Rules.StepCapture(point, { Redcliff = 1 }, Config, 3)
    near(point.Progress, 3 / Config.World.CaptureSeconds)
    equal(point.Owner, "Redcliff")
    equal(point.Built, true)
end)

test("a different challenger starts its own capture rather than inheriting progress", function()
    local point = ownerPoint()
    Rules.StepCapture(point, { Korblox = 1 }, Config, 10)
    Rules.StepCapture(point, { Greywolf = 1 }, Config, 1)
    equal(point.Claimant, "Greywolf")
    near(point.Progress, 1 / Config.World.CaptureSeconds)
    equal(point.Owner, "Redcliff")
end)

test("changing ownership removes the previous kingdom's built outpost", function()
    local point = ownerPoint()
    point.Built = true
    Rules.StepCapture(point, { Korblox = 1 }, Config, Config.World.CaptureSeconds)
    equal(point.Owner, "Korblox")
    equal(point.Built, false)
    equal(point.Claimant, nil)
    equal(point.Progress, 0)
    equal(Rules.StepCapture(point, { Korblox = 2 }, Config, 1), false)
end)

test("unknown kingdoms and zero or malformed counts cannot capture or contest a flag", function()
    local point = Rules.NewOutpost()
    equal(Rules.StepCapture(point, { Dawn = 100, Unknown = 10, Redcliff = 0, Korblox = -1, Greywolf = math.huge, Overseer = 0 / 0 }, Config, 20), false)
    equal(point.Owner, nil)
    equal(point.Contested, false)
    Rules.StepCapture(point, { Redcliff = 1, Korblox = "1", Overseer = 0.5, Unknown = 10 }, Config, 1)
    equal(point.Contested, false)
    equal(point.Claimant, "Redcliff")
    near(point.Progress, 1 / Config.World.CaptureSeconds)
end)

test("invalid frame durations and malformed counts leave capture state unchanged", function()
    local point = ownerPoint()
    point.Built = true
    for _, dt in ipairs({ -1, 0, math.huge, -math.huge, 0 / 0, "1" }) do
        equal(Rules.StepCapture(point, { Korblox = 1 }, Config, dt), false)
    end
    for _, counts in ipairs({ false, 1, "Korblox" }) do equal(Rules.StepCapture(point, counts, Config, 1), false) end
    equal(Rules.StepCapture(nil, {}, Config, 1), false)
    equal(point.Owner, "Redcliff")
    equal(point.Claimant, nil)
    equal(point.Progress, 0)
    equal(point.Built, true)
end)

test("building spends both resource costs exactly once for the owner", function()
    local player, point = citizen(), ownerPoint()
    player.Wood, player.Ore = Config.World.OutpostWoodCost + 2, Config.World.OutpostOreCost + 3
    assert(Rules.BuildOutpost(player, point, Config))
    equal(player.Wood, 2)
    equal(player.Ore, 3)
    equal(point.Built, true)
    local accepted, reason = Rules.BuildOutpost(player, point, Config)
    equal(accepted, false)
    equal(reason, "AlreadyBuilt")
    equal(player.Wood, 2)
    equal(player.Ore, 3)
end)

test("missing either material prevents all build deductions", function()
    local player, point = citizen(), ownerPoint()
    player.Wood, player.Ore = Config.World.OutpostWoodCost - 1, Config.World.OutpostOreCost
    local accepted, reason = Rules.BuildOutpost(player, point, Config)
    equal(accepted, false)
    equal(reason, "InsufficientWood")
    equal(player.Ore, Config.World.OutpostOreCost)
    player.Wood, player.Ore = Config.World.OutpostWoodCost, Config.World.OutpostOreCost - 1
    accepted, reason = Rules.BuildOutpost(player, point, Config)
    equal(accepted, false)
    equal(reason, "InsufficientOre")
    equal(player.Wood, Config.World.OutpostWoodCost)
    equal(point.Built, false)
end)

test("only the owning kingdom can build and neutral flags reject unchosen players", function()
    local player, point = citizen("Korblox"), ownerPoint()
    player.Wood, player.Ore = 100, 100
    local accepted, reason = Rules.BuildOutpost(player, point, Config)
    equal(accepted, false)
    equal(reason, "NotOwner")
    equal(player.Wood, 100)
    equal(player.Ore, 100)
    equal(point.Built, false)
    local neutral = Rules.NewOutpost()
    equal(Rules.BuildOutpost(Rules.NewPlayer(), neutral, Config), false)
    equal(Rules.BuildOutpost(player, neutral, Config), false)
end)

test("contested flags cannot spend materials or become fortified", function()
    local player, point = citizen(), ownerPoint()
    player.Wood, player.Ore = 100, 100
    point.Contested = true
    local accepted, reason = Rules.BuildOutpost(player, point, Config)
    equal(accepted, false)
    equal(reason, "Contested")
    equal(player.Wood, 100)
    equal(player.Ore, 100)
    equal(point.Built, false)
end)

test("malformed player state and outposts cannot spend materials or gain ownership", function()
    local point = ownerPoint()
    equal(Rules.BuildOutpost({}, point, Config), false)
    local player = citizen()
    player.Wood, player.Ore = 100, 100
    for _, malformed in ipairs({ false, {}, { Owner = "Redcliff", Progress = math.huge, Built = false, Contested = false } }) do
        equal(Rules.BuildOutpost(player, malformed, Config), false)
    end
    player.Ore = math.huge
    equal(Rules.BuildOutpost(player, point, Config), false)
    equal(player.Wood, 100)
    equal(point.Built, false)
end)

print(tostring(passed) .. " world rule tests passed; 0 failed")
