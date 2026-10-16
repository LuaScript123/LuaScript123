-- Optional Roblox integration smoke test, excluded from default.project.json.
-- Run the separate test project in Roblox Studio with Play or Run.
-- It uses actual Humanoids, raycasts, sword joints and RemoteEvents.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	warn("[Smoke] This test runner is intended for Roblox Studio only.")
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage:WaitForChild("MedievalShared"):WaitForChild("Config"))
local CombatService = require(ServerScriptService:WaitForChild("MedievalServer"):WaitForChild("CombatService"))

local fixtures = Instance.new("Folder")
fixtures.Name = "FerFiolesSmokeFixtures"
fixtures.Parent = workspace
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "FerFiolesSmokeRemotes"
remotesFolder.Parent = ReplicatedStorage
local remotes = {}
for _, name in ipairs({ "Action", "State", "Effects" }) do
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotesFolder
	remotes[name] = event
end

local combat = CombatService.new(remotes)
combat:SetEnabled(true)
local subjects = {}
local origin = Vector3.new(10000, 1000, 10000)
local passed = 0

local function equal(actual, expected, context)
	assert(actual == expected, context .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, callback)
	callback()
	passed += 1
	print("[Smoke] PASS " .. name)
end

local function rig(name, teamId, offset)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = true
	root.CanCollide = false
	root.CFrame = CFrame.new(origin + offset)
	root.Parent = model
	model.PrimaryPart = root
	for _, definition in ipairs({
		{ "Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0) },
		{ "Torso", Vector3.new(2, 2, 1), Vector3.zero },
		{ "Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0) },
	}) do
		local part = Instance.new("Part")
		part.Name = definition[1]
		part.Size = definition[2]
		part.CFrame = root.CFrame + definition[3]
		part.CanCollide = false
		part.Massless = true
		part.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	model.Parent = fixtures
	local state = assert(combat:Register(model, model, teamId), "fixture registration failed")
	state.SpawnProtectedUntil = 0
	subjects[#subjects + 1] = model
	return state
end

local attacker = rig("Attacker", "Dawn", Vector3.zero)
local enemy = rig("Enemy", "Ember", Vector3.new(30, 0, 0))
local secondEnemy = rig("SecondEnemy", "Ember", Vector3.new(40, 0, 0))
local ally = rig("Ally", "Dawn", Vector3.new(50, 0, 0))

local function position(state, offset)
	state.Root.Anchored = true
	state.Model:PivotTo(CFrame.new(origin + offset))
	state.Root.AssemblyLinearVelocity = Vector3.zero
	state.Root.AssemblyAngularVelocity = Vector3.zero
end

local function resetPositions()
	position(attacker, Vector3.zero)
	position(enemy, Vector3.new(30, 0, 0))
	position(secondEnemy, Vector3.new(40, 0, 0))
	position(ally, Vector3.new(50, 0, 0))
end

local lastSwing = -math.huge
local function swing(checkImmediately, checkAfterWindup)
	local remaining = Config.Combat.AttackCooldown - (os.clock() - lastSwing)
	if remaining > 0 then
		task.wait(remaining + 0.02)
	end
	assert(combat:Act(attacker.Subject, "Attack", { Aim = Vector3.new(0, 0, -1) }), "attack should be accepted")
	lastSwing = os.clock()
	if checkImmediately then
		checkImmediately()
	end
	task.wait(Config.Combat.AttackWindup + 0.05)
	combat:Step(0.01)
	if checkAfterWindup then
		checkAfterWindup()
	end
end

local ok, problem = pcall(function()
	test("registration provides real sword geometry and replicated attributes", function()
		assert(attacker.Model:FindFirstChild("FerSword"), "procedural sword must exist")
		assert(attacker.SwordJoint and attacker.SwordJoint:IsA("Motor6D"), "sword grip must be a Motor6D")
		equal(attacker.Model:GetAttribute("Stamina"), 100, "replicated stamina")
		equal(attacker.Model:GetAttribute("PotionsSmall"), Config.Potions.Small.Count, "replicated inventory")
	end)

	test("sword animation preserves locomotion settings before and after windup", function()
		attacker.Root.Anchored = false
		local speed = attacker.Humanoid.WalkSpeed
		local jumpPower = attacker.Humanoid.JumpPower
		local jumpHeight = attacker.Humanoid.JumpHeight
		local autoRotate = attacker.Humanoid.AutoRotate
		local function check()
			equal(attacker.Root.Anchored, false, "swing must leave the root movable")
			equal(attacker.Humanoid.WalkSpeed, speed, "walk speed during swing")
			equal(attacker.Humanoid.JumpPower, jumpPower, "jump power during swing")
			equal(attacker.Humanoid.JumpHeight, jumpHeight, "jump height during swing")
			equal(attacker.Humanoid.AutoRotate, autoRotate, "rotation during swing")
		end
		swing(check, check)
		resetPositions()
	end)

	test("invalid aim, malformed action and unsupported combat cannot spend stamina", function()
		local before = attacker.Stamina
		local health = enemy.Humanoid.Health
		equal(combat:Act(attacker.Subject, "Attack", { Aim = Vector3.new(0 / 0, 0, 0) }), false, "NaN aim")
		equal(combat:Act(attacker.Subject, "Attack", { Aim = Vector3.zero }), false, "zero aim")
		equal(combat:Act(attacker.Subject, "Attack", 42), false, "malformed payload")
		for _, action in ipairs({ "Kick", "Block", "Parry" }) do
			equal(combat:Act(attacker.Subject, action, { Aim = Vector3.new(0, 0, -1) }), false, action .. " must be unsupported")
		end
		equal(attacker.Stamina, before, "invalid input must not spend stamina")
		equal(attacker.PendingAttack, nil, "unsupported input must not schedule a hit")
		equal(enemy.Humanoid.Health, health, "unsupported input must not damage enemies")
	end)

	test("accepted enemy hit damages a real Humanoid once", function()
		position(enemy, Vector3.new(0, 0, -4))
		local before = enemy.Humanoid.Health
		swing()
		equal(enemy.Humanoid.Health, before - Config.Combat.AttackDamage, "enemy health after hit")
		combat:Step(0.01)
		equal(enemy.Humanoid.Health, before - Config.Combat.AttackDamage, "resolved hit must not repeat")
		resetPositions()
	end)

	test("friendlies and protected spawns ignore sword damage", function()
		position(ally, Vector3.new(0, 0, -4))
		local before = ally.Humanoid.Health
		swing()
		equal(ally.Humanoid.Health, before, "friendly fire")
		resetPositions()
		position(enemy, Vector3.new(0, 0, -4))
		enemy.SpawnProtectedUntil = os.clock() + 60
		before = enemy.Humanoid.Health
		swing()
		equal(enemy.Humanoid.Health, before, "spawn protection")
		enemy.SpawnProtectedUntil = 0
		resetPositions()
	end)

	test("a physical wall blocks a sword hit through raycasting", function()
		position(enemy, Vector3.new(0, 0, -4))
		local wall = Instance.new("Part")
		wall.Name = "LineOfSightWall"
		wall.Anchored = true
		wall.Size = Vector3.new(8, 8, 0.5)
		wall.Position = origin + Vector3.new(0, 0, -2)
		wall.Parent = fixtures
		local before = enemy.Humanoid.Health
		swing()
		equal(enemy.Humanoid.Health, before, "wall must block damage")
		wall:Destroy()
		resetPositions()
	end)

	test("one swing damages only the nearest enemy", function()
		position(enemy, Vector3.new(0, 0, -3))
		position(secondEnemy, Vector3.new(0, 0, -6))
		local firstHealth = enemy.Humanoid.Health
		local secondHealth = secondEnemy.Humanoid.Health
		swing()
		equal(enemy.Humanoid.Health, firstHealth - Config.Combat.AttackDamage, "nearest target")
		equal(secondEnemy.Humanoid.Health, secondHealth, "second target")
		resetPositions()
	end)

	test("potions heal official Humanoid health and synchronize inventory", function()
		local before = ally.Potions.Small
		equal(combat:Act(ally.Subject, "Potion", { Size = "Small" }), false, "full-health potion refusal")
		equal(ally.Potions.Small, before, "full-health stock preservation")
		ally.Humanoid.Health = 30
		assert(combat:Act(ally.Subject, "Potion", { Size = "Small" }))
		equal(ally.Humanoid.Health, 30 + Config.Potions.Small.Heal, "official healed health")
		equal(ally.Model:GetAttribute("PotionsSmall"), before - 1, "replicated stock")
		equal(combat:Act(ally.Subject, "Potion", { Size = "Medium" }), false, "shared potion cooldown")
		equal(ally.Potions.Medium, Config.Potions.Medium.Count, "refused potion preserves stock")
	end)

	test("lethal damage reports the actual killer once", function()
		local calls = 0
		combat.OnDeath = function(victim, killer)
			equal(victim, enemy, "death victim")
			equal(killer, attacker, "death killer")
			calls += 1
		end
		position(enemy, Vector3.new(0, 0, -4))
		enemy.Humanoid.Health = Config.Combat.AttackDamage
		swing()
		task.wait()
		equal(enemy.Humanoid.Health, 0, "lethal damage")
		equal(enemy.Dead, true, "authoritative death state")
		equal(calls, 1, "single death callback")
	end)
end)

combat:SetEnabled(false)
for _, subject in ipairs(subjects) do
	combat:Unregister(subject)
end
fixtures:Destroy()
remotesFolder:Destroy()

assert(ok, "[Smoke] FAILED: " .. tostring(problem))
print("[Smoke] " .. tostring(passed) .. " integration tests passed.")
