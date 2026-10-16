-- Pure production invitation rules: no Roblox engine simulation.
local Rules = require("../src/shared/InvitationRules")
local passed = 0
local function equal(a, b, message) assert(a == b, (message or "unexpected value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, callback) callback(); passed += 1; print("PASS " .. name) end
local function available(id) return id ~= 99 end
local function fresh() return Rules.New(15, 25) end
local function duel(state, now) return Rules.Create(state, 1, "Duel", {1, 2}, now or 0, available, false) end
local function released(state, ids) for _, id in ipairs(ids) do equal(Rules.Get(state, id), nil, "reservation leaked") end end

test("duels reserve both human slots and require the opponent's consent", function()
    local state = fresh()
    local invite = assert(duel(state))
    equal(invite.HostId, 1); equal(invite.Mode, "Duel"); equal(invite.ExpiresAt, 25)
    equal(invite.Accepted[1], true); equal(invite.Accepted[2], nil)
    equal(Rules.Get(state, 1), invite); equal(Rules.Get(state, 2), invite)
    local accepted, reason, ready = Rules.Respond(state, 2, invite.Id, true, 1)
    equal(accepted, invite); equal(reason, nil); equal(ready, true)
    released(state, {1, 2})
end)

test("two versus two waits for every invitee and preserves explicit team order", function()
    local state = fresh()
    local members = {1, 2, 3, 4}
    local invite = assert(Rules.Create(state, 1, "Teams", members, 5, available, false))
    members[2] = 99
    equal(invite.Members[2], 2, "request must be copied")
    for _, id in ipairs({3, 4}) do local _, _, ready = Rules.Respond(state, id, invite.Id, true, 6); equal(ready, false) end
    for _, id in ipairs({1, 2, 3, 4}) do equal(Rules.Get(state, id), invite) end
    local _, _, ready = Rules.Respond(state, 2, invite.Id, true, 7)
    equal(ready, true); released(state, {1, 2, 3, 4})
end)

test("host cannot bypass consent and outsiders cannot answer", function()
    local state = fresh(); local invite = assert(duel(state))
    for _, id in ipairs({1, 3, 0}) do
        local result, _, ready = Rules.Respond(state, id, invite.Id, true, 1)
        equal(result, nil); equal(ready, false)
    end
    equal(invite.Accepted[2], nil); equal(Rules.Get(state, 2), invite)
end)

test("responses require a real boolean and the exact bounded invitation id", function()
    local state = fresh(); local invite = assert(duel(state))
    for _, accept in ipairs({1, "true", {}, "false"}) do local result = Rules.Respond(state, 2, invite.Id, accept, 1); equal(result, nil) end
    for _, id in ipairs({42, {}, string.rep("x", 65), "invite:fake"}) do local result = Rules.Respond(state, 2, id, true, 1); equal(result, nil) end
    equal(Rules.Get(state, 2), invite)
end)

test("declining releases all teammates including previous acceptances", function()
    local state = fresh(); local invite = assert(Rules.Create(state, 1, "Teams", {1, 2, 3, 4}, 0, available, false))
    Rules.Respond(state, 2, invite.Id, true, 1)
    local result, reason, ready = Rules.Respond(state, 4, invite.Id, false, 2)
    equal(result, invite); equal(reason, "Declined"); equal(ready, false)
    released(state, {1, 2, 3, 4})
end)

test("only host can cancel and canceled invitations cannot be accepted", function()
    local state = fresh(); local invite = assert(duel(state))
    equal(Rules.Cancel(state, 2, invite.Id), false); equal(Rules.Get(state, 2), invite)
    equal(Rules.Cancel(state, 1, invite.Id), true); released(state, {1, 2})
    local result, _, ready = Rules.Respond(state, 2, invite.Id, true, 1)
    equal(result, nil); equal(ready, false)
end)

test("host cooldown lasts fifteen seconds after cancellation", function()
    local state = fresh(); local invite = assert(duel(state, 10))
    Rules.Cancel(state, 1, invite.Id); equal(Rules.CooldownUntil(state, 1), 25)
    local result, reason = duel(state, 24.999); equal(result, nil); equal(reason, "InviteCooldown")
    assert(duel(state, 25)); equal(Rules.CooldownUntil(state, 1), 40)
end)

test("invalid requests do not consume the host's invitation cooldown", function()
    local state = fresh()
    equal(Rules.Create(state, 1, "Duel", {1, 99}, 0, available, false), nil)
    equal(Rules.CooldownUntil(state, 1), 0); assert(duel(state))
end)

test("a reserved player cannot receive or host a second invitation", function()
    local state = fresh(); local invite = assert(duel(state))
    local result, reason = Rules.Create(state, 3, "Duel", {3, 2}, 1, available, false)
    equal(result, nil); equal(reason, "PlayerBusy")
    result, reason = Rules.Create(state, 2, "Duel", {2, 4}, 1, available, false)
    equal(result, nil); equal(reason, "PlayerBusy"); equal(Rules.Get(state, 2), invite)
end)

test("expiration at twenty five seconds releases reservations and refuses stale acceptance", function()
    local state = fresh(); local invite = assert(duel(state))
    equal(Rules.Expire(state, 24.999), 0)
    local result, reason, ready = Rules.Respond(state, 2, invite.Id, true, 25)
    equal(result, nil); equal(reason, "Expired"); equal(ready, false); released(state, {1, 2})
    assert(duel(state, 25))
end)

test("periodic expiration counts invitations rather than player slots", function()
    local state = fresh(); assert(duel(state))
    assert(Rules.Create(state, 3, "Duel", {3, 4}, 0, available, false))
    equal(Rules.Expire(state, 25), 2); released(state, {1, 2, 3, 4}); equal(Rules.Expire(state, 25), 0)
end)

test("leaving from any invitation slot releases every member", function()
    for _, leaving in ipairs({1, 2, 3, 4}) do
        local state = fresh(); assert(Rules.Create(state, 1, "Teams", {1, 2, 3, 4}, 0, available, false))
        equal(Rules.RemovePlayer(state, leaving), true); released(state, {1, 2, 3, 4})
        equal(Rules.RemovePlayer(state, leaving), false)
    end
end)

test("self selection, duplicate teammates and incomplete teams are rejected", function()
    for _, members in ipairs({{1, 1}, {1, 2, 2, 4}, {1, 2, 3}, {1, 2, 3, 4, 5}, {2, 1}}) do
        local state = fresh(); local mode = #members == 2 and "Duel" or "Teams"
        equal(Rules.Create(state, 1, mode, members, 0, available, false), nil)
        equal(next(state.Invites), nil); equal(next(state.Reserved), nil)
    end
    local state = fresh()
    equal(Rules.Create(state, 1, "Teams", {[1] = 1, [3] = 3, [4] = 4}, 0, available, false), nil)
    equal(next(state.Reserved), nil)
    equal(Rules.CooldownUntil(state, 1), 0, "missing ally must not consume cooldown")
end)

test("malformed ids and unknown modes cannot create invitations", function()
    for _, id in ipairs({0, 1.5, math.huge, -math.huge, 0 / 0, "2", {}}) do
        local state = fresh(); equal(Rules.Create(state, 1, "Duel", {1, id}, 0, available, false), nil)
    end
    local state = fresh()
    equal(Rules.Create(state, 1, "Farm", {1, 2}, 0, available, false), nil)
    equal(Rules.Create(state, 0, "Duel", {0, 2}, 0, available, false), nil)
    equal(Rules.Create(state, 1, "Duel", "1,2", 0, available, false), nil)
end)

test("Studio negative user ids remain valid real player identifiers", function()
    local state = fresh(); assert(Rules.Create(state, -1, "Duel", {-1, -2}, 0, available, false))
end)

test("arena busy and unavailable players refuse invitations before reservation", function()
    local state = fresh()
    local invite, reason = Rules.Create(state, 1, "Duel", {1, 2}, 0, available, true)
    equal(invite, nil); equal(reason, "ArenaBusy"); equal(next(state.Reserved), nil)
    invite, reason = Rules.Create(state, 1, "Duel", {1, 99}, 0, available, false)
    equal(invite, nil); equal(reason, "PlayerUnavailable"); equal(next(state.Reserved), nil)
end)

test("duplicate consent cannot replay a ready match", function()
    local state = fresh(); local invite = assert(duel(state))
    local _, _, ready = Rules.Respond(state, 2, invite.Id, true, 1); equal(ready, true)
    local result; result, _, ready = Rules.Respond(state, 2, invite.Id, true, 1)
    equal(result, nil); equal(ready, false)
end)

test("clearing pending invitations preserves anti spam cooldown", function()
    local state = fresh(); assert(duel(state)); Rules.Clear(state)
    released(state, {1, 2}); equal(Rules.CooldownUntil(state, 1), 15)
    local invite, reason = duel(state, 1); equal(invite, nil); equal(reason, "InviteCooldown")
end)

print(tostring(passed) .. " invitation tests passed; 0 failed")
