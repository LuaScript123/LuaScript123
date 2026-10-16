-- Exercise the real server's recovery and gathering costs without Roblox.
local Config = require("../src/shared/Config")
local Rules = require("../src/shared/CombatRules")
local count = 0
local function test(name, run)
    run()
    count += 1
    print("PASS " .. name)
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " ~= " .. tostring(expected))
end
local function state() return Rules.NewState(Config, 0) end

test("health remains unchanged during recovery delay", function()
    near(Rules.RecoverHealth(state(), Config, 1, 7, 40, 100), 40)
end)
test("only the fraction of a frame beyond the recovery delay heals", function()
    near(Rules.RecoverHealth(state(), Config, 1, 8.25, 40, 100), 40.5)
end)
test("damage restarts the full health recovery delay", function()
    local s = state()
    s.LastDamagedAt = 10
    near(Rules.RecoverHealth(s, Config, 1, 17, 40, 100), 40)
    near(Rules.RecoverHealth(s, Config, 1, 19, 40, 100), 42)
end)
test("sword attacks and gathering restart out of combat recovery", function()
    local s = state()
    assert(Rules.ConsumeAttack(s, Config, 10))
    near(Rules.RecoverHealth(s, Config, 1, 17, 40, 100), 40)
    assert(Rules.ConsumeEffort(s, Config, 18, 10))
    near(Rules.RecoverHealth(s, Config, 1, 25, 40, 100), 40)
end)
test("health recovery clamps to maximum health", function()
    near(Rules.RecoverHealth(state(), Config, 1, 20, 99, 100), 100)
end)
test("recovery cannot resurrect dead or zero health characters", function()
    local s = state()
    s.Dead = true
    near(Rules.RecoverHealth(s, Config, 1, 20, 40, 100), 40)
    near(Rules.RecoverHealth(state(), Config, 1, 20, 0, 100), 0)
end)
test("invalid recovery durations cannot heal", function()
    for _, dt in ipairs({ 0, -1, math.huge, 0/0 }) do
        near(Rules.RecoverHealth(state(), Config, dt, 20, 40, 100), 40)
    end
end)
test("recovery is independent of tick frequency", function()
    local s, health = state(), 40
    for tick = 1, 100 do health = Rules.RecoverHealth(s, Config, 0.1, 8 + tick * 0.1, health, 100) end
    near(health, Rules.RecoverHealth(s, Config, 10, 18, 40, 100))
end)
test("accepted work spends stamina and updates shared swing timers", function()
    local s = state()
    assert(Rules.ConsumeEffort(s, Config, 1, Config.World.HarvestStaminaCost))
    near(s.Stamina, 90)
    near(s.LastWorkAt, 1)
    near(s.LastSpendAt, 1)
    assert(s.SwingSide == 1 and s.NextSwingSide == -1)
end)
test("gathering and attacks cannot bypass each other's swing cooldown", function()
    local s = state()
    assert(Rules.ConsumeEffort(s, Config, 1, 10))
    assert(not Rules.ConsumeAttack(s, Config, 1.1))
    assert(Rules.ConsumeAttack(s, Config, 2))
    assert(not Rules.ConsumeEffort(s, Config, 2.1, 10))
    near(s.Stamina, 80)
end)
test("rejected effort cannot change stamina or timers", function()
    local s = state()
    s.Stamina = 9
    assert(not Rules.ConsumeEffort(s, Config, 1, 10))
    near(s.Stamina, 9)
    assert(s.LastWorkAt == -math.huge and s.LastAttackAt == -math.huge and s.SwingSide == nil)
    for _, cost in ipairs({ -10, 0, math.huge, 0/0 }) do assert(not Rules.ConsumeEffort(s, Config, 1, cost)) end
    near(s.Stamina, 9)
end)
test("dead characters cannot gather resources", function()
    local s = state()
    s.Dead = true
    assert(not Rules.ConsumeEffort(s, Config, 1, 10))
    near(s.Stamina, 100)
end)
print(tostring(count) .. " recovery and effort tests passed; 0 failed")
