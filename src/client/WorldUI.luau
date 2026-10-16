-- Local presentation and input only; the server validates allegiance, range, costs and ownership.
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local WorldUI = {}
WorldUI.__index = WorldUI

local colors = {
	Panel = Color3.fromRGB(24, 29, 34), Inset = Color3.fromRGB(13, 18, 22),
	Text = Color3.fromRGB(245, 237, 219), Muted = Color3.fromRGB(173, 182, 188),
	Gold = Color3.fromRGB(224, 183, 103), Border = Color3.fromRGB(106, 93, 67),
	Danger = Color3.fromRGB(230, 117, 96), Green = Color3.fromRGB(133, 190, 151),
}

local function create(kind, properties, parent)
	local object = Instance.new(kind)
	for key, value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end

local function round(object, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, object)
end

local function panel(parent, properties)
	properties.BackgroundColor3 = properties.BackgroundColor3 or colors.Panel
	properties.BorderSizePixel = 0
	properties.Active = true
	local object = create("Frame", properties, parent)
	round(object)
	create("UIStroke", { Color = colors.Border, Thickness = 1, Transparency = 0.2 }, object)
	return object
end

local function label(parent, text, properties)
	local props = {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = text,
		TextColor3 = colors.Text, TextSize = 13, Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = (parent.ZIndex or 1) + 1,
	}
	for key, value in pairs(properties or {}) do props[key] = value end
	return create("TextLabel", props, parent)
end

local function button(parent, text, callback, properties)
	local props = {
		BackgroundColor3 = colors.Inset, BorderSizePixel = 0, Text = text,
		TextColor3 = colors.Text, Font = Enum.Font.GothamBold, TextSize = 12,
		AutoButtonColor = true, Active = true, ZIndex = (parent.ZIndex or 1) + 2,
	}
	for key, value in pairs(properties or {}) do props[key] = value end
	local object = create("TextButton", props, parent)
	round(object, 6)
	object.Activated:Connect(callback)
	return object
end

local function enabled(object, allowed)
	object.Interactable = allowed
	object.AutoButtonColor = allowed
	object.TextTransparency = allowed and 0 or 0.5
end

local function rgb(value)
	if type(value) ~= "table" then return colors.Muted end
	return Color3.fromRGB(value[1] or 173, value[2] or 182, value[3] or 188)
end

local function amount(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function remaining(deadline, now)
	return math.max(0, math.ceil((tonumber(deadline) or 0) - now))
end

function WorldUI.new(player, root, action, config, onMenuChanged)
	local self = setmetatable({
		Player = player, Root = root, Action = action, Config = config,
		OnMenuChanged = onMenuChanged, Open = false, HasSnapshot = false,
		Snapshot = { Inventory = {}, Kingdoms = {}, Outposts = {}, Nodes = {} },
		Connections = {}, KingdomRows = {}, OutpostRows = {}, SummaryRows = {},
		SendUntil = 0, HarvestReadyAt = 0, NearestNode = nil, NearbyOutpost = nil,
	}, WorldUI)

	self.Header = panel(root, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(452, 68), ZIndex = 34,
	})
	self.Allegiance = label(self.Header, "KINGDOMS", {
		Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -132, 0, 23),
		TextColor3 = colors.Gold, TextSize = 16, Font = Enum.Font.GothamBold,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	self.Resources = label(self.Header, "WOOD  0     ORE  0", {
		Position = UDim2.fromOffset(14, 37), Size = UDim2.new(1, -132, 0, 20), TextSize = 12,
	})
	self.Toggle = button(self.Header, "KINGDOMS · M", function() self:SetOpen(not self.Open) end, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(111, 42),
	})

	self.FlagPanel = panel(root, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 96),
		Size = UDim2.fromOffset(244, 142), ZIndex = 32,
	})
	label(self.FlagPanel, "THE FRONTIER", {
		Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 20),
		Font = Enum.Font.GothamBold, TextColor3 = colors.Gold, TextSize = 12,
	})

	self.HarvestPanel = panel(root, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -148),
		Size = UDim2.fromOffset(340, 66), Visible = false, ZIndex = 33,
	})
	self.HarvestTitle = label(self.HarvestPanel, "", {
		Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -116, 0, 22),
		Font = Enum.Font.GothamBold, TextSize = 13,
	})
	self.HarvestInfo = label(self.HarvestPanel, "", {
		Position = UDim2.fromOffset(12, 33), Size = UDim2.new(1, -116, 0, 23),
		TextSize = 11, TextColor3 = colors.Muted, TextWrapped = true,
	})
	self.HarvestButton = button(self.HarvestPanel, "HARVEST · E", function() self:_harvest() end, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -9, 0.5, 0),
		Size = UDim2.fromOffset(98, 46), TextSize = 11,
	})
	self.BuildPanel = panel(root, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -222),
		Size = UDim2.fromOffset(340, 64), Visible = false, ZIndex = 33,
	})
	self.BuildTitle = label(self.BuildPanel, "", {
		Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -116, 0, 23),
		Font = Enum.Font.GothamBold, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	self.BuildInfo = label(self.BuildPanel, "", {
		Position = UDim2.fromOffset(12, 33), Size = UDim2.new(1, -116, 0, 20),
		TextSize = 11, TextColor3 = colors.Muted,
	})
	self.BuildButton = button(self.BuildPanel, "BUILD", function()
		local point = self.NearbyOutpost
		if point then self:_send("BuildOutpost", { OutpostId = point.Id }) end
	end, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -9, 0.5, 0),
		Size = UDim2.fromOffset(98, 44), TextColor3 = colors.Gold,
	})

	self.DeathPanel = panel(root, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.43),
		Size = UDim2.fromOffset(330, 76), Visible = false, ZIndex = 39,
	})
	self.DeathTitle = label(self.DeathPanel, "", {
		Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 0, 24),
		TextSize = 17, Font = Enum.Font.GothamBold, TextColor3 = colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	self.DeathInfo = label(self.DeathPanel, "", {
		Position = UDim2.fromOffset(12, 41), Size = UDim2.new(1, -24, 0, 20),
		TextColor3 = colors.Muted, TextXAlignment = Enum.TextXAlignment.Center,
	})

	self.Scrim = create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(5, 8, 11),
		BackgroundTransparency = 0.26, BorderSizePixel = 0, Active = true,
		Visible = false, ZIndex = 40,
	}, root)
	self.Window = panel(self.Scrim, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(590, 570), ZIndex = 41,
	})
	self.Title = label(self.Window, "PLEDGE YOUR ALLEGIANCE", {
		Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -75, 0, 28),
		TextColor3 = colors.Gold, TextSize = 18, Font = Enum.Font.GothamBold,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	self.Close = button(self.Window, "×", function() self:SetOpen(false) end, {
		Position = UDim2.new(1, -49, 0, 10), Size = UDim2.fromOffset(35, 35), TextSize = 23,
	})
	self.Subtitle = label(self.Window, "", {
		Position = UDim2.fromOffset(18, 45), Size = UDim2.new(1, -36, 0, 40),
		TextColor3 = colors.Muted, TextSize = 12, TextWrapped = true,
	})
	self.Body = create("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 94), Size = UDim2.new(1, -32, 1, -138),
		BackgroundTransparency = 1, BorderSizePixel = 0, Active = true,
		ScrollBarThickness = 4, ScrollBarImageColor3 = colors.Gold,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 42,
	}, self.Window)
	create("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }, self.Body)
	self.Footer = label(self.Window, "", {
		Position = UDim2.new(0, 18, 1, -37), Size = UDim2.new(1, -36, 0, 29),
		TextColor3 = colors.Muted, TextSize = 11, TextWrapped = true,
	})
	self:_createKingdomRows()
	self.CaptureHeading = label(self.Body, "FLAGS & OUTPOSTS", {
		Size = UDim2.new(1, -8, 0, 26), TextColor3 = colors.Gold,
		Font = Enum.Font.GothamBold, LayoutOrder = 20,
	})
	self.BaseButton = button(self.Body, "RESPAWN AT KINGDOM BASE", function()
		self:_send("SetOutpostSpawn", { OutpostId = "" })
	end, { Size = UDim2.new(1, -8, 0, 40), LayoutOrder = 21 })
	label(self.Body, "Stand alone with your kingdom at a flag to capture it. Enemy kingdoms contest the claim. Build an owned outpost to unlock a forward respawn.", {
		Size = UDim2.new(1, -8, 0, 64), LayoutOrder = 90, TextWrapped = true,
		TextColor3 = colors.Muted, TextSize = 12,
	})
	label(self.Body, "Wood, ore, flag ownership and outposts belong to this server session.", {
		Size = UDim2.new(1, -8, 0, 35), LayoutOrder = 91,
		TextColor3 = colors.Muted, TextWrapped = true, TextSize = 11,
	})

	local function layout()
		local size = root.AbsoluteSize
		local width = math.max(240, size.X - 24)
		self.Header.Size = UDim2.fromOffset(math.min(452, width), 68)
		self.Window.Size = UDim2.fromOffset(math.min(590, width), math.max(190, math.min(620, size.Y - 24)))
		self.HarvestPanel.Size = UDim2.fromOffset(math.min(340, width), 66)
		self.BuildPanel.Size = UDim2.fromOffset(math.min(340, width), 64)
		self.DeathPanel.Size = UDim2.fromOffset(math.min(330, width), 76)
		local compact = size.X < 900 or (UserInputService.TouchEnabled and size.X < 1200)
		self.Compact = compact
		self.NarrowTouch = UserInputService.TouchEnabled and size.X < 560
		self.ShortViewport = size.Y < 500
		self.HarvestPanel.AnchorPoint = self.ShortViewport and not self.NarrowTouch and Vector2.new(0, 1) or Vector2.new(0.5, 1)
		if self.ShortViewport and not self.NarrowTouch then
			self.HarvestPanel.Size = UDim2.fromOffset(math.min(300, width), 66)
		end
		self.FlagPanel.Position = compact and UDim2.new(1, -12, 0, 94) or UDim2.new(1, -24, 0, 96)
		self.FlagPanel.Size = UDim2.fromOffset(compact and math.min(215, width) or 244, 142)
		self.HarvestPanel.Position = self.NarrowTouch and UDim2.new(0.5, 0, 0, 264)
			or (self.ShortViewport and UDim2.new(0, 15, 1, -116))
			or UDim2.new(0.5, 0, 1, size.Y < 480 and -116 or -148)
		self.BuildPanel.Position = UDim2.new(0.5, 0, 1, size.Y < 480 and -190 or -222)
	end
	table.insert(self.Connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.M then self:SetOpen(not self.Open)
		elseif input.KeyCode == Enum.KeyCode.E and not self.Open then self:_harvest() end
	end))
	local elapsed = 0
	table.insert(self.Connections, RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then return end
		elapsed = 0
		self:Step()
	end))
	layout()
	self:SetOpen(true)
	self:Step()
	return self
end

function WorldUI:_kingdom(id)
	for _, kingdom in ipairs(self.Snapshot.Kingdoms or {}) do
		if kingdom.Id == id then return kingdom end
	end
	return self.Config.Kingdoms[id]
end

function WorldUI:_kingdomName(id)
	local kingdom = id and self:_kingdom(id)
	return kingdom and kingdom.Name or "Neutral"
end

function WorldUI:_kingdomColor(id)
	local kingdom = id and self:_kingdom(id)
	return kingdom and rgb(kingdom.Color) or colors.Muted
end

function WorldUI:_createKingdomRows()
	for index, id in ipairs(self.Config.KingdomOrder) do
		local kingdom = self.Config.Kingdoms[id]
		local card = panel(self.Body, {
			Size = UDim2.new(1, -8, 0, 66), BackgroundColor3 = colors.Inset,
			LayoutOrder = index, ZIndex = 43,
		})
		create("Frame", {
			Position = UDim2.fromOffset(0, 10), Size = UDim2.new(0, 3, 1, -20),
			BackgroundColor3 = rgb(kingdom.Color), BorderSizePixel = 0, ZIndex = 44,
		}, card)
		local name = label(card, kingdom.Name, {
			Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -142, 0, 23),
			TextColor3 = rgb(kingdom.Color), Font = Enum.Font.GothamBold,
			TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local population = label(card, "", {
			Position = UDim2.fromOffset(14, 35), Size = UDim2.new(1, -142, 0, 20),
			TextColor3 = colors.Muted, TextSize = 12,
		})
		local choose = button(card, "JOIN KINGDOM", function()
			self:_send("ChooseKingdom", { KingdomId = id })
		end, {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(114, 40), BackgroundColor3 = colors.Panel,
		})
		self.KingdomRows[id] = { Name = name, Population = population, Button = choose }
	end
end

function WorldUI:_createOutpostRows(points)
	for _, row in pairs(self.OutpostRows) do row.Card:Destroy() end
	for _, row in ipairs(self.SummaryRows) do row.Card:Destroy() end
	self.OutpostRows, self.SummaryRows = {}, {}
	for index, point in ipairs(points) do
		local id = point.Id
		local card = panel(self.Body, {
			Size = UDim2.new(1, -8, 0, 137), BackgroundColor3 = colors.Inset,
			LayoutOrder = 30 + index, ZIndex = 43,
		})
		local title = label(card, point.Name or id, {
			Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 22),
			Font = Enum.Font.GothamBold, TextSize = 14,
		})
		local status = label(card, "", {
			Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 20), TextSize = 12,
		})
		local track = create("Frame", {
			Position = UDim2.fromOffset(12, 61), Size = UDim2.new(1, -24, 0, 4),
			BackgroundColor3 = colors.Panel, BorderSizePixel = 0, ZIndex = 44,
		}, card)
		local fill = create("Frame", {
			Size = UDim2.fromScale(0, 1), BackgroundColor3 = colors.Gold,
			BorderSizePixel = 0, ZIndex = 45,
		}, track)
		local info = label(card, "", {
			Position = UDim2.fromOffset(12, 76), Size = UDim2.new(1, -150, 0, 48),
			TextWrapped = true, TextColor3 = colors.Muted, TextSize = 11,
		})
		local choice = button(card, "", function()
			local current = self:_outpost(id)
			if not current or current.Owner ~= self.Snapshot.KingdomId then return end
			self:_send(current.Built and "SetOutpostSpawn" or "BuildOutpost", { OutpostId = id })
		end, {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, 102),
			Size = UDim2.fromOffset(127, 42), BackgroundColor3 = colors.Panel,
		})
		self.OutpostRows[id] = { Card = card, Name = title, Status = status, Fill = fill, Info = info, Button = choice }
		local summary = create("Frame", {
			Position = UDim2.fromOffset(12, 33 + (index - 1) * 33),
			Size = UDim2.new(1, -24, 0, 29), BackgroundTransparency = 1, ZIndex = 33,
		}, self.FlagPanel)
		local name = label(summary, "", { Size = UDim2.new(1, 0, 0, 17), TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd })
		local meter = create("Frame", {
			Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = colors.Inset, BorderSizePixel = 0, ZIndex = 34,
		}, summary)
		local meterFill = create("Frame", {
			Size = UDim2.fromScale(0, 1), BackgroundColor3 = colors.Gold, BorderSizePixel = 0, ZIndex = 35,
		}, meter)
		table.insert(self.SummaryRows, { Card = summary, Id = id, Name = name, Fill = meterFill })
	end
	self.FlagPanel.Size = UDim2.new(self.FlagPanel.Size.X.Scale, self.FlagPanel.Size.X.Offset, 0, 40 + #points * 33)
end

function WorldUI:_outpost(id)
	for _, point in ipairs(self.Snapshot.Outposts or {}) do if point.Id == id then return point end end
	return nil
end

function WorldUI:_send(action, payload)
	local now = workspace:GetServerTimeNow()
	if not self.HasSnapshot or now < self.SendUntil then return false end
	self.SendUntil = now + 0.25
	self.Action:FireServer(action, payload)
	self:Step()
	return true
end

function WorldUI:_livingRoot()
	local character = self.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid and humanoid.Health > 0 and root or nil
end

function WorldUI:_harvest()
	if self.Open or not self.Snapshot.KingdomId or not self:_livingRoot() then return end
	local now = workspace:GetServerTimeNow()
	if not self.NearestNode or now < self.HarvestReadyAt then return end
	local nodeId = self.NearestNode.Id
	-- Use the latest local position for the prompt. Server positions and sightlines decide acceptance.
	self:Step()
	if not self.NearestNode or self.NearestNode.Id ~= nodeId then return end
	if self:_send("Harvest", { NodeId = nodeId }) then
		self.HarvestReadyAt = now + self.Config.World.HarvestCooldown
		self:Step()
	end
end

function WorldUI:IsOpen()
	return self.Open
end

function WorldUI:SetOpen(open)
	open = open == true or not self.Snapshot.KingdomId
	local changed = self.Open ~= open
	self.Open = open
	self.Scrim.Visible = open
	self.Toggle.Text = open and "CLOSE · M" or "KINGDOMS · M"
	if changed and self.OnMenuChanged then self.OnMenuChanged(open) end
	self:Step()
end

function WorldUI:SetWorld(snapshot)
	if type(snapshot) ~= "table" then return end
	local previousKingdom = self.Snapshot.KingdomId
	self.Snapshot = snapshot
	self.HasSnapshot = true
	local ids = {}
	for _, point in ipairs(snapshot.Outposts or {}) do table.insert(ids, point.Id) end
	local key = table.concat(ids, "|")
	if key ~= self.OutpostKey then
		self.OutpostKey = key
		self:_createOutpostRows(snapshot.Outposts or {})
	end
	if not snapshot.KingdomId then self:SetOpen(true)
	elseif not previousKingdom then self:SetOpen(false) end
	self:Step()
end

function WorldUI:Step()
	local now = workspace:GetServerTimeNow()
	local state, world = self.Snapshot, self.Config.World
	local kingdomId = state.KingdomId
	local inventory = state.Inventory or {}
	local wood, ore = amount(inventory.Wood), amount(inventory.Ore)
	local root = self:_livingRoot()
	local ready = self.HasSnapshot and now >= self.SendUntil
	local kingdomWait = remaining(state.KingdomChangeReadyAt, now)
	local respawnWait = remaining(state.RespawnAt, now)
	local dead = kingdomId ~= nil and (respawnWait > 0 or not root)
	local affordable = wood >= world.OutpostWoodCost and ore >= world.OutpostOreCost
	self.Allegiance.Text = kingdomId and string.upper(self:_kingdomName(kingdomId)) or "CHOOSE A KINGDOM"
	self.Allegiance.TextColor3 = kingdomId and self:_kingdomColor(kingdomId) or colors.Gold
	self.Toggle.Text = not kingdomId and "CHOOSE" or (self.Open and "CLOSE · M" or "KINGDOMS · M")
	self.Resources.Text = "WOOD  " .. wood .. "     ORE  " .. ore
	self.Title.Text = kingdomId and "KINGDOMS & THE FRONTIER" or "PLEDGE YOUR ALLEGIANCE"
	self.Subtitle.Text = not self.HasSnapshot and "Connecting to the world…"
		or (not kingdomId and "Choose your kingdom, gather resources and claim the frontier. Your kingdom determines your allies and base."
		or (kingdomWait > 0 and "Kingdom change available in " .. kingdomWait .. "s. Leave combat before changing allegiance."
		or "Changing allegiance returns you to your new base. Leave combat before changing kingdoms."))
	self.Close.Visible = kingdomId ~= nil
	self.Footer.Text = kingdomId and (UserInputService.TouchEnabled and "Tap HARVEST near a tree or mine. Close this menu to wield your sword."
		or "M: close menu   ·   E: harvest nearby resources   ·   Stand at flags to capture")
		or "Select a kingdom to enter the world."
	for id, row in pairs(self.KingdomRows) do
		local kingdom = self:_kingdom(id)
		local selected = id == kingdomId
		local count = amount(kingdom and kingdom.Players)
		row.Population.Text = count .. (count == 1 and " player" or " players") .. (selected and " · your kingdom" or "")
		row.Button.Text = selected and "ALLEGIANCE" or (kingdomWait > 0 and kingdomWait .. "s" or "JOIN KINGDOM")
		row.Button.TextColor3 = selected and colors.Gold or colors.Text
		enabled(row.Button, ready and not selected and kingdomWait == 0 and not dead)
	end

	local selectedSpawn = state.SpawnOutpostId and self:_outpost(state.SpawnOutpostId)
	local spawnName = selectedSpawn and selectedSpawn.Owner == kingdomId and selectedSpawn.Built and selectedSpawn.Name or "kingdom base"
	local forwardSpawn = type(state.SpawnOutpostId) == "string" and state.SpawnOutpostId ~= ""
	self.BaseButton.Text = forwardSpawn and "RESET RESPAWN TO KINGDOM BASE" or "RESPAWN: KINGDOM BASE"
	self.BaseButton.TextColor3 = forwardSpawn and colors.Text or colors.Gold
	enabled(self.BaseButton, ready and kingdomId ~= nil and not dead and state.SpawnOutpostId ~= nil and state.SpawnOutpostId ~= "")
	self.DeathPanel.Visible = dead and not self.Open
	self.DeathTitle.Text = respawnWait > 0 and "RETURNING IN " .. respawnWait .. "s" or "RETURNING TO BATTLE…"
	self.DeathInfo.Text = "Respawn: " .. tostring(spawnName)
	-- The complete flag list remains in the menu; keep small viewports clear for vitals and touch controls.
	self.FlagPanel.Visible = kingdomId ~= nil and not self.Open and not self.Compact

	local nearestBuild, buildDistance = nil, math.huge
	for _, point in ipairs(state.Outposts or {}) do
		local row = self.OutpostRows[point.Id]
		local owned = kingdomId ~= nil and point.Owner == kingdomId
		local distance = root and typeof(point.Position) == "Vector3" and (point.Position - root.Position).Magnitude or math.huge
		local progress = math.clamp(tonumber(point.Progress) or 0, 0, 1)
		local color = point.Contested and colors.Danger or self:_kingdomColor(point.Claimant or point.Owner)
		local status = point.Contested and "CONTESTED — capture paused"
			or (point.Claimant and (self:_kingdomName(point.Claimant) .. " claiming · " .. math.floor(progress * 100) .. "%")
			or (self:_kingdomName(point.Owner) .. (point.Built and " · fortified" or " · flag")))
		if row then
			row.Name.Text = point.Name or point.Id
			row.Status.Text, row.Status.TextColor3 = status, color
			row.Fill.Size = UDim2.fromScale(point.Claimant and progress or (point.Owner and 1 or 0), 1)
			row.Fill.BackgroundColor3 = color
			row.Info.Text = owned and (point.Built and "An allied outpost. Select it as your next respawn."
				or ("Build: " .. world.OutpostWoodCost .. " wood + " .. world.OutpostOreCost .. " ore\n" .. (distance <= world.BuildRange and "Within building range" or "Move within " .. world.BuildRange .. " studs")))
				or (point.Owner and "Capture the flag for your kingdom to use this outpost." or "Stand at this flag to claim it for your kingdom.")
			local selected = state.SpawnOutpostId == point.Id
			row.Button.Text = not owned and "CAPTURE FLAG" or (point.Built and (selected and "RESPAWN SET" or "SET RESPAWN") or "BUILD OUTPOST")
			row.Button.TextColor3 = selected and colors.Gold or colors.Text
			enabled(row.Button, ready and owned and not dead and not selected and (point.Built or (not point.Contested and distance <= world.BuildRange and affordable)))
		end
		if owned and not point.Built and distance <= world.BuildRange and distance < buildDistance then
			nearestBuild, buildDistance = point, distance
		end
	end
	for _, row in ipairs(self.SummaryRows) do
		local point = self:_outpost(row.Id)
		if point then
			local progress = math.clamp(tonumber(point.Progress) or 0, 0, 1)
			row.Name.Text = (point.Name or point.Id) .. " · " .. (point.Contested and "CONTESTED" or self:_kingdomName(point.Owner))
			row.Name.TextColor3 = point.Contested and colors.Danger or self:_kingdomColor(point.Owner)
			row.Fill.Size = UDim2.fromScale(point.Claimant and progress or (point.Owner and 1 or 0), 1)
			row.Fill.BackgroundColor3 = point.Contested and colors.Danger or self:_kingdomColor(point.Claimant or point.Owner)
		end
	end
	self.NearbyOutpost = nearestBuild
	self.BuildPanel.Visible = nearestBuild ~= nil and not self.Open and not dead and not self.NarrowTouch and not self.ShortViewport
	if nearestBuild then
		self.BuildTitle.Text = nearestBuild.Name or nearestBuild.Id
		self.BuildInfo.Text = nearestBuild.Contested and "Contested: clear enemy claimants"
			or (world.OutpostWoodCost .. " wood + " .. world.OutpostOreCost .. " ore")
		self.BuildInfo.TextColor3 = affordable and colors.Green or colors.Muted
		enabled(self.BuildButton, ready and affordable and not dead and not nearestBuild.Contested)
	end

	local closest, closestDistance, live, liveDistance = nil, math.huge, nil, math.huge
	if kingdomId and root then
		for _, node in ipairs(state.Nodes or {}) do
			if typeof(node.Position) == "Vector3" then
				local distance = (node.Position - root.Position).Magnitude
				if distance < closestDistance then closest, closestDistance = node, distance end
				if amount(node.HitsRemaining) > 0 and distance <= world.HarvestRange and distance < liveDistance then
					live, liveDistance = node, distance
				end
			end
		end
	end
	self.NearestNode = live
	local shown = live or closest
	local distance = live and liveDistance or closestDistance
	self.HarvestPanel.Visible = shown ~= nil and distance <= world.HarvestRange + 10 and not self.Open and not dead
	if shown then
		local hits = amount(shown.HitsRemaining)
		local tree = shown.Kind == "Tree"
		local nodeConfig = tree and world.Tree or world.Mine
		self.HarvestTitle.Text = (tree and "CHOP TREE" or "MINE ORE") .. " · " .. math.floor(distance) .. " studs"
		self.HarvestInfo.Text = hits == 0 and ("Returns in " .. remaining(shown.RespawnAt, now) .. "s")
			or (not live and "Move closer to harvest" or (hits .. " hits left · +" .. nodeConfig.Yield .. (tree and " wood" or " ore") .. " on depletion"))
		local wait = remaining(self.HarvestReadyAt, now)
		self.HarvestButton.Text = wait > 0 and "READY IN " .. wait .. "s" or (UserInputService.TouchEnabled and "HARVEST" or "HARVEST · E")
		enabled(self.HarvestButton, live ~= nil and ready and wait == 0 and not dead)
	end
end

function WorldUI:Destroy()
	for _, connection in ipairs(self.Connections) do connection:Disconnect() end
	for _, object in ipairs({ self.Header, self.FlagPanel, self.HarvestPanel, self.BuildPanel, self.DeathPanel, self.Scrim }) do object:Destroy() end
	if self.Open and self.OnMenuChanged then self.OnMenuChanged(false) end
end

return WorldUI
