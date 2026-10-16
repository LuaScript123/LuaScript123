-- Portable, synchronous profile rules. Only the server supplies the catalog,
-- reward values and match IDs; no client amount can enter these functions.
local Rules = {}
local MAX_INTEGER = 2147483647
local REWARD_HISTORY = 100

local function integer(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.max(0, math.min(MAX_INTEGER, math.floor(value)))
end

local function validId(value)
    return type(value) == "string" and #value > 0 and #value <= 128
end

function Rules.New(catalog)
    return {
        Version = 1, Coins = 0, OwnedSwords = { [catalog.DefaultSword] = true },
        EquippedSword = catalog.DefaultSword, FactionId = catalog.DefaultFaction,
        Wins = 0, Losses = 0, RewardedMatches = {}, RewardOrder = {},
    }
end

function Rules.Sanitize(raw, catalog)
    local profile = Rules.New(catalog)
    if type(raw) ~= "table" then return profile end
    profile.Coins, profile.Wins, profile.Losses = integer(raw.Coins), integer(raw.Wins), integer(raw.Losses)
    if type(raw.OwnedSwords) == "table" then
        for id in pairs(catalog.Swords) do
            if raw.OwnedSwords[id] == true then profile.OwnedSwords[id] = true end
        end
    end
    if validId(raw.EquippedSword) and profile.OwnedSwords[raw.EquippedSword] then
        profile.EquippedSword = raw.EquippedSword
    end
    if validId(raw.FactionId) and catalog.Factions[raw.FactionId] then profile.FactionId = raw.FactionId end
    -- Persist a bounded, ordered replay ledger. The service also deduplicates
    -- all matches for the lifetime of its server, without evicting old IDs.
    if type(raw.RewardOrder) == "table" and type(raw.RewardedMatches) == "table" then
        local start = math.max(1, #raw.RewardOrder - REWARD_HISTORY + 1)
        for index = start, #raw.RewardOrder do
            local id = raw.RewardOrder[index]
            if validId(id) and raw.RewardedMatches[id] == true and not profile.RewardedMatches[id] then
                profile.RewardedMatches[id] = true
                table.insert(profile.RewardOrder, id)
            end
        end
    end
    return profile
end

function Rules.Buy(profile, swordId, catalog)
    if not validId(swordId) or not catalog.Swords[swordId] then return false, "UnknownSword" end
    if profile.OwnedSwords[swordId] then return false, "AlreadyOwned" end
    local price = catalog.Swords[swordId].Price
    if type(price) ~= "number" or price < 0 or price % 1 ~= 0 or price > MAX_INTEGER then return false, "InvalidPrice" end
    if profile.Coins < price then return false, "InsufficientCoins" end
    profile.Coins -= price
    profile.OwnedSwords[swordId] = true
    return true
end

function Rules.Equip(profile, swordId, catalog)
    if not validId(swordId) or not catalog.Swords[swordId] then return false, "UnknownSword" end
    if not profile.OwnedSwords[swordId] then return false, "NotOwned" end
    profile.EquippedSword = swordId
    return true
end

function Rules.ChooseFaction(profile, factionId, catalog)
    if not validId(factionId) or not catalog.Factions[factionId] then return false, "UnknownFaction" end
    profile.FactionId = factionId
    return true
end

function Rules.Reward(profile, matchId, outcome, rewards)
    if not validId(matchId) then return false, "InvalidMatch" end
    if outcome ~= "Win" and outcome ~= "Loss" and outcome ~= "Draw" then return false, "InvalidOutcome" end
    local amount = rewards[outcome]
    if type(amount) ~= "number" or amount < 0 or amount % 1 ~= 0 or amount > MAX_INTEGER then return false, "InvalidReward" end
    if profile.RewardedMatches[matchId] then return false, "AlreadyRewarded" end
    profile.Coins = math.min(MAX_INTEGER, profile.Coins + amount)
    if outcome == "Win" then profile.Wins = math.min(MAX_INTEGER, profile.Wins + 1) end
    if outcome == "Loss" then profile.Losses = math.min(MAX_INTEGER, profile.Losses + 1) end
    profile.RewardedMatches[matchId] = true
    table.insert(profile.RewardOrder, matchId)
    if #profile.RewardOrder > REWARD_HISTORY then
        local oldest = table.remove(profile.RewardOrder, 1)
        profile.RewardedMatches[oldest] = nil
    end
    return true
end

return Rules
