-- Production service loaded unchanged; network/task/datastore boundaries are doubles.
-- This does not simulate Roblox API availability or live DataStore reliability.
local Modules = {}
local shared = {Config = {Name = "Config"}, Catalog = {Name = "Catalog"}, ProfileRules = {Name = "ProfileRules"}}
local replicated = {WaitForChild = function(_, name) assert(name == "MedievalShared"); return shared end}
local game = {GetService = function(_, name) assert(name == "ReplicatedStorage", name); return replicated end}
local require = function(module) return assert(Modules[module.Name], module.Name) end
local warn = function(...) print("EXPECTED WARNING", ...) end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = clone(item) end; return result
end
local function resume(thread)
    local ok, problem = coroutine.resume(thread); assert(ok, tostring(problem))
end
local function spawn(callback)
    local thread = coroutine.create(callback); resume(thread); return thread
end
local function player(id)
    local object = {UserId = id, Attributes = {Activity = "Lobby"}}
    function object:SetAttribute(key, value) self.Attributes[key] = value end
    function object:GetAttribute(key) return self.Attributes[key] end
    return object
end
local function storeDouble()
    local store = {Data = {}, Calls = 0, Writes = 0, Fail = false, HoldNext = false}
    function store:UpdateAsync(key, transform)
        self.Calls += 1
        if self.HoldNext then
            self.HoldNext = false; self.Held = coroutine.running(); coroutine.yield("HeldDataStore")
        end
        if self.Fail then error("simulated datastore outage") end
        local nextValue = transform(clone(self.Data[key]))
        if nextValue == nil then return nil end
        self.Data[key] = clone(nextValue); self.Writes += 1
        return clone(nextValue)
    end
    function store:Complete()
        local thread = assert(self.Held, "no pending store operation"); self.Held = nil; resume(thread)
    end
    return store
end
-- INSERT_REAL_MODULES_HERE
local Service = Modules.ProfileService
local Catalog = Modules.Catalog
local passed = 0
local function equal(a, b, message) assert(a == b, (message or "unexpected value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, callback) callback(); passed += 1; print("PASS " .. name) end
local function context(options)
    options = options or {}
    local ctx = {Clock = 0, Epoch = 1000, Store = storeDouble(), Calls = {}}
    local remote = {FireClient = function(_, who, payload) table.insert(ctx.Calls, {Player = who, Payload = clone(payload)}) end}
    ctx.Service = Service.new({Profile = remote}, {
        Store = ctx.Store, IsStudio = options.Studio == true, IsPublished = options.Published ~= false,
        Clock = function() return ctx.Clock end, Timestamp = function() return ctx.Epoch end,
        Spawn = spawn, Wait = function(dt) ctx.Clock += dt end, SessionId = "test-session",
    })
    function ctx:Add(id, raw)
        if raw then self.Store.Data["u_" .. tostring(id)] = clone(raw) end
        local subject = player(id); self.Service:AddPlayer(subject); return subject
    end
    function ctx:Advance(seconds)
        self.Clock += seconds; self.Epoch += seconds; self.Service:Step(seconds)
    end
    return ctx
end
local function roster(a, b)
    return {Members = {[a] = {Id = a, TeamId = "Dawn", IsBot = false}, [b] = {Id = b, TeamId = "Ember", IsBot = false}}}
end

test("profile loading is asynchronous and commerce waits for the atomic load", function()
    local ctx = context(); ctx.Store.HoldNext = true
    local subject = ctx:Add(1)
    equal(subject:GetAttribute("ProfileLoaded"), false); equal(ctx.Service.Records[subject].Loading, true)
    equal(ctx.Service:HandleAction(subject, "ChooseFaction", {FactionId = "Korblox"}), false)
    ctx.Store:Complete()
    equal(subject:GetAttribute("ProfileLoaded"), true); equal(subject:GetAttribute("SaveMode"), "Persistent")
    equal(ctx.Service.Records[subject].Loading, false)
end)

test("atomic load restores cosmetics and attaches a bounded renewable owner lease", function()
    local ctx = context(); local subject = ctx:Add(2, {Coins = 275, OwnedSwords = {Korblox = true}, EquippedSword = "Korblox", FactionId = "Greywolf"})
    equal(subject:GetAttribute("Coins"), 275); equal(subject:GetAttribute("EquippedSword"), "Korblox")
    equal(subject:GetAttribute("FactionId"), "Greywolf")
    local stored = ctx.Store.Data.u_2
    equal(stored.Profile.Coins, 275); equal(stored.Lease.Owner, "test-session:1")
    equal(stored.Lease.ExpiresAt, ctx.Epoch + 180)
end)

test("a failed production load never saves defaults over a real profile", function()
    local ctx = context(); ctx.Store.Fail = true
    ctx.Store.Data.u_3 = {Profile = {Coins = 999}}
    local subject = ctx:Add(3)
    equal(ctx.Store.Calls, 3); equal(ctx.Store.Writes, 0)
    equal(subject:GetAttribute("ProfileLoaded"), false); equal(subject:GetAttribute("SaveMode"), "Unavailable")
    ctx.Store.Fail = false; ctx:Advance(60); ctx.Service:RemovePlayer(subject)
    equal(ctx.Store.Writes, 0); equal(ctx.Store.Data.u_3.Profile.Coins, 999)
end)

test("unpublished Studio uses explicit session mode without datastore writes", function()
    local ctx = context({Studio = true, Published = false}); local subject = ctx:Add(-1)
    equal(subject:GetAttribute("ProfileLoaded"), true); equal(subject:GetAttribute("SaveMode"), "Session")
    assert(ctx.Service:HandleAction(subject, "ChooseFaction", {FactionId = "Overseer"}))
    ctx:Advance(60); ctx.Service:RemovePlayer(subject); equal(ctx.Store.Calls, 0); equal(ctx.Store.Writes, 0)
end)

test("Studio datastore failure falls back to session without replacing stored progress", function()
    local ctx = context({Studio = true}); ctx.Store.Fail = true
    local subject = ctx:Add(4, {Profile = {Coins = 730}})
    equal(subject:GetAttribute("SaveMode"), "Session"); equal(subject:GetAttribute("ProfileLoaded"), true)
    ctx.Store.Fail = false; ctx:Advance(60); ctx.Service:RemovePlayer(subject)
    equal(ctx.Store.Writes, 0); equal(ctx.Store.Data.u_4.Profile.Coins, 730)
end)

test("a live foreign lease refuses commerce and never writes over the other session", function()
    local ctx = context(); local subject = ctx:Add(5, {Profile = {Coins = 730}, Lease = {Owner = "another-server", ExpiresAt = 1100}})
    equal(subject:GetAttribute("ProfileLoaded"), false); equal(ctx.Store.Writes, 0)
    equal(ctx.Service:HandleAction(subject, "BuySword", {SwordId = "Redcliff"}), false)
    ctx.Service:RemovePlayer(subject); equal(ctx.Store.Writes, 0); equal(ctx.Store.Data.u_5.Lease.Owner, "another-server")
end)

test("shop ignores client amounts and only permits loaded players in the lobby", function()
    local ctx = context(); local a, b = ctx:Add(6), ctx:Add(7)
    equal(ctx.Service:HandleAction(a, "BuySword", {SwordId = "Redcliff", Price = 0, Coins = 1000000}), false)
    equal(a:GetAttribute("Coins"), 0)
    assert(ctx.Service:AwardMatch("fund:1", roster(a, b), "Dawn")); assert(ctx.Service:AwardMatch("fund:2", roster(a, b), "Dawn"))
    a:SetAttribute("Activity", "Battle")
    equal(ctx.Service:HandleAction(a, "BuySword", {SwordId = "Redcliff"}), false)
    a:SetAttribute("Activity", "Lobby")
    assert(ctx.Service:HandleAction(a, "BuySword", {SwordId = "Redcliff", Price = -500}))
    equal(a:GetAttribute("Coins"), 0)
    assert(ctx.Service:HandleAction(a, "EquipSword", {SwordId = "Redcliff"}))
    equal(a:GetAttribute("EquippedSword"), "Redcliff")
    equal(ctx.Service:HandleAction(a, "Reward", {Coins = 1000}), false)
    equal(ctx.Service:HandleAction(a, "BuySword", "Redcliff"), false)
end)

test("match rewards are atomic across eligible humans and reject bot or missing profiles", function()
    local ctx = context(); local a, b = ctx:Add(8), ctx:Add(9)
    local invalid = roster(a, b); invalid.Members[b].IsBot = true
    equal(ctx.Service:AwardMatch("bad", invalid, "Dawn"), false); equal(a:GetAttribute("Coins"), 0)
    invalid = roster(a, player(999)); equal(ctx.Service:AwardMatch("bad", invalid, "Dawn"), false)
    equal(a:GetAttribute("Coins"), 0)
    assert(ctx.Service:AwardMatch("good", roster(a, b), "Dawn"))
    equal(a:GetAttribute("Coins"), 50); equal(b:GetAttribute("Coins"), 10)
    equal(ctx.Service:AwardMatch("good", roster(a, b), "Ember"), false)
    equal(a:GetAttribute("Coins"), 50); equal(b:GetAttribute("Coins"), 10)
end)

test("server lifetime deduplication survives eviction from the persisted reward journal", function()
    local ctx = context({Studio = true, Published = false}); local a, b = ctx:Add(-2), ctx:Add(-3)
    for i = 1, 105 do assert(ctx.Service:AwardMatch("long:" .. tostring(i), roster(a, b), nil)) end
    equal(#ctx.Service.Records[a].Data.RewardOrder, 100)
    equal(ctx.Service:AwardMatch("long:1", roster(a, b), "Dawn"), false)
    equal(a:GetAttribute("Coins"), 1050)
end)

test("autosave renews the lease and leaving releases the latest owned cosmetics", function()
    local ctx = context(); local subject = ctx:Add(10, {Coins = 150})
    assert(ctx.Service:HandleAction(subject, "BuySword", {SwordId = "Korblox"}))
    assert(ctx.Service:HandleAction(subject, "EquipSword", {SwordId = "Korblox"}))
    ctx:Advance(59); equal(ctx.Store.Writes, 1)
    ctx:Advance(1); equal(ctx.Store.Writes, 2); equal(ctx.Store.Data.u_10.Lease.ExpiresAt, ctx.Epoch + 180)
    equal(ctx.Store.Data.u_10.Profile.Coins, 0); equal(ctx.Store.Data.u_10.Profile.EquippedSword, "Korblox")
    ctx.Service:RemovePlayer(subject); equal(ctx.Store.Data.u_10.Lease, nil)
    equal(ctx.Store.Data.u_10.Profile.OwnedSwords.Korblox, true)
end)

test("a purchase during autosave is serialized into the final leave write", function()
    local ctx = context(); local subject = ctx:Add(11, {Coins = 200})
    ctx.Store.HoldNext = true; ctx:Advance(60)
    equal(ctx.Service.Records[subject].Saving, true)
    assert(ctx.Service:HandleAction(subject, "BuySword", {SwordId = "Redcliff"}))
    ctx.Service:RemovePlayer(subject)
    ctx.Store:Complete()
    equal(ctx.Store.Data.u_11.Profile.Coins, 100); equal(ctx.Store.Data.u_11.Profile.OwnedSwords.Redcliff, true)
    equal(ctx.Store.Data.u_11.Lease, nil); equal(ctx.Store.Writes, 3)
end)

test("losing the owner lease during autosave cannot overwrite another server", function()
    local ctx = context(); local subject = ctx:Add(12, {Coins = 200})
    ctx.Store.HoldNext = true; ctx:Advance(60)
    ctx.Store.Data.u_12.Lease.Owner = "new-owner"; ctx.Store.Data.u_12.Profile.Coins = 999
    ctx.Store:Complete()
    equal(subject:GetAttribute("ProfileLoaded"), false); equal(subject:GetAttribute("SaveMode"), "Unavailable")
    equal(ctx.Store.Data.u_12.Profile.Coins, 999); equal(ctx.Store.Writes, 1)
    ctx.Service:RemovePlayer(subject); equal(ctx.Store.Writes, 1)
end)

test("expired owner leases block purchases and are never renewed with stale data", function()
    local ctx = context(); local subject = ctx:Add(13, {Coins = 200})
    ctx.Clock += 181; ctx.Epoch += 181
    equal(ctx.Service:HandleAction(subject, "BuySword", {SwordId = "Redcliff"}), false)
    equal(subject:GetAttribute("ProfileLoaded"), false)
    ctx.Service:Step(181); ctx.Service:RemovePlayer(subject)
    equal(ctx.Store.Writes, 1); equal(ctx.Store.Data.u_13.Profile.Coins, 200)
end)

test("leaving during an in flight load releases its acquired lease safely", function()
    local ctx = context(); ctx.Store.HoldNext = true; local subject = ctx:Add(14)
    ctx.Service:RemovePlayer(subject); ctx.Store:Complete()
    equal(ctx.Service.Records[subject], nil); equal(ctx.Store.Data.u_14.Lease, nil)
    equal(next(ctx.Service.AllEntries), nil)
end)

test("shutdown saves and releases every loaded profile once", function()
    local ctx = context(); local a, b = ctx:Add(15), ctx:Add(16)
    assert(ctx.Service:AwardMatch("shutdown", roster(a, b), "Dawn"))
    ctx.Service:Close(); equal(ctx.Service.Closing, true); equal(next(ctx.Service.AllEntries), nil)
    equal(ctx.Store.Data.u_15.Profile.Coins, 50); equal(ctx.Store.Data.u_16.Profile.Coins, 10)
    equal(ctx.Store.Data.u_15.Lease, nil); equal(ctx.Store.Data.u_16.Lease, nil)
    local writes = ctx.Store.Writes; ctx.Service:Close(); equal(ctx.Store.Writes, writes)
end)

print(tostring(passed) .. " profile service tests passed; 0 failed")
