-- Portable roster rules: no Roblox globals, clock, or side effects.
local MatchRules = {}

function MatchRules.New(teamOrder, teamSize)
    assert(type(teamOrder) == "table" and #teamOrder >= 2, "At least two teams are required")
    assert(type(teamSize) == "number" and teamSize >= 1 and teamSize % 1 == 0, "Invalid team size")
    local order, teams = {}, {}
    for _, teamId in ipairs(teamOrder) do
        assert(type(teamId) == "string" and not teams[teamId], "Invalid or duplicate team")
        teams[teamId] = true
        table.insert(order, teamId)
    end
    return { TeamOrder = order, TeamSize = teamSize, Members = {}, Teams = teams, Locked = false, Started = false }
end

function MatchRules.Get(roster, id)
    return roster.Members[id]
end

function MatchRules.Add(roster, id, teamId)
    if roster.Locked then return false, "Locked" end
    if id == nil or (type(id) == "number" and id ~= id) then return false, "InvalidId" end
    if roster.Members[id] then return false, "Duplicate" end
    if not roster.Teams[teamId] then return false, "UnknownTeam" end
    local count = 0
    for _, member in pairs(roster.Members) do
        if member.TeamId == teamId then count += 1 end
    end
    if count >= roster.TeamSize then return false, "TeamFull" end
    roster.Members[id] = { Id = id, TeamId = teamId, Ready = false, Eliminated = false }
    return true
end

function MatchRules.Lock(roster)
    if roster.Locked then return false, "AlreadyLocked" end
    local counts = {}
    for _, teamId in ipairs(roster.TeamOrder) do counts[teamId] = 0 end
    for _, member in pairs(roster.Members) do counts[member.TeamId] += 1 end
    for _, teamId in ipairs(roster.TeamOrder) do
        if counts[teamId] ~= roster.TeamSize then return false, "Incomplete" end
    end
    roster.Locked = true
    return true
end

function MatchRules.SetReady(roster, id, ready)
    local member = roster.Members[id]
    if not member then return false, "UnknownMember" end
    if roster.Started then return false, "Started" end
    if member.Eliminated then return false, "Eliminated" end
    member.Ready = ready == true
    return true
end

function MatchRules.IsReady(roster)
    if not roster.Locked then return false end
    for _, member in pairs(roster.Members) do
        if not member.Ready or member.Eliminated then return false end
    end
    return true
end

function MatchRules.Begin(roster)
    if roster.Started then return false, "AlreadyStarted" end
    if not MatchRules.IsReady(roster) then return false, "NotReady" end
    roster.Started = true
    return true
end

function MatchRules.Eliminate(roster, id)
    local member = roster.Members[id]
    if not member then return false, "UnknownMember" end
    if member.Eliminated then return false, "AlreadyEliminated" end
    member.Eliminated = true
    return true
end

function MatchRules.CountAlive(roster)
    local alive = {}
    for _, teamId in ipairs(roster.TeamOrder) do alive[teamId] = 0 end
    for _, member in pairs(roster.Members) do
        if not member.Eliminated then alive[member.TeamId] += 1 end
    end
    return alive
end

function MatchRules.Resolve(roster)
    if not roster.Started then return false, nil end
    local alive = MatchRules.CountAlive(roster)
    local remaining, winner = 0, nil
    for _, teamId in ipairs(roster.TeamOrder) do
        if alive[teamId] > 0 then
            remaining += 1
            winner = teamId
        end
    end
    if remaining > 1 then return false, nil end
    return true, winner
end

return MatchRules
