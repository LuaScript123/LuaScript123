-- Run with: .tools/bin/luau tests/MatchRules.spec.luau
-- The same portable elimination rules are used by MatchService in Roblox.
local Config = require("../src/shared/Config")
local Rules = require("../src/shared/MatchRules")

local passed = 0
local failed = 0
local teamA = Config.TeamOrder[1]
local teamB = Config.TeamOrder[2]
local ids = { "a1", "a2", "b1", "b2" }

local function equal(actual, expected, message)
	assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
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

local function newRoster()
	return Rules.New(Config.TeamOrder, 2)
end

local function fill(roster)
	assert(Rules.Add(roster, "a1", teamA))
	assert(Rules.Add(roster, "a2", teamA))
	assert(Rules.Add(roster, "b1", teamB))
	assert(Rules.Add(roster, "b2", teamB))
	return roster
end

local function lockedRoster()
	local roster = fill(newRoster())
	assert(Rules.Lock(roster))
	return roster
end

local function readyRoster()
	local roster = lockedRoster()
	for _, id in ipairs(ids) do
		assert(Rules.SetReady(roster, id, true))
	end
	return roster
end

local function startedRoster()
	local roster = readyRoster()
	assert(Rules.Begin(roster))
	return roster
end

test("an empty roster cannot start or declare a winner", function()
	local roster = newRoster()
	equal(roster.Locked, false)
	equal(Rules.IsReady(roster), false)
	equal(Rules.Begin(roster), false)
	local finished, winner = Rules.Resolve(roster)
	equal(finished, false)
	equal(winner, nil)
	equal(Rules.Get(roster, "missing"), nil)
end)

test("each team accepts two members and refuses a third", function()
	local roster = fill(newRoster())
	for _, teamId in ipairs(Config.TeamOrder) do
		local accepted, reason = Rules.Add(roster, "extra-" .. teamId, teamId)
		equal(accepted, false)
		equal(reason, "TeamFull")
	end
	local alive = Rules.CountAlive(roster)
	equal(alive[teamA], 2)
	equal(alive[teamB], 2)
end)

test("duplicate identities and unknown teams cannot replace a member", function()
	local roster = newRoster()
	assert(Rules.Add(roster, "a1", teamA))
	local accepted, reason = Rules.Add(roster, "a1", teamB)
	equal(accepted, false)
	equal(reason, "Duplicate")
	accepted, reason = Rules.Add(roster, "outsider", "UnknownTeam")
	equal(accepted, false)
	equal(reason, "UnknownTeam")
	equal(Rules.Get(roster, "a1").TeamId, teamA)
	equal(Rules.Get(roster, "outsider"), nil)
end)

test("an incomplete 2v2 cannot lock and can still receive its fourth member", function()
	local roster = newRoster()
	assert(Rules.Add(roster, "a1", teamA))
	assert(Rules.Add(roster, "a2", teamA))
	assert(Rules.Add(roster, "b1", teamB))
	local accepted, reason = Rules.Lock(roster)
	equal(accepted, false)
	equal(reason, "Incomplete")
	equal(roster.Locked, false)
	assert(Rules.Add(roster, "b2", teamB))
	assert(Rules.Lock(roster))
	equal(roster.Locked, true)
end)

test("locked rosters refuse late entrants and cannot lock a second time", function()
	local roster = lockedRoster()
	local accepted, reason = Rules.Add(roster, "late", teamA)
	equal(accepted, false)
	equal(reason, "Locked")
	equal(Rules.Get(roster, "late"), nil)
	accepted, reason = Rules.Lock(roster)
	equal(accepted, false)
	equal(reason, "AlreadyLocked")
end)

test("all four locked members must be ready before battle", function()
	local roster = lockedRoster()
	equal(Rules.IsReady(roster), false)
	for index, id in ipairs(ids) do
		assert(Rules.SetReady(roster, id, true))
		equal(Rules.IsReady(roster), index == #ids)
	end
	equal(Rules.SetReady(roster, "missing", true), false)
	assert(Rules.SetReady(roster, "a1", false))
	equal(Rules.IsReady(roster), false)
	equal(Rules.Begin(roster), false)
end)

test("three ready members cannot begin or resolve while the fourth loads", function()
	local roster = lockedRoster()
	for index = 1, 3 do
		assert(Rules.SetReady(roster, ids[index], true))
	end
	equal(Rules.Begin(roster), false)
	local finished, winner = Rules.Resolve(roster)
	equal(finished, false)
	equal(winner, nil)
	assert(Rules.SetReady(roster, ids[4], true))
	assert(Rules.Begin(roster))
end)

test("four ready members still need an explicit battle start", function()
	local roster = readyRoster()
	equal(Rules.IsReady(roster), true)
	local finished, winner = Rules.Resolve(roster)
	equal(finished, false)
	equal(winner, nil)
	assert(Rules.Begin(roster))
	equal(roster.Started, true)
	equal(Rules.Begin(roster), false)
end)

test("elimination during loading cannot produce a premature victory", function()
	local roster = lockedRoster()
	assert(Rules.SetReady(roster, "b1", true))
	assert(Rules.SetReady(roster, "b2", true))
	assert(Rules.Eliminate(roster, "a1"))
	assert(Rules.Eliminate(roster, "a2"))
	local finished, winner = Rules.Resolve(roster)
	equal(finished, false)
	equal(winner, nil)
	equal(Rules.IsReady(roster), false)
	equal(Rules.Begin(roster), false)
end)

test("a battle starts with two living members on each team", function()
	local roster = startedRoster()
	local alive = Rules.CountAlive(roster)
	equal(alive[teamA], 2)
	equal(alive[teamB], 2)
	local finished, winner = Rules.Resolve(roster)
	equal(finished, false)
	equal(winner, nil)
end)

test("one death leaves the 2v2 running and preserves loading readiness", function()
	local roster = startedRoster()
	assert(Rules.Eliminate(roster, "a1"))
	local member = Rules.Get(roster, "a1")
	equal(member.Eliminated, true)
	equal(member.Ready, true, "death must not be treated as unfinished loading")
	local alive = Rules.CountAlive(roster)
	equal(alive[teamA], 1)
	equal(alive[teamB], 2)
	local finished, winner = Rules.Resolve(roster)
	equal(finished, false)
	equal(winner, nil)
end)

test("elimination is idempotent and unknown disconnects do not change counts", function()
	local roster = startedRoster()
	assert(Rules.Eliminate(roster, "a1"))
	equal(Rules.Eliminate(roster, "a1"), false)
	equal(Rules.Eliminate(roster, "missing"), false)
	local alive = Rules.CountAlive(roster)
	equal(alive[teamA], 1)
	equal(alive[teamB], 2)
end)

test("eliminated or disconnected members cannot respawn or be replaced", function()
	local roster = startedRoster()
	assert(Rules.Eliminate(roster, "a1"))
	equal(Rules.SetReady(roster, "a1", true), false)
	equal(Rules.Add(roster, "a1", teamA), false)
	equal(Rules.Add(roster, "replacement", teamA), false)
	equal(Rules.Get(roster, "a1").Eliminated, true)
	equal(Rules.Get(roster, "replacement"), nil)
	equal(Rules.CountAlive(roster)[teamA], 1)
end)

test("readiness cannot be reset after battle begins", function()
	local roster = startedRoster()
	equal(Rules.SetReady(roster, "b1", false), false)
	equal(Rules.Get(roster, "b1").Ready, true)
	assert(Rules.Eliminate(roster, "a1"))
	assert(Rules.Eliminate(roster, "a2"))
	local finished, winner = Rules.Resolve(roster)
	equal(finished, true)
	equal(winner, teamB)
end)

test("eliminating the first team awards victory to the second team", function()
	local roster = startedRoster()
	assert(Rules.Eliminate(roster, "a1"))
	assert(Rules.Eliminate(roster, "a2"))
	local finished, winner = Rules.Resolve(roster)
	equal(finished, true)
	equal(winner, teamB)
	equal(Rules.CountAlive(roster)[teamA], 0)
end)

test("eliminating the second team awards victory to the first team", function()
	local roster = startedRoster()
	assert(Rules.Eliminate(roster, "b1"))
	assert(Rules.Eliminate(roster, "b2"))
	local finished, winner = Rules.Resolve(roster)
	equal(finished, true)
	equal(winner, teamA)
	equal(Rules.CountAlive(roster)[teamB], 0)
end)

test("one survivor on each team continues the battle", function()
	local roster = startedRoster()
	assert(Rules.Eliminate(roster, "a1"))
	assert(Rules.Eliminate(roster, "b1"))
	local finished, winner = Rules.Resolve(roster)
	equal(finished, false)
	equal(winner, nil)
end)

test("a simultaneous complete elimination ends in a draw", function()
	local roster = startedRoster()
	for _, id in ipairs(ids) do
		assert(Rules.Eliminate(roster, id))
	end
	local alive = Rules.CountAlive(roster)
	equal(alive[teamA], 0)
	equal(alive[teamB], 0)
	local finished, winner = Rules.Resolve(roster)
	equal(finished, true)
	equal(winner, nil)
end)

test("a new round starts with a fresh roster rather than reviving eliminated members", function()
	local previous = startedRoster()
	assert(Rules.Eliminate(previous, "a1"))
	local current = startedRoster()
	equal(Rules.Get(current, "a1").Eliminated, false)
	equal(Rules.CountAlive(current)[teamA], 2)
	equal(Rules.Get(previous, "a1").Eliminated, true)
	equal(Rules.CountAlive(previous)[teamA], 1)
end)

print(tostring(passed) .. " passed; " .. tostring(failed) .. " failed")
assert(failed == 0, tostring(failed) .. " match rules test(s) failed")
