-- Presentation only: invitations, ownership and every purchase are validated by the server.
local UserInputService = game:GetService("UserInputService")
local LobbyUI = {}
LobbyUI.__index = LobbyUI

local colors = {
	Panel = Color3.fromRGB(25, 29, 34), Inset = Color3.fromRGB(13, 17, 21),
	Text = Color3.fromRGB(245, 236, 217), Muted = Color3.fromRGB(177, 181, 184),
	Gold = Color3.fromRGB(222, 181, 99), Stroke = Color3.fromRGB(101, 91, 72),
	Blue = Color3.fromRGB(75, 151, 222), Red = Color3.fromRGB(218, 91, 65),
}
local function create(kind, properties, parent)
	local object = Instance.new(kind)
	for key, value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end
local function round(object)
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, object)
end
local function label(parent, text, height, color)
	return create("TextLabel", {
		Size = UDim2.new(1, -4, 0, height or 26), BackgroundTransparency = 1,
		Text = text, TextColor3 = color or colors.Text, Font = Enum.Font.GothamMedium,
		TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 42,
	}, parent)
end
local function button(parent, text, callback, properties)
	local props = {
		Size = UDim2.new(1, -4, 0, 38), BackgroundColor3 = colors.Inset,
		BorderSizePixel = 0, Text = text, TextColor3 = colors.Text, Font = Enum.Font.GothamBold,
		TextSize = 13, AutoButtonColor = true, ZIndex = 43,
	}
	for key, value in pairs(properties or {}) do props[key] = value end
	local object = create("TextButton", props, parent)
	round(object)
	object.Activated:Connect(callback)
	return object
end
local function row(parent, height)
	return create("Frame", { Size = UDim2.new(1, -4, 0, height), BackgroundTransparency = 1, ZIndex = 42 }, parent)
end
local function rgb(values)
	return Color3.fromRGB(values[1], values[2], values[3])
end
local function validId(value)
	return type(value) == "number" and value ~= 0 and value % 1 == 0
end

function LobbyUI.new(player, root, action, config, catalog, onMenuChanged)
	local self = setmetatable({
		Player = player, Root = root, Action = action, Config = config, Catalog = catalog,
		OnMenuChanged = onMenuChanged, Activity = player:GetAttribute("Activity") or "Lobby",
		Open = false, Tab = "PvP", Mode = "Duel", Role = "OpponentUserId", Selection = {},
		Lobby = { Players = {} }, Profile = {}, TimerLabels = {}, RenderKey = nil,
		PendingProfileUntil = 0, SendUntil = 0,
	}, LobbyUI)
	self.Header = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(450, 58), BackgroundColor3 = colors.Panel,
		BackgroundTransparency = 0.06, BorderSizePixel = 0, ZIndex = 35,
	}, root)
	round(self.Header)
	self.Coins = label(self.Header, "LOBBY · chargement du profil…", 44, colors.Gold)
	self.Coins.Position = UDim2.fromOffset(13, 7)
	self.Coins.Size = UDim2.new(1, -151, 0, 44)
	self.Toggle = button(self.Header, "MENU PvP", function() self:SetOpen(not self.Open) end, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(123, 36), ZIndex = 36,
	})
	self.Window = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(660, 535), BackgroundColor3 = colors.Panel,
		BackgroundTransparency = 0.025, BorderSizePixel = 0, Visible = false, ZIndex = 40,
	}, root)
	round(self.Window)
	create("UIStroke", { Color = colors.Stroke, Thickness = 1 }, self.Window)
	local title = label(self.Window, "FER & FIOLES · LE LOBBY", 28, colors.Gold)
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -78, 0, 28)
	self.Close = button(self.Window, "×", function() self:SetOpen(false) end, {
		Position = UDim2.new(1, -48, 0, 10), Size = UDim2.fromOffset(34, 34), TextSize = 22,
	})
	self.Tabs = {}
	for i, name in ipairs({ "PvP", "Boutique", "Factions" }) do
		self.Tabs[name] = button(self.Window, name, function()
			self.Tab = name
			self:Render()
		end, { Position = UDim2.new((i - 1) / 3, 14, 0, 52), Size = UDim2.new(1 / 3, -20, 0, 35) })
	end
	self.Body = create("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 100), Size = UDim2.new(1, -32, 1, -144),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.Gold, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 41,
	}, self.Window)
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, self.Body)
	self.Footer = label(self.Window, "Ferme le menu pour viser · Ctrl : verrouillage caméra", 30, colors.Muted)
	self.Footer.Position = UDim2.new(0, 17, 1, -37)
	self.Footer.Size = UDim2.new(1, -34, 0, 30)
	local function layout()
		local size = root.AbsoluteSize
		self.Header.Size = UDim2.fromOffset(math.min(450, math.max(270, size.X - 24)), 58)
		self.Window.Size = UDim2.fromOffset(math.min(660, size.X - 24), math.min(535, math.max(220, size.Y - 91)))
		self.Window.Position = UDim2.new(0.5, 0, 0, 79 + self.Window.Size.Y.Offset / 2)
		self.Footer.Text = UserInputService.TouchEnabled and "Ferme le menu pour explorer le lobby." or "Ferme le menu pour viser · Ctrl : caméra · Maj : courir"
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	self:SetActivity(self.Activity)
	return self
end

function LobbyUI:IsOpen()
	return self.Open and self.Activity == "Lobby"
end

function LobbyUI:SetOpen(open)
	self.Open = open == true and self.Activity == "Lobby"
	self.Window.Visible = self.Open
	self.Toggle.Text = self.Open and "FERMER" or "MENU PvP"
	if self.OnMenuChanged then self.OnMenuChanged(self.Open) end
	if self.Open then self:Render() end
end

function LobbyUI:SetActivity(activity)
	local previous = self.Activity
	self.Activity = activity or "Lobby"
	self.Header.Visible = self.Activity == "Lobby"
	if self.Activity ~= "Lobby" then
		self:SetOpen(false)
	elseif previous ~= "Lobby" then
		self.Selection = {}
		self:SetOpen(false)
	end
end

function LobbyUI:SetLobby(snapshot)
	if type(snapshot) ~= "table" then return end
	local oldIncoming = self.Lobby.Incoming
	self.Lobby = snapshot
	-- Stable identity lets the countdown update without rebuilding a scrolling menu every second.
	local parts = { tostring(snapshot.ArenaBusy) }
	for _, subject in ipairs(snapshot.Players or {}) do
		table.insert(parts, tostring(subject.UserId) .. tostring(subject.Name) .. tostring(subject.Activity) .. tostring(subject.Busy) .. tostring(subject.FactionId))
	end
	for _, invite in pairs({ snapshot.Incoming or false, snapshot.Outgoing or false }) do
		if type(invite) == "table" then
			table.insert(parts, tostring(invite.Id))
			for _, member in ipairs(invite.Members or {}) do table.insert(parts, tostring(member.Name) .. tostring(member.Accepted)) end
		end
	end
	local key = table.concat(parts, "|")
	if key ~= self.RenderKey then self.RenderKey = key self:Render() end
	if snapshot.Incoming and (not oldIncoming or oldIncoming.Id ~= snapshot.Incoming.Id) and self.Activity == "Lobby" then
		self.Tab = "PvP"
		self:SetOpen(true)
	end
end

function LobbyUI:SetProfile(profile)
	if type(profile) ~= "table" then return end
	self.Profile = profile
	self.PendingProfileUntil = 0
	self:Render()
end

function LobbyUI:_profileAction(action, payload)
	if self.Activity ~= "Lobby" or self.Profile.Loaded ~= true or workspace:GetServerTimeNow() < self.PendingProfileUntil then return end
	self.PendingProfileUntil = workspace:GetServerTimeNow() + 1
	self.Action:FireServer(action, payload)
	self:Step()
end

function LobbyUI:_personName(id)
	for _, subject in ipairs(self.Lobby.Players or {}) do
		if subject.UserId == id then return subject.DisplayName or subject.Name or tostring(id) end
	end
	return "Choisir un joueur"
end

function LobbyUI:_renderInvite(invite, incoming)
	label(self.Body, incoming and ("DEMANDE DE " .. tostring(invite.HostName or "combat")) or "DEMANDE ENVOYÉE", 24, colors.Gold)
	local timer = label(self.Body, "", 22, colors.Muted)
	table.insert(self.TimerLabels, { Label = timer, ExpiresAt = invite.ExpiresAt })
	for _, member in ipairs(invite.Members or {}) do
		local team = self.Config.Teams[member.TeamId]
		label(self.Body, (member.Accepted and "✓ " or "… ") .. tostring(member.Name or "Joueur") .. " · " .. (team and team.Name or ""), 23,
			team and rgb(team.Color) or colors.Text)
	end
	if incoming then
		local accepted = false
		for _, member in ipairs(invite.Members or {}) do
			if member.UserId == self.Player.UserId or member.Name == self.Player.Name then accepted = member.Accepted == true end
		end
		local controls = row(self.Body, 38)
		local accept = button(controls, accepted and "ACCEPTÉ · EN ATTENTE" or "ACCEPTER", function()
			self.Action:FireServer("InviteRespond", { InviteId = invite.Id, Accept = true })
		end, { Size = UDim2.new(0.5, -4, 1, 0), TextColor3 = colors.Gold })
		accept.Interactable = not accepted
		button(controls, "REFUSER", function()
			self.Action:FireServer("InviteRespond", { InviteId = invite.Id, Accept = false })
		end, { Position = UDim2.new(0.5, 4, 0, 0), Size = UDim2.new(0.5, -8, 1, 0) })
	else
		button(self.Body, "ANNULER LA DEMANDE", function()
			self.Action:FireServer("InviteCancel", { InviteId = invite.Id })
		end)
	end
	label(self.Body, "Tous les joueurs doivent accepter pour lancer le combat.", 32, colors.Muted)
end

function LobbyUI:_renderPvP()
	local lobby = self.Lobby
	if lobby.Incoming or lobby.Outgoing then self:_renderInvite(lobby.Incoming or lobby.Outgoing, lobby.Incoming ~= nil) return end
	label(self.Body, "Invite des joueurs du lobby. Une vie, l'épée seule, sans parade ni coup de pied.", 38, colors.Muted)
	local modes = row(self.Body, 37)
	for index, mode in ipairs({ "Duel", "Teams" }) do
		button(modes, mode == "Duel" and "DUEL · 1 CONTRE 1" or "ÉQUIPES · 2 CONTRE 2", function()
			self.Mode = mode
			self.Role = mode == "Teams" and "AllyUserId" or "OpponentUserId"
			self.Selection = {}
			self:Render()
		end, { Position = UDim2.new((index - 1) * 0.5, index == 1 and 0 or 4, 0, 0),
			Size = UDim2.new(0.5, -5, 1, 0), TextColor3 = self.Mode == mode and colors.Gold or colors.Muted })
	end
	local roles = self.Mode == "Teams" and {
		{ "AllyUserId", "TON ALLIÉ · BLEUS", colors.Blue },
		{ "OpponentUserId", "ADVERSAIRE 1 · ROUGES", colors.Red },
		{ "OpponentAllyUserId", "ADVERSAIRE 2 · ROUGES", colors.Red },
	} or { { "OpponentUserId", "TON ADVERSAIRE", colors.Red } }
	for _, role in ipairs(roles) do
		local key, title, color = role[1], role[2], role[3]
		button(self.Body, (self.Role == key and "▶ " or "") .. title .. " : " .. self:_personName(self.Selection[key]), function()
			self.Role = key
			self:Render()
		end, { TextColor3 = color, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	label(self.Body, "JOUEURS DISPONIBLES · clique pour remplir la place sélectionnée", 33, colors.Gold)
	local count = 0
	for _, subject in ipairs(lobby.Players or {}) do
		if subject.UserId ~= self.Player.UserId and subject.Activity == "Lobby" and not subject.Busy and validId(subject.UserId) then
			count += 1
			local selected
			for _, role in ipairs(roles) do if self.Selection[role[1]] == subject.UserId then selected = role[2] end end
			local displayName = subject.DisplayName or subject.Name or tostring(subject.UserId)
			local text = displayName .. (subject.Name and "  @" .. subject.Name or "") .. (selected and "  · " .. selected or "")
			button(self.Body, text, function()
				for role, id in pairs(self.Selection) do if id == subject.UserId then self.Selection[role] = nil end end
				self.Selection[self.Role] = subject.UserId
				for _, role in ipairs(roles) do if not self.Selection[role[1]] then self.Role = role[1] break end end
				self:Render()
			end, { TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = selected and colors.Gold or colors.Text })
		end
	end
	if count == 0 then label(self.Body, "Aucun autre joueur disponible. Invite tes amis à rejoindre ce serveur.", 48, colors.Muted) end
	self.Status = label(self.Body, "", 36, colors.Muted)
	self.Send = button(self.Body, "ENVOYER LA DEMANDE", function()
		if not self:_canInvite() then return end
		local payload = { Mode = self.Mode, OpponentUserId = self.Selection.OpponentUserId }
		if self.Mode == "Teams" then
			payload.AllyUserId = self.Selection.AllyUserId
			payload.OpponentAllyUserId = self.Selection.OpponentAllyUserId
		end
		self.SendUntil = workspace:GetServerTimeNow() + 1
		self.Action:FireServer("Invite", payload)
		self:Step()
	end, { TextColor3 = colors.Gold })
	label(self.Body, "Demandes : délai de " .. self.Config.Invites.CooldownSeconds .. " s · expiration après " .. self.Config.Invites.ExpiresSeconds .. " s.", 32, colors.Muted)
end

function LobbyUI:_renderShop()
	label(self.Body, "ÉPÉES COSMÉTIQUES · Toutes infligent les mêmes dégâts et ont la même portée.", 40, colors.Gold)
	label(self.Body, "Victoire : +" .. self.Config.Rewards.Win .. " pièces · défaite : +" .. self.Config.Rewards.Loss .. " · aucun gain sur abandon.", 34, colors.Muted)
	local profile = self.Profile
	for _, id in ipairs(self.Catalog.SwordOrder) do
		local sword = self.Catalog.Swords[id]
		local card = row(self.Body, 74)
		card.BackgroundColor3 = colors.Inset
		card.BackgroundTransparency = 0.1
		round(card)
		-- Original stylized blade preview; no downloaded assets are needed.
		create("Frame", { Position = UDim2.fromOffset(23, 10), Size = UDim2.fromOffset(7, 39),
			BackgroundColor3 = rgb(sword.Blade), BorderSizePixel = 0, Rotation = 14, ZIndex = 43 }, card)
		create("Frame", { Position = UDim2.fromOffset(12, 45), Size = UDim2.fromOffset(24, 5),
			BackgroundColor3 = rgb(sword.Guard), BorderSizePixel = 0, Rotation = 14, ZIndex = 43 }, card)
		create("Frame", { Position = UDim2.fromOffset(21, 49), Size = UDim2.fromOffset(6, 15),
			BackgroundColor3 = rgb(sword.Accent), BorderSizePixel = 0, Rotation = 14, ZIndex = 43 }, card)
		local title = label(card, sword.Name .. "\n" .. sword.Price .. " pièces", 58)
		title.Position = UDim2.fromOffset(51, 8)
		title.Size = UDim2.new(1, -180, 0, 58)
		local owned = profile.OwnedSwords and profile.OwnedSwords[id] == true
		local equipped = profile.EquippedSword == id
		local choice = button(card, equipped and "ÉQUIPÉE" or (owned and "ÉQUIPER" or "ACHETER"), function()
			self:_profileAction(owned and "EquipSword" or "BuySword", { SwordId = id })
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -9, 0.5, 0),
			Size = UDim2.fromOffset(112, 39), BackgroundColor3 = colors.Panel,
			TextColor3 = equipped and colors.Gold or colors.Text })
		table.insert(self.ProfileButtons, { Button = choice, Allowed = not equipped and (owned or (tonumber(profile.Coins) or 0) >= sword.Price) })
	end
end

function LobbyUI:_renderFactions()
	label(self.Body, "CHOISIS TA FACTION · Armure visuelle gratuite, sans avantage de combat.", 42, colors.Gold)
	for _, id in ipairs(self.Catalog.FactionOrder) do
		local faction = self.Catalog.Factions[id]
		local card = row(self.Body, 82)
		card.BackgroundColor3 = colors.Inset
		card.BackgroundTransparency = 0.1
		round(card)
		local swatch = create("Frame", { Position = UDim2.fromOffset(13, 18), Size = UDim2.fromOffset(26, 43),
			BackgroundColor3 = rgb(faction.Color), BorderSizePixel = 0, ZIndex = 43 }, card)
		round(swatch)
		create("UIStroke", { Color = rgb(faction.Trim), Thickness = 2 }, swatch)
		local title = label(card, faction.Name .. "\n" .. faction.Description, 68)
		title.Position = UDim2.fromOffset(53, 7)
		title.Size = UDim2.new(1, -181, 0, 68)
		local selected = self.Profile.FactionId == id
		local choice = button(card, selected and "CHOISIE" or "CHOISIR", function()
			self:_profileAction("ChooseFaction", { FactionId = id })
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -9, 0.5, 0),
			Size = UDim2.fromOffset(112, 39), BackgroundColor3 = colors.Panel,
			TextColor3 = selected and colors.Gold or colors.Text })
		table.insert(self.ProfileButtons, { Button = choice, Allowed = not selected })
	end
	label(self.Body, "Les clans et leur classement arriveront plus tard.", 36, colors.Muted)
end

function LobbyUI:Render()
	for _, child in ipairs(self.Body:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
	self.TimerLabels = {}
	self.ProfileButtons = {}
	self.Status, self.Send = nil, nil
	for name, tab in pairs(self.Tabs) do tab.TextColor3 = self.Tab == name and colors.Gold or colors.Muted end
	if self.Profile.Loaded ~= true then
		label(self.Body, self.Profile.SaveMode == "Unavailable" and "Profil indisponible : les achats et les invitations sont temporairement bloqués." or "Chargement du profil… Tu peux explorer le lobby en fermant ce menu.", 54, colors.Muted)
	elseif self.Profile.SaveMode == "Session" then
		label(self.Body, "Mode session : tes pièces et choix ne seront pas conservés après avoir quitté ce serveur.", 42, colors.Muted)
	end
	if self.Tab == "Boutique" then self:_renderShop()
	elseif self.Tab == "Factions" then self:_renderFactions()
	else self:_renderPvP() end
	self:Step()
end

function LobbyUI:_inviteReason()
	if self.Profile.Loaded ~= true then return "Le profil doit être chargé avant de lancer un combat." end
	if self.Lobby.ArenaBusy then return "L'arène est occupée. Attends la fin du combat en cours." end
	local cooldown = math.ceil((tonumber(self.Lobby.InviteCooldownUntil) or 0) - workspace:GetServerTimeNow())
	if cooldown > 0 then return "Nouvelle invitation dans " .. cooldown .. " s." end
	if workspace:GetServerTimeNow() < self.SendUntil then return "Envoi de la demande…" end
	local ids = { self.Player.UserId }
	for _, key in ipairs(self.Mode == "Teams" and { "AllyUserId", "OpponentUserId", "OpponentAllyUserId" } or { "OpponentUserId" }) do
		local id = self.Selection[key]
		if not validId(id) or table.find(ids, id) then return "Choisis " .. (self.Mode == "Teams" and "trois joueurs différents" or "un adversaire") .. " dans la liste." end
		local available = false
		for _, subject in ipairs(self.Lobby.Players or {}) do
			if subject.UserId == id and subject.Activity == "Lobby" and not subject.Busy then available = true break end
		end
		if not available then return "Un joueur sélectionné n'est plus disponible." end
		table.insert(ids, id)
	end
	return nil
end

function LobbyUI:_canInvite()
	return self.Activity == "Lobby" and not self.Lobby.Incoming and not self.Lobby.Outgoing and self:_inviteReason() == nil
end

function LobbyUI:Step()
	local profile = self.Profile
	local coins = tonumber(profile.Coins) or self.Player:GetAttribute("Coins") or 0
	self.Coins.Text = "LOBBY · " .. tostring(coins) .. " pièces" .. (profile.Loaded ~= true and "\nChargement du profil…" or "\nCombats sur invitation")
	for _, timer in ipairs(self.TimerLabels) do
		local remaining = math.max(0, math.ceil((tonumber(timer.ExpiresAt) or 0) - workspace:GetServerTimeNow()))
		timer.Label.Text = "Expiration dans " .. remaining .. " s · " .. ((self.Lobby.Incoming or self.Lobby.Outgoing or {}).Mode == "Teams" and "2 contre 2" or "1 contre 1")
	end
	if self.Send then
		local reason = self:_inviteReason()
		self.Status.Text = reason or "Prêt à envoyer : chaque joueur devra accepter."
		self.Send.Interactable = reason == nil
		self.Send.AutoButtonColor = reason == nil
		self.Send.TextTransparency = reason and 0.45 or 0
	end
	local profileReady = profile.Loaded == true and workspace:GetServerTimeNow() >= self.PendingProfileUntil and self.Activity == "Lobby"
	for _, entry in ipairs(self.ProfileButtons or {}) do
		entry.Button.Interactable = profileReady and entry.Allowed
		entry.Button.AutoButtonColor = entry.Button.Interactable
		entry.Button.TextTransparency = entry.Button.Interactable and 0 or 0.4
	end
	if not self.Open and self.Lobby.Incoming then self.Toggle.Text = "INVITATION !" end
end

return LobbyUI
