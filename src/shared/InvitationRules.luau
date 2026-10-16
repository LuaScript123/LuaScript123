-- Pure invitation state. User IDs are integers (Studio uses negative IDs).
-- All clocks are monotone and supplied by the caller; no Roblox dependencies.
local InvitationRules = {}

local function validId(id)
    return type(id) == "number" and id == id and id ~= math.huge and id ~= -math.huge
        and id ~= 0 and id % 1 == 0
end

local function release(state, invite)
    state.Invites[invite.Id] = nil
    for _, id in ipairs(invite.Members) do
        if state.Reserved[id] == invite.Id then state.Reserved[id] = nil end
    end
end

function InvitationRules.New(cooldownSeconds, expiresSeconds)
    return {
        CooldownSeconds = cooldownSeconds or 15, ExpiresSeconds = expiresSeconds or 25,
        Invites = {}, Reserved = {}, Cooldowns = {}, Serial = 0,
    }
end

function InvitationRules.Get(state, userId)
    local inviteId = state.Reserved[userId]
    return inviteId and state.Invites[inviteId] or nil
end

function InvitationRules.CooldownUntil(state, userId)
    return state.Cooldowns[userId] or 0
end

function InvitationRules.Expire(state, now)
    local expired = {}
    for _, invite in pairs(state.Invites) do
        if now >= invite.ExpiresAt then table.insert(expired, invite) end
    end
    for _, invite in ipairs(expired) do release(state, invite) end
    return #expired
end

function InvitationRules.Create(state, hostId, mode, memberIds, now, available, arenaBusy)
    InvitationRules.Expire(state, now)
    if arenaBusy then return nil, "ArenaBusy" end
    if not validId(hostId) then return nil, "InvalidPlayer" end
    if now < InvitationRules.CooldownUntil(state, hostId) then return nil, "InviteCooldown" end
    local size = mode == "Duel" and 2 or (mode == "Teams" and 4 or nil)
    if not size or type(memberIds) ~= "table" or #memberIds ~= size or memberIds[1] ~= hostId then
        return nil, "InvalidMembers"
    end
    local seen, members = {}, {}
    for index = 1, size do
        local id = memberIds[index]
        if not validId(id) or seen[id] then return nil, "InvalidMembers" end
        if state.Reserved[id] then return nil, "PlayerBusy" end
        if not available(id) then return nil, "PlayerUnavailable" end
        seen[id], members[index] = true, id
    end
    state.Serial += 1
    local invite = {
        Id = "invite:" .. tostring(state.Serial), HostId = hostId, Mode = mode,
        Members = members, Accepted = { [hostId] = true }, ExpiresAt = now + state.ExpiresSeconds,
    }
    state.Invites[invite.Id] = invite
    for _, id in ipairs(members) do state.Reserved[id] = invite.Id end
    state.Cooldowns[hostId] = now + state.CooldownSeconds
    return invite, nil
end

function InvitationRules.Respond(state, userId, inviteId, accept, now)
    if type(inviteId) ~= "string" or #inviteId > 64 or type(accept) ~= "boolean" then
        return nil, "InvalidResponse", false
    end
    local invite = state.Invites[inviteId]
    if not invite or state.Reserved[userId] ~= inviteId or userId == invite.HostId then
        return nil, "UnknownInvite", false
    end
    if now >= invite.ExpiresAt then
        release(state, invite)
        return nil, "Expired", false
    end
    if not accept then
        release(state, invite)
        return invite, "Declined", false
    end
    invite.Accepted[userId] = true
    for _, id in ipairs(invite.Members) do
        if not invite.Accepted[id] then return invite, nil, false end
    end
    -- The caller consumes this result synchronously before yielding. Removing
    -- reservations here prevents an accepted invitation from becoming stale.
    release(state, invite)
    return invite, nil, true
end

function InvitationRules.Cancel(state, hostId, inviteId)
    if type(inviteId) ~= "string" or #inviteId > 64 then return false, "UnknownInvite" end
    local invite = state.Invites[inviteId]
    if not invite or invite.HostId ~= hostId then return false, "UnknownInvite" end
    release(state, invite)
    return true, nil
end

function InvitationRules.RemovePlayer(state, userId)
    local invite = InvitationRules.Get(state, userId)
    if invite then release(state, invite) end
    state.Cooldowns[userId] = nil
    return invite ~= nil
end

function InvitationRules.Clear(state)
    state.Invites, state.Reserved = {}, {}
end

return InvitationRules
