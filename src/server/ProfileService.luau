-- Server-owned cosmetics and currency. DataStore writes use a renewable session
-- lease; a failed/contended load never becomes a writable default profile.
local shared = game:GetService("ReplicatedStorage"):WaitForChild("MedievalShared")
local Config = require(shared.Config)
local Catalog = require(shared.Catalog)
local Rules = require(shared.ProfileRules)

local ProfileService = {}
ProfileService.__index = ProfileService

local function copyOwned(owned)
    local result = {}
    for id, value in pairs(owned) do if value == true then result[id] = true end end
    return result
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function ProfileService.new(remotes, deps)
    deps = deps or {}
    local studio = deps.IsStudio
    if studio == nil then studio = game:GetService("RunService"):IsStudio() end
    local published = deps.IsPublished
    if published == nil then published = game.GameId ~= 0 end
    local sessionId = deps.SessionId
    if not sessionId then sessionId = game:GetService("HttpService"):GenerateGUID(false) end
    local store = deps.Store
    if store == nil and published then
        local ok, value = pcall(function()
            return game:GetService("DataStoreService"):GetDataStore(Config.Persistence.StoreName)
        end)
        if ok then store = value end
    end
    return setmetatable({
        Remotes = remotes, Store = store, IsStudio = studio, IsPublished = published,
        Clock = deps.Clock or os.clock, Timestamp = deps.Timestamp or os.time,
        Spawn = deps.Spawn or task.spawn, Wait = deps.Wait or task.wait,
        SessionId = sessionId, Counter = 0, Records = {}, AllEntries = {},
        AwardedMatches = {}, Closing = false,
    }, ProfileService)
end

function ProfileService:_current(entry)
    return self.Records[entry.Player] == entry and not entry.Removed
end

function ProfileService:_attributes(entry)
    if not self:_current(entry) then return end
    local player, data = entry.Player, entry.Data
    player:SetAttribute("Coins", data and data.Coins or 0)
    player:SetAttribute("EquippedSword", data and data.EquippedSword or Catalog.DefaultSword)
    player:SetAttribute("FactionId", data and data.FactionId or Catalog.DefaultFaction)
    player:SetAttribute("SaveMode", entry.Mode)
    player:SetAttribute("ProfileLoaded", entry.Loaded == true)
end

function ProfileService:SendProfile(player)
    local entry = self.Records[player]
    if not entry or not self.Remotes.Profile then return end
    local data = entry.Data
    self.Remotes.Profile:FireClient(player, {
        Loaded = entry.Loaded == true, Coins = data and data.Coins or 0,
        OwnedSwords = data and copyOwned(data.OwnedSwords) or {},
        EquippedSword = data and data.EquippedSword or Catalog.DefaultSword,
        FactionId = data and data.FactionId or Catalog.DefaultFaction,
        Wins = data and data.Wins or 0, Losses = data and data.Losses or 0,
        SaveMode = entry.Mode, Message = entry.Message,
    })
end

function ProfileService:_publish(entry)
    if not self:_current(entry) then return end
    self:_attributes(entry)
    self:SendProfile(entry.Player)
end

function ProfileService:_unavailable(entry, message)
    entry.Loaded, entry.Mode, entry.Lost = false, "Unavailable", true
    entry.Message = message
    self:_publish(entry)
end

function ProfileService:_session(entry)
    entry.Data, entry.Loaded, entry.Mode = Rules.New(Catalog), true, "Session"
    entry.Message = "Mode session Studio : pieces et achats non sauvegardes."
    self:_publish(entry)
end

function ProfileService:_leaseValid(entry)
    return not entry.Lost and entry.LeaseUntil ~= nil and self.Timestamp() < entry.LeaseUntil
end

function ProfileService:_usable(entry)
    if not entry or not entry.Loaded or entry.Removed or entry.Closing or self.Closing then return false end
    if entry.Mode == "Persistent" and not self:_leaseValid(entry) then
        self:_unavailable(entry, "Session expiree : reconnectez-vous pour proteger vos donnees.")
        return false
    end
    return entry.Mode == "Persistent" or entry.Mode == "Session"
end

function ProfileService:_load(entry)
    if not self.Store or not self.IsPublished then
        entry.Loading = false
        if self.IsStudio then
            if self:_current(entry) and not self.Closing then self:_session(entry) end
        else
            self:_unavailable(entry, "Sauvegarde indisponible. Reconnectez-vous plus tard.")
        end
        if entry.Removed or self.Closing then self.AllEntries[entry] = nil end
        return
    end
    local result, loaded, busy = nil, false, false
    for attempt = 1, 3 do
        if entry.Removed or self.Closing then break end
        busy = false
        local ok, value = pcall(function()
            return self.Store:UpdateAsync(entry.Key, function(old)
                local now = self.Timestamp()
                local lease = type(old) == "table" and old.Lease or nil
                if type(lease) == "table" and type(lease.Owner) == "string"
                    and lease.Owner ~= entry.Owner and finite(lease.ExpiresAt) and lease.ExpiresAt > now then
                    busy = true
                    return nil
                end
                -- No defaults are written after a failed read. This transform
                -- creates defaults only as part of a successful atomic load.
                local raw = type(old) == "table" and (old.Profile or old) or nil
                return { Version = 1, Profile = Rules.Sanitize(raw, Catalog),
                    Lease = { Owner = entry.Owner, ExpiresAt = now + Config.Persistence.LeaseSeconds } }
            end)
        end)
        if ok then
            result = value
            loaded = type(result) == "table" and type(result.Lease) == "table" and result.Lease.Owner == entry.Owner
            break
        end
        if attempt < 3 then self.Wait(attempt) end
    end
    entry.Loading = false
    if loaded then
        entry.Data = Rules.Sanitize(result.Profile, Catalog)
        entry.LeaseUntil = result.Lease.ExpiresAt
        entry.Loaded, entry.Mode, entry.Lost = true, "Persistent", false
        entry.Message = "Progression sauvegardee entre les sessions."
        entry.LastAttemptAt = self.Clock()
        if not self:_current(entry) or self.Closing then
            entry.Closing = true
            self:_save(entry, true)
        else
            self:_publish(entry)
        end
    elseif entry.Removed or self.Closing then
        self.AllEntries[entry] = nil
    elseif busy then
        self:_unavailable(entry, "Profil deja ouvert sur un autre serveur. Reconnectez-vous dans quelques minutes.")
    elseif self.IsStudio then
        self:_session(entry)
    else
        self:_unavailable(entry, "Chargement impossible : aucun achat ni remplacement de votre sauvegarde.")
    end
end

function ProfileService:AddPlayer(player)
    if self.Closing or self.Records[player] then return end
    self.Counter += 1
    local entry = {
        Player = player, Key = "u_" .. tostring(player.UserId), Owner = self.SessionId .. ":" .. tostring(self.Counter),
        Loaded = false, Loading = true, Mode = "Unavailable", Message = "Chargement de votre progression...",
        Revision = 0, SavedRevision = 0, LastAttemptAt = self.Clock(),
    }
    self.Records[player], self.AllEntries[entry] = entry, true
    self:_publish(entry)
    self.Spawn(function() self:_load(entry) end)
end

function ProfileService:_save(entry, release)
    if release then entry.ReleaseRequested = true end
    if entry.Saving then return end
    if entry.Mode ~= "Persistent" or not entry.Data or entry.Lost then
        if entry.Removed or entry.Closing then self.AllEntries[entry] = nil end
        return
    end
    entry.Saving = true
    entry.LastAttemptAt = self.Clock()
    self.Spawn(function()
        repeat
            -- Capture before yielding. Concurrent purchases update the live
            -- object, never this write; a subsequent release saves the latest.
            local snapshot = Rules.Sanitize(entry.Data, Catalog)
            local revision = entry.Revision
            local releasing = entry.ReleaseRequested == true
            local saved, leaseLost, newLease = false, false, nil
            for attempt = 1, 3 do
                if entry.Lost then leaseLost = true; break end
                local ok, value = pcall(function()
                    return self.Store:UpdateAsync(entry.Key, function(old)
                        local lease = type(old) == "table" and old.Lease or nil
                        local now = self.Timestamp()
                        if entry.Lost or type(lease) ~= "table" or lease.Owner ~= entry.Owner
                            or not finite(lease.ExpiresAt) or lease.ExpiresAt <= now then
                            leaseLost = true
                            return nil
                        end
                        local record = { Version = 1, Profile = snapshot }
                        if not releasing then
                            record.Lease = { Owner = entry.Owner, ExpiresAt = now + Config.Persistence.LeaseSeconds }
                        end
                        return record
                    end)
                end)
                if ok then
                    saved = type(value) == "table" and not leaseLost
                    if saved and not releasing then
                        saved = type(value.Lease) == "table" and value.Lease.Owner == entry.Owner
                        if saved then newLease = value.Lease.ExpiresAt end
                    end
                    break
                end
                if attempt < 3 then self.Wait(attempt) end
            end
            if leaseLost then
                self:_unavailable(entry, "Session transferee ou expiree. Reconnectez-vous pour proteger vos donnees.")
            elseif saved then
                entry.SavedRevision = revision
                if newLease then entry.LeaseUntil = newLease end
                entry.Message = "Progression sauvegardee entre les sessions."
                if releasing then
                    entry.Released = true
                    self.AllEntries[entry] = nil
                end
            else
                entry.Message = "Sauvegarde temporairement indisponible ; nouvelle tentative automatique."
                warn("[Fer & Fioles] Echec de sauvegarde du profil " .. tostring(entry.Player.UserId))
            end
            self:_publish(entry)
            -- A release requested while the previous write was in flight must
            -- run after it, with the newest revision, never race that write.
            -- Even a failed autosave may have an older snapshot than a leave
            -- queued during it. Give that release its own latest-data write.
            if releasing or entry.Lost or not entry.ReleaseRequested then break end
        until false
        entry.Saving = false
        if entry.Removed or entry.Closing then self.AllEntries[entry] = nil end
    end)
end

function ProfileService:RemovePlayer(player)
    local entry = self.Records[player]
    if not entry then return end
    entry.Removed, entry.Closing = true, true
    self.Records[player] = nil
    if not entry.Loading then self:_save(entry, true) end
end

function ProfileService:HandleAction(player, action, payload)
    if action ~= "BuySword" and action ~= "EquipSword" and action ~= "ChooseFaction" then return false, "UnknownAction" end
    if type(payload) ~= "table" then return false, "InvalidPayload" end
    local entry = self.Records[player]
    if not self:_usable(entry) then return false, "ProfileUnavailable" end
    if player:GetAttribute("Activity") ~= "Lobby" then return false, "NotInLobby" end
    local accepted, reason
    if action == "BuySword" then accepted, reason = Rules.Buy(entry.Data, payload.SwordId, Catalog)
    elseif action == "EquipSword" then accepted, reason = Rules.Equip(entry.Data, payload.SwordId, Catalog)
    else accepted, reason = Rules.ChooseFaction(entry.Data, payload.FactionId, Catalog) end
    if accepted then entry.Revision += 1; self:_publish(entry) end
    return accepted, reason
end

function ProfileService:AwardMatch(matchId, roster, winner)
    if type(matchId) ~= "string" or #matchId == 0 or #matchId > 128 then return false, "InvalidMatch" end
    if self.AwardedMatches[matchId] then return false, "AlreadyRewarded" end
    if winner ~= nil and not Config.Teams[winner] then return false, "UnknownTeam" end
    if type(roster) ~= "table" then return false, "InvalidRoster" end
    local members = roster.Members or roster
    local recipients, seen, teams = {}, {}, {}
    for _, member in pairs(members) do
        if type(member) ~= "table" or member.IsBot == true or not Config.Teams[member.TeamId] then return false, "InvalidRoster" end
        local entry = self.Records[member.Id]
        if seen[member.Id] or not self:_usable(entry) then return false, "ProfileUnavailable" end
        seen[member.Id], teams[member.TeamId] = true, true
        if entry.Data.RewardedMatches[matchId] then return false, "AlreadyRewarded" end
        table.insert(recipients, { Entry = entry, Outcome = winner == nil and "Draw" or (member.TeamId == winner and "Win" or "Loss") })
    end
    local teamCount = 0
    for _ in pairs(teams) do teamCount += 1 end
    if #recipients < 2 or teamCount ~= 2 or (winner and not teams[winner]) then return false, "InvalidRoster" end
    -- Validation above and all balance mutations below are synchronous.
    -- There is no remote for awarding coins, and no await between accounts.
    for _, recipient in ipairs(recipients) do
        Rules.Reward(recipient.Entry.Data, matchId, recipient.Outcome, Config.Rewards)
        recipient.Entry.Revision += 1
    end
    self.AwardedMatches[matchId] = true
    for _, recipient in ipairs(recipients) do self:_publish(recipient.Entry) end
    return true
end

function ProfileService:Step(_dt)
    if self.Closing then return end
    local now = self.Clock()
    for _, entry in pairs(self.Records) do
        if entry.Loaded and entry.Mode == "Persistent" then
            if not self:_leaseValid(entry) then
                self:_unavailable(entry, "Session expiree : reconnectez-vous pour proteger vos donnees.")
            elseif not entry.Saving and now - entry.LastAttemptAt >= Config.Persistence.AutosaveSeconds then
                self:_save(entry, false)
            end
        end
    end
end

function ProfileService:Close()
    if self.Closing then return end
    self.Closing = true
    for entry in pairs(self.AllEntries) do
        entry.Closing = true
        if not entry.Loading then self:_save(entry, true) end
    end
    local deadline = self.Clock() + 25
    while next(self.AllEntries) and self.Clock() < deadline do self.Wait(0.05) end
    if next(self.AllEntries) then warn("[Fer & Fioles] Fermeture avant la fin de toutes les sauvegardes ; les baux expireront.") end
end

return ProfileService
