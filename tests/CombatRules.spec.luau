-- Run with: .tools/bin/luau tests/CombatRules.spec.luau
-- These tests load the same portable rules that the Roblox server uses.
local Config = require("../src/shared/Config")
local Rules = require("../src/shared/CombatRules")

local passed = 0
local failed = 0

local function equal(actual, expected, message)
	assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function near(actual, expected, message)
	assert(math.abs(actual - expected) < 0.000001, (message or "unexpected number") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, callback)
	local ok, problem = pcall(callback)
	if ok then
		passed += 1
		print("PASS " .. name)
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(problem))
	end
end

-- Cases below exercise accepted and refused player actions, not Roblox services.
test("requested stamina and potion key bindings", function()
	equal(Config.Combat.MaxStamina, 100)
	equal(Config.Combat.AttackCost, 10)
	equal(Config.Combat.SprintDrainPerSecond, 1)
	equal(Config.Potions.Small.Key, "Z")
	equal(Config.Potions.Medium.Key, "X")
	equal(Config.Potions.Large.Key, "C")
	equal(Config.PotionCooldown, 60)
end)

test("new combatants start with independent stamina and potion inventories", function()
	local first = Rules.NewState(Config, 0)
	local second = Rules.NewState(Config, 0)
	equal(first.Stamina, 100)
	equal(first.Sprinting, false)
	equal(first.Dead, false)
	for _, size in ipairs(Config.PotionOrder) do
		equal(first.Potions[size], Config.Potions[size].Count)
	end
	first.Potions.Small = 0
	equal(second.Potions.Small, Config.Potions.Small.Count, "inventories must belong to one character")
end)

test("each accepted swing costs 10 stamina", function()
	local state = Rules.NewState(Config, 0)
	assert(Rules.ConsumeAttack(state, Config, 0))
	equal(state.Stamina, 90)
	assert(Rules.ConsumeAttack(state, Config, 1))
	equal(state.Stamina, 80)
end)

test("only accepted attacks alternate the two horizontal swing directions", function()
	local state = Rules.NewState(Config, 0)
	equal(state.NextSwingSide, 1)
	equal(state.SwingSide, nil)
	assert(Rules.ConsumeAttack(state, Config, 0))
	equal(state.SwingSide, 1)
	equal(state.NextSwingSide, -1)
	equal(Rules.ConsumeAttack(state, Config, 0.001), false)
	equal(state.SwingSide, 1)
	equal(state.NextSwingSide, -1, "spam must not skip an animation")
	assert(Rules.ConsumeAttack(state, Config, 1))
	equal(state.SwingSide, -1)
	equal(state.NextSwingSide, 1)
	state.Stamina = 0
	equal(Rules.ConsumeAttack(state, Config, 2), false)
	equal(state.SwingSide, -1)
	equal(state.NextSwingSide, 1, "exhaustion must not skip an animation")
	state.Stamina = 10
	assert(Rules.ConsumeAttack(state, Config, 3))
	equal(state.SwingSide, 1)
end)

test("attack spam cannot spend or damage repeatedly during cooldown", function()
	local state = Rules.NewState(Config, 0)
	assert(Rules.ConsumeAttack(state, Config, 5))
	for index = 1, 20 do
		local accepted, reason = Rules.ConsumeAttack(state, Config, 5 + index * 0.001)
		equal(accepted, false)
		equal(reason, "Cooldown")
	end
	equal(state.Stamina, 90)
	equal(state.LastAttackAt, 5)
	assert(Rules.ConsumeAttack(state, Config, 5 + Config.Combat.AttackCooldown))
	equal(state.Stamina, 80)
end)

test("a player can swing ten times from full stamina and then must recover", function()
	local state = Rules.NewState(Config, 0)
	for index = 0, 9 do
		assert(Rules.ConsumeAttack(state, Config, index))
	end
	equal(state.Stamina, 0)
	local accepted, reason = Rules.ConsumeAttack(state, Config, 10)
	equal(accepted, false)
	equal(reason, "Stamina")
	equal(state.Stamina, 0)
end)

test("insufficient stamina refuses a swing without changing action timers", function()
	local state = Rules.NewState(Config, 0)
	state.Stamina = 9
	local accepted, reason = Rules.ConsumeAttack(state, Config, 1)
	equal(accepted, false)
	equal(reason, "Stamina")
	equal(state.Stamina, 9)
	equal(state.LastSpendAt, 0)
	equal(state.SpawnProtectedUntil, Config.Game.SpawnProtectionSeconds)
	state.Stamina = 10
	assert(Rules.ConsumeAttack(state, Config, 1))
	equal(state.Stamina, 0)
end)

test("attacking voluntarily ends the attacker's spawn protection", function()
	local state = Rules.NewState(Config, 10)
	assert(state.SpawnProtectedUntil > 10)
	assert(Rules.ConsumeAttack(state, Config, 10))
	equal(state.SpawnProtectedUntil, 0)
end)

test("sprinting drains one stamina per second only while moving", function()
	local state = Rules.NewState(Config, 0)
	state.Sprinting = true
	Rules.TickStamina(state, Config, 0.25, 0.25, true)
	near(state.Stamina, 99.75)
	Rules.TickStamina(state, Config, 0.75, 1, true)
	near(state.Stamina, 99)
	Rules.TickStamina(state, Config, 0.5, 1.5, false)
	near(state.Stamina, 99, "holding sprint while stationary must not spend stamina")
	state.Sprinting = false
	Rules.TickStamina(state, Config, 0.25, 1.75, true)
	near(state.Stamina, 99, "walking must not spend stamina")
end)

test("sprint drain is independent of frame rate", function()
	local manySteps = Rules.NewState(Config, 0)
	local oneStep = Rules.NewState(Config, 0)
	manySteps.Sprinting = true
	oneStep.Sprinting = true
	for index = 1, 120 do
		Rules.TickStamina(manySteps, Config, 1 / 60, index / 60, true)
	end
	Rules.TickStamina(oneStep, Config, 2, 2, true)
	near(manySteps.Stamina, 98)
	near(manySteps.Stamina, oneStep.Stamina)
end)

test("exhaustion stops sprinting and never produces negative stamina", function()
	local state = Rules.NewState(Config, 0)
	state.Stamina = 0.2
	state.Sprinting = true
	Rules.TickStamina(state, Config, 1, 1, true)
	equal(state.Stamina, 0)
	equal(state.Sprinting, false)
	Rules.TickStamina(state, Config, 0.5, 1.5, true)
	equal(state.Stamina, 0)
end)

test("stamina regenerates after its delay and stops at 100", function()
	local state = Rules.NewState(Config, 0)
	assert(Rules.ConsumeAttack(state, Config, 0))
	Rules.TickStamina(state, Config, 1, 1, false)
	equal(state.Stamina, 90)
	Rules.TickStamina(state, Config, 0.5, 1.5, false)
	equal(state.Stamina, 90)
	Rules.TickStamina(state, Config, 0.5, 2, false)
	near(state.Stamina, 92.5)
	Rules.TickStamina(state, Config, 100, 102, false)
	equal(state.Stamina, 100)
end)

test("a frame crossing the regeneration delay restores only eligible time", function()
	local state = Rules.NewState(Config, 0)
	state.Stamina = 50
	Rules.TickStamina(state, Config, 2, 2, false)
	near(state.Stamina, 52.5)
end)

test("spending stamina resets the regeneration delay", function()
	local state = Rules.NewState(Config, 0)
	assert(Rules.ConsumeAttack(state, Config, 2))
	Rules.TickStamina(state, Config, 1, 3, false)
	equal(state.Stamina, 90)
	state.Sprinting = true
	Rules.TickStamina(state, Config, 0.5, 3.5, true)
	near(state.Stamina, 89.5)
	state.Sprinting = false
	Rules.TickStamina(state, Config, 1, 4.5, false)
	near(state.Stamina, 89.5)
end)

test("invalid frame durations cannot alter stamina", function()
	local state = Rules.NewState(Config, 0)
	state.Stamina = 50
	state.Sprinting = true
	for _, dt in ipairs({ -1, 0, math.huge, -math.huge, 0 / 0 }) do
		Rules.TickStamina(state, Config, dt, 100, true)
		equal(state.Stamina, 50)
	end
end)

test("each potion restores its configured amount and consumes one stock", function()
	for _, size in ipairs(Config.PotionOrder) do
		local state = Rules.NewState(Config, 0)
		local accepted, health = Rules.ConsumePotion(state, Config, size, 10, 100, 0)
		equal(accepted, true)
		equal(health, 10 + Config.Potions[size].Heal)
		equal(state.Potions[size], Config.Potions[size].Count - 1)
	end
end)

test("all potion sizes heal without exceeding maximum health", function()
	for _, size in ipairs(Config.PotionOrder) do
		local state = Rules.NewState(Config, 0)
		local accepted, health = Rules.ConsumePotion(state, Config, size, 99, 100, 0)
		equal(accepted, true)
		equal(health, 100)
	end
end)

test("all potion sizes share exactly sixty seconds of cooldown", function()
	for _, size in ipairs(Config.PotionOrder) do
		local state = Rules.NewState(Config, 0)
		local firstSize = if size == "Large" then "Small" else "Large"
		assert(Rules.ConsumePotion(state, Config, firstSize, 10, 100, 0))
		local before = table.clone(state.Potions)
		for _, time in ipairs({ 0, 30, 59.999 }) do
			local accepted, reason = Rules.ConsumePotion(state, Config, size, 10, 100, time)
			equal(accepted, false, size .. " must still be cooling down at " .. tostring(time))
			equal(reason, "Cooldown")
			for _, inventorySize in ipairs(Config.PotionOrder) do
				equal(state.Potions[inventorySize], before[inventorySize], "cooldown must preserve every stock")
			end
		end
		assert(Rules.ConsumePotion(state, Config, size, 10, 100, 60), size .. " must be available at sixty seconds")
		equal(state.Potions[size], before[size] - 1)
	end
end)

test("using a potion at full health wastes neither stock nor cooldown", function()
	local state = Rules.NewState(Config, 0)
	local accepted, reason = Rules.ConsumePotion(state, Config, "Small", 100, 100, 5)
	equal(accepted, false)
	equal(reason, "FullHealth")
	equal(state.Potions.Small, Config.Potions.Small.Count)
	assert(Rules.ConsumePotion(state, Config, "Small", 50, 100, 5))
	equal(state.Potions.Small, Config.Potions.Small.Count - 1)
end)

test("an empty potion stock cannot become negative or reserve the cooldown", function()
	local state = Rules.NewState(Config, 0)
	local count = Config.Potions.Small.Count
	for index = 0, count - 1 do
		assert(Rules.ConsumePotion(state, Config, "Small", 1, 100, index * Config.PotionCooldown))
	end
	local accepted, reason = Rules.ConsumePotion(state, Config, "Small", 1, 100, count * Config.PotionCooldown)
	equal(accepted, false)
	equal(reason, "Empty")
	equal(state.Potions.Small, 0)
	assert(Rules.ConsumePotion(state, Config, "Medium", 1, 100, count * Config.PotionCooldown))
end)

test("unknown potion sizes and invalid health cannot consume inventory", function()
	local state = Rules.NewState(Config, 0)
	for _, size in ipairs({ "Huge", "", 42, false, {} }) do
		local accepted = Rules.ConsumePotion(state, Config, size, 50, 100, 0)
		equal(accepted, false)
	end
	for _, health in ipairs({ 0, -1, math.huge, -math.huge, 0 / 0 }) do
		local accepted = Rules.ConsumePotion(state, Config, "Small", health, 100, 0)
		equal(accepted, false)
	end
	for _, maximum in ipairs({ 0, -1, math.huge, 0 / 0 }) do
		local accepted = Rules.ConsumePotion(state, Config, "Small", 50, maximum, 0)
		equal(accepted, false)
	end
	equal(state.Potions.Small, Config.Potions.Small.Count)
	assert(Rules.ConsumePotion(state, Config, "Small", 50, 100, 0))
end)

test("dead combatants cannot attack, heal or regenerate", function()
	local state = Rules.NewState(Config, 0)
	state.Dead = true
	state.Stamina = 50
	equal(Rules.ConsumeAttack(state, Config, 10), false)
	equal(Rules.ConsumePotion(state, Config, "Large", 1, 100, 10), false)
	Rules.TickStamina(state, Config, 10, 10, false)
	equal(state.Stamina, 50)
	equal(state.Potions.Large, Config.Potions.Large.Count)
end)

test("damage accepts enemies only after spawn protection expires", function()
	local attacker = Rules.NewState(Config, 0)
	local target = Rules.NewState(Config, 0)
	attacker.TeamId = "Dawn"
	target.TeamId = "Ember"
	equal(Rules.CanDamage(attacker, target, Config.Game.SpawnProtectionSeconds - 0.01), false)
	equal(Rules.CanDamage(attacker, target, Config.Game.SpawnProtectionSeconds), true)
	target.TeamId = "Dawn"
	equal(Rules.CanDamage(attacker, target, 100), false, "friendly fire must be disabled")
	equal(Rules.CanDamage(attacker, attacker, 100), false, "self damage must be disabled")
end)

test("neither dead attackers nor dead targets can participate in damage", function()
	local attacker = Rules.NewState(Config, 0)
	local target = Rules.NewState(Config, 0)
	attacker.TeamId = "Dawn"
	target.TeamId = "Ember"
	attacker.Dead = true
	equal(Rules.CanDamage(attacker, target, 100), false)
	attacker.Dead = false
	target.Dead = true
	equal(Rules.CanDamage(attacker, target, 100), false)
end)

test("sword hits respect maximum range and the forward attack arc", function()
	local boundary = math.cos(math.rad(Config.Combat.AttackArc / 2))
	equal(Rules.InAttackArc(Config.Combat.AttackRange, 1, Config), true)
	equal(Rules.InAttackArc(1, boundary, Config), true)
	equal(Rules.InAttackArc(Config.Combat.AttackRange + 0.01, 1, Config), false)
	equal(Rules.InAttackArc(1, boundary - 0.01, Config), false)
	equal(Rules.InAttackArc(1, -1, Config), false, "a player behind the attacker must not be hit")
end)

test("nonfinite or negative hit geometry is rejected", function()
	for _, distance in ipairs({ -1, math.huge, -math.huge, 0 / 0 }) do
		equal(Rules.InAttackArc(distance, 1, Config), false)
	end
	for _, dot in ipairs({ math.huge, -math.huge, 0 / 0 }) do
		equal(Rules.InAttackArc(1, dot, Config), false)
	end
end)

print(tostring(passed) .. " passed; " .. tostring(failed) .. " failed")
assert(failed == 0, tostring(failed) .. " combat rules test(s) failed")
