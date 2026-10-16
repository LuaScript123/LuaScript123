local Rules = require("../src/shared/ProfileRules")
local Catalog = require("../src/shared/Catalog")
local Config = require("../src/shared/Config")
local passed = 0
local function equal(a, b, message) assert(a == b, (message or "unexpected value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, callback) callback(); passed += 1; print("PASS " .. name) end
local rewards = {Win = 50, Loss = 10, Draw = 10}
local function fresh() return Rules.New(Catalog) end

test("new players receive one free sword and independent zero coin profiles", function()
    local a, b = fresh(), fresh()
    equal(a.Coins, 0); equal(a.Wins, 0); equal(a.Losses, 0)
    equal(a.EquippedSword, Catalog.DefaultSword); equal(a.FactionId, Catalog.DefaultFaction)
    equal(a.OwnedSwords[Catalog.DefaultSword], true)
    a.OwnedSwords.Korblox = true; equal(b.OwnedSwords.Korblox, nil)
    a.RewardedMatches.test = true; equal(b.RewardedMatches.test, nil)
end)

test("insufficient balance cannot buy or equip a cosmetic", function()
    local profile = fresh()
    local accepted, reason = Rules.Buy(profile, "Redcliff", Catalog)
    equal(accepted, false); equal(reason, "InsufficientCoins"); equal(profile.Coins, 0)
    equal(profile.OwnedSwords.Redcliff, nil); equal(Rules.Equip(profile, "Redcliff", Catalog), false)
    equal(profile.EquippedSword, Catalog.DefaultSword)
end)

test("purchases deduct the trusted catalog price exactly once", function()
    local profile = fresh(); local price = Catalog.Swords.Korblox.Price
    profile.Coins = price + 17
    assert(Rules.Buy(profile, "Korblox", Catalog)); equal(profile.Coins, 17); equal(profile.OwnedSwords.Korblox, true)
    local accepted, reason = Rules.Buy(profile, "Korblox", Catalog)
    equal(accepted, false); equal(reason, "AlreadyOwned"); equal(profile.Coins, 17)
    assert(Rules.Equip(profile, "Korblox", Catalog)); equal(profile.EquippedSword, "Korblox")
end)

test("buying does not equip an unchosen sword", function()
    local profile = fresh(); profile.Coins = Catalog.Swords.Redcliff.Price
    assert(Rules.Buy(profile, "Redcliff", Catalog)); equal(profile.EquippedSword, Catalog.DefaultSword)
    assert(Rules.Equip(profile, "Redcliff", Catalog)); equal(profile.EquippedSword, "Redcliff")
    assert(Rules.Equip(profile, Catalog.DefaultSword, Catalog)); equal(profile.EquippedSword, Catalog.DefaultSword)
end)

test("client shaped objects and unknown cosmetic ids grant nothing", function()
    local profile = fresh(); profile.Coins = 1000
    for _, id in ipairs({"Unknown", "", string.rep("x", 129), 4, false, {SwordId = "Overseer", Price = -100}}) do
        equal(Rules.Buy(profile, id, Catalog), false)
        equal(Rules.Equip(profile, id, Catalog), false)
        equal(Rules.ChooseFaction(profile, id, Catalog), false)
    end
    equal(profile.Coins, 1000); equal(profile.EquippedSword, Catalog.DefaultSword)
end)

test("all four factions are free and leave coins and combat stats unchanged", function()
    local profile = fresh(); local damage, range = Config.Combat.Damage, Config.Combat.AttackRange
    for _, id in ipairs({"Redcliff", "Korblox", "Greywolf", "Overseer"}) do
        assert(Catalog.Factions[id]); assert(Rules.ChooseFaction(profile, id, Catalog))
        equal(profile.FactionId, id); equal(profile.Coins, 0)
        equal(Catalog.Factions[id].Damage, nil); equal(Catalog.Factions[id].AttackRange, nil)
    end
    equal(Config.Combat.Damage, damage); equal(Config.Combat.AttackRange, range)
    equal(profile.Damage, nil); equal(profile.MaxStamina, nil)
end)

test("every purchasable sword contains appearance rather than combat overrides", function()
    local forbidden = {"Damage", "AttackDamage", "AttackRange", "Range", "AttackCost", "AttackCooldown", "MaxStamina", "WalkSpeed"}
    for _, id in ipairs(Catalog.SwordOrder) do
        local sword = assert(Catalog.Swords[id])
        for _, key in ipairs(forbidden) do equal(sword[key], nil, id .. " has a combat override") end
    end
end)

test("sanitization restores the starter and rejects unknown or unowned equipment", function()
    local profile = Rules.Sanitize({Coins = 25, OwnedSwords = {Korblox = true, Overseer = 1, Exploit = true}, EquippedSword = "Overseer", FactionId = "Exploit"}, Catalog)
    equal(profile.Coins, 25); equal(profile.OwnedSwords[Catalog.DefaultSword], true)
    equal(profile.OwnedSwords.Korblox, true); equal(profile.OwnedSwords.Overseer, nil); equal(profile.OwnedSwords.Exploit, nil)
    equal(profile.EquippedSword, Catalog.DefaultSword); equal(profile.FactionId, Catalog.DefaultFaction)
end)

test("valid saved ownership and chosen faction survive loading without aliasing", function()
    local raw = {Coins = 47, Wins = 2, Losses = 1, OwnedSwords = {Korblox = true}, EquippedSword = "Korblox", FactionId = "Greywolf"}
    local profile = Rules.Sanitize(raw, Catalog)
    equal(profile.Coins, 47); equal(profile.Wins, 2); equal(profile.Losses, 1)
    equal(profile.EquippedSword, "Korblox"); equal(profile.FactionId, "Greywolf")
    profile.OwnedSwords.Redcliff = true; equal(raw.OwnedSwords.Redcliff, nil)
end)

test("malformed saved profiles and nonfinite money cannot enter commerce", function()
    for _, raw in ipairs({false, 42, "profile", {}, {Coins = -100}, {Coins = 0/0}, {Coins = math.huge}, {Coins = "1000000"}}) do
        local profile = Rules.Sanitize(raw, Catalog); equal(profile.Coins, 0)
        equal(profile.EquippedSword, Catalog.DefaultSword)
    end
    local profile = Rules.Sanitize({Coins = 13.9, Wins = -1, Losses = math.huge}, Catalog)
    equal(profile.Coins, 13); equal(profile.Wins, 0); equal(profile.Losses, 0)
    equal(Rules.Sanitize({Coins = 1e30}, Catalog).Coins, 2147483647)
end)

test("completed match rewards use server outcome amounts and update the correct statistics", function()
    local profile = fresh()
    assert(Rules.Reward(profile, "match:win", "Win", rewards)); equal(profile.Coins, 50); equal(profile.Wins, 1); equal(profile.Losses, 0)
    assert(Rules.Reward(profile, "match:loss", "Loss", rewards)); equal(profile.Coins, 60); equal(profile.Wins, 1); equal(profile.Losses, 1)
    assert(Rules.Reward(profile, "match:draw", "Draw", rewards)); equal(profile.Coins, 70); equal(profile.Wins, 1); equal(profile.Losses, 1)
end)

test("rewarding the same match twice cannot mint coins even with a changed outcome", function()
    local profile = fresh(); assert(Rules.Reward(profile, "match:1", "Win", rewards))
    local accepted, reason = Rules.Reward(profile, "match:1", "Loss", rewards)
    equal(accepted, false); equal(reason, "AlreadyRewarded"); equal(profile.Coins, 50)
    equal(profile.Wins, 1); equal(profile.Losses, 0)
end)

test("saved reward history refuses replay after a load", function()
    local profile = fresh(); assert(Rules.Reward(profile, "match:saved", "Win", rewards))
    local restored = Rules.Sanitize(profile, Catalog)
    equal(Rules.Reward(restored, "match:saved", "Win", rewards), false); equal(restored.Coins, 50)
    equal(#restored.RewardOrder, 1); equal(restored.RewardedMatches["match:saved"], true)
end)

test("reward history remains bounded and sanitized against duplicate journal entries", function()
    local profile = fresh()
    for i = 1, 105 do assert(Rules.Reward(profile, "match:" .. tostring(i), "Draw", rewards)) end
    equal(#profile.RewardOrder, 100); equal(profile.RewardedMatches["match:1"], nil)
    equal(profile.RewardedMatches["match:105"], true); equal(profile.Coins, 1050)
    table.insert(profile.RewardOrder, "match:105"); table.insert(profile.RewardOrder, {})
    local restored = Rules.Sanitize(profile, Catalog)
    assert(#restored.RewardOrder <= 100)
    local seen = {}; for _, id in ipairs(restored.RewardOrder) do equal(seen[id], nil); seen[id] = true end
end)

test("invalid rewards or match ids cannot reserve a ledger entry or change balances", function()
    local profile = fresh()
    for _, id in ipairs({"", string.rep("x", 129), 12, {}}) do equal(Rules.Reward(profile, id, "Win", rewards), false) end
    equal(Rules.Reward(profile, "a", "ClientWinner", rewards), false)
    for _, amount in ipairs({-10, 1.5, math.huge, 0/0}) do equal(Rules.Reward(profile, "a", "Win", {Win = amount}), false) end
    equal(profile.Coins, 0); equal(next(profile.RewardedMatches), nil)
    assert(Rules.Reward(profile, "a", "Win", rewards))
end)

print(tostring(passed) .. " profile rule tests passed; 0 failed")
