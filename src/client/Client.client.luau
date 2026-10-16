-- HUD and input only. Combat, healing, inventory and stamina remain authoritative on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("MedievalShared")
local Config = require(shared:WaitForChild("Config"))
local worldMode = Config.Game.Mode == "Kingdoms"
local Catalog = require(shared:WaitForChild("Catalog"))
local LobbyUI = require(script.Parent:WaitForChild("LobbyUI"))
local CameraLock = require(script.Parent:WaitForChild("CameraLock"))
local remotes = ReplicatedStorage:WaitForChild("MedievalRemotes")
local Action = remotes:WaitForChild("Action")
local State = remotes:WaitForChild("State")
local Effects = remotes:WaitForChild("Effects")
local Lobby = remotes:WaitForChild("Lobby")
local Profile = remotes:WaitForChild("Profile")
local World = remotes:WaitForChild("World")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local palette = {
	Panel = Color3.fromRGB(25, 29, 34), Inset = Color3.fromRGB(13, 17, 21),
	Text = Color3.fromRGB(245, 236, 217), Muted = Color3.fromRGB(177, 181, 184),
	Gold = Color3.fromRGB(222, 181, 99), Stroke = Color3.fromRGB(101, 91, 72),
	Health = Color3.fromRGB(117, 192, 140), Danger = Color3.fromRGB(229, 105, 91),
}

local function rgb(values)
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function create(className, properties, parent)
	local object = Instance.new(className)
	for key, value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end

local function corners(parent, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

local function outline(parent, color, transparency)
	return create("UIStroke", {
		Color = color or palette.Stroke, Thickness = 1,
		Transparency = transparency or 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function panel(parent, properties)
	properties.BackgroundColor3 = properties.BackgroundColor3 or palette.Panel
	properties.BackgroundTransparency = properties.BackgroundTransparency or 0.08
	properties.BorderSizePixel = 0
	local object = create("Frame", properties, parent)
	corners(object, 10)
	outline(object)
	return object
end

local function label(parent, text, properties)
	properties = properties or {}
	properties.Text = text
	properties.BackgroundTransparency = 1
	properties.BorderSizePixel = 0
	properties.Font = properties.Font or Enum.Font.GothamMedium
	properties.TextColor3 = properties.TextColor3 or palette.Text
	properties.TextSize = properties.TextSize or 14
	properties.TextXAlignment = properties.TextXAlignment or Enum.TextXAlignment.Left
	return create("TextLabel", properties, parent)
end

local function button(parent, text, properties)
	properties.Text = text
	properties.Font = Enum.Font.GothamBold
	properties.TextSize = properties.TextSize or 14
	properties.TextColor3 = palette.Text
	properties.BackgroundColor3 = properties.BackgroundColor3 or palette.Panel
	properties.BackgroundTransparency = 0.06
	properties.BorderSizePixel = 0
	properties.AutoButtonColor = true
	local object = create("TextButton", properties, parent)
	corners(object, 10)
	outline(object)
	return object
end

local gui = create("ScreenGui", {
	Name = "FerEtFiolesHUD", ResetOnSpawn = false, IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 20,
}, player:WaitForChild("PlayerGui"))
local root = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)

local heading = label(root, "FER & FIOLES", {
	Position = UDim2.fromOffset(26, 20), Size = UDim2.fromOffset(220, 26),
	Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = palette.Gold,
})
local teamLabel = label(root, "Bataille médiévale", {
	Position = UDim2.fromOffset(27, 49), Size = UDim2.fromOffset(220, 20),
	TextSize = 12, TextColor3 = palette.Muted,
})

local scorePanel = panel(root, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.fromOffset(460, 76),
})
local blueScore = label(scorePanel, "BLEUS  2/2", {
	Position = UDim2.new(0, 17, 0, 15), Size = UDim2.new(0.35, -17, 0, 25),
	Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = rgb(Config.Teams.Dawn.Color),
})
local redScore = label(scorePanel, "2/2  ROUGES", {
	Position = UDim2.new(0.65, 0, 0, 15), Size = UDim2.new(0.35, -17, 0, 25),
	Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = rgb(Config.Teams.Ember.Color),
	TextXAlignment = Enum.TextXAlignment.Right,
})
local blueWins = label(scorePanel, "0 VICTOIRE", {
	Position = UDim2.new(0, 17, 0, 2), Size = UDim2.new(0.35, -17, 0, 12),
	TextSize = 8, TextColor3 = palette.Muted,
})
local redWins = label(scorePanel, "0 VICTOIRE", {
	Position = UDim2.new(0.65, 0, 0, 2), Size = UDim2.new(0.35, -17, 0, 12),
	TextSize = 8, TextColor3 = palette.Muted, TextXAlignment = Enum.TextXAlignment.Right,
})
local timerLabel = label(scorePanel, "--:--", {
	Position = UDim2.new(0.35, 0, 0, 10), Size = UDim2.new(0.3, 0, 0, 30),
	TextSize = 25, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center,
})
local phaseLabel = label(scorePanel, "Connexion à la bataille…", {
	Position = UDim2.new(0, 10, 0, 47), Size = UDim2.new(1, -20, 0, 17),
	TextSize = 11, TextColor3 = palette.Muted, TextXAlignment = Enum.TextXAlignment.Center,
})
local scoresButton = button(root, "JOUEURS · TAB", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 23),
	Size = UDim2.fromOffset(141, 36), TextSize = 11,
})

local vitals = panel(root, {
	Position = UDim2.new(0, 24, 1, -145), Size = UDim2.fromOffset(290, 118),
})
local function makeBar(y, title, color)
	local titleLabel = label(vitals, title, {
		Position = UDim2.fromOffset(15, y), Size = UDim2.new(1, -30, 0, 18), TextSize = 11,
	})
	local number = label(vitals, "100 / 100", {
		Position = UDim2.fromOffset(15, y), Size = UDim2.new(1, -30, 0, 18),
		TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
	})
	local track = create("Frame", {
		Position = UDim2.fromOffset(15, y + 23), Size = UDim2.new(1, -30, 0, 9),
		BackgroundColor3 = palette.Inset, BorderSizePixel = 0, ClipsDescendants = true,
	}, vitals)
	corners(track, 5)
	local fill = create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0,
	}, track)
	corners(fill, 5)
	return { Title = titleLabel, Number = number, Fill = fill }
end
local healthBar = makeBar(11, worldMode and "HEALTH" or "SANTÉ", palette.Health)
local staminaBar = makeBar(62, worldMode and "STAMINA" or "ENDURANCE", palette.Gold)
local protectionLabel = label(root, worldMode and "SPAWN PROTECTION" or "PROTECTION DE DÉBUT DE MANCHE", {
	Position = UDim2.new(0, 25, 1, -171), Size = UDim2.fromOffset(300, 20),
	TextSize = 10, TextColor3 = palette.Gold, Visible = false,
})

local hotbar = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -25),
	Size = UDim2.fromOffset(300, 89), BackgroundTransparency = 1,
}, root)
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, hotbar)
local potionButtons = {}
for order, size in ipairs(Config.PotionOrder) do
	local potion = Config.Potions[size]
	local slot = button(hotbar, "", { Size = UDim2.fromOffset(94, 89), LayoutOrder = order })
	local accent = rgb(potion.Color)
	label(slot, potion.Key, {
		Position = UDim2.fromOffset(9, 7), Size = UDim2.fromOffset(20, 17),
		TextSize = 12, TextColor3 = palette.Gold, Font = Enum.Font.GothamBold,
	})
	local count = label(slot, "×" .. potion.Count, {
		Position = UDim2.new(1, -34, 0, 7), Size = UDim2.fromOffset(25, 17),
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
	})
	-- A small geometric bottle, using only native GUI primitives.
	local bottle = create("Frame", {
		Position = UDim2.new(0.5, -9, 0, 23), Size = UDim2.fromOffset(18, 23),
		BackgroundColor3 = accent, BorderSizePixel = 0,
	}, slot)
	corners(bottle, 5)
	create("Frame", {
		Position = UDim2.new(0.5, -4, 0, 19), Size = UDim2.fromOffset(8, 7),
		BackgroundColor3 = accent, BorderSizePixel = 0,
	}, slot)
	create("Frame", {
		Position = UDim2.new(0.5, -5, 0, 17), Size = UDim2.fromOffset(10, 4),
		BackgroundColor3 = palette.Gold, BorderSizePixel = 0,
	}, slot)
	label(slot, worldMode and size or potion.Name, {
		Position = UDim2.new(0, 3, 0, 51), Size = UDim2.new(1, -6, 0, 16),
		TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center,
	})
	label(slot, "+" .. potion.Heal .. (worldMode and " HP" or " PV"), {
		Position = UDim2.new(0, 3, 0, 68), Size = UDim2.new(1, -6, 0, 14),
		TextSize = 10, TextColor3 = accent, TextXAlignment = Enum.TextXAlignment.Center,
	})
	local cooldown = label(slot, "60 s", {
		Position = UDim2.fromOffset(6, 22), Size = UDim2.new(1, -12, 0, 27),
		TextSize = 16, Font = Enum.Font.GothamBold, TextColor3 = palette.Gold,
		TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 3,
	})
	cooldown.BackgroundColor3 = palette.Inset
	cooldown.BackgroundTransparency = 0.05
	corners(cooldown, 5)
	potionButtons[size] = { Button = slot, Count = count, Cooldown = cooldown }
end

local helpLabel = label(root, worldMode and "CLICK  Sword · SHIFT  Sprint · CTRL  Camera\nE  Gather · M  Kingdoms and outposts\nZ / X / C  Potions · shared cooldown 60 s"
	or "CLIC  Frapper · −10 endurance\nMAJ  Courir · −1 endurance/s · CTRL  Caméra\nZ / X / C  Potions · délai commun 60 s", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -26, 1, -32),
	Size = UDim2.fromOffset(290, 66), TextSize = 12, TextColor3 = palette.Muted,
	TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center,
})
local attackButton = button(root, worldMode and "SWING\n−10" or "FRAPPER\n−10", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -26, 1, -182),
	Size = UDim2.fromOffset(91, 77), TextSize = 13, Visible = false,
})
local sprintButton = button(root, worldMode and "SPRINT\nhold" or "COURIR\nmaintenir", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -128, 1, -164),
	Size = UDim2.fromOffset(85, 63), TextSize = 11, Visible = false,
})

local crosshair = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(4, 4), BackgroundColor3 = palette.Text,
	BackgroundTransparency = 0.2, BorderSizePixel = 0,
}, root)
corners(crosshair, 2)
local hitMarker = label(root, "", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -31),
	Size = UDim2.fromOffset(120, 25), TextColor3 = palette.Gold,
	TextSize = 20, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center,
})
local swingStatus = label(root, "", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 22),
	Size = UDim2.fromOffset(160, 20), TextSize = 10, TextColor3 = palette.Muted,
	TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
})
local damageFlash = create("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = palette.Danger,
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 8,
}, root)

local toast = panel(root, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 105),
	Size = UDim2.fromOffset(390, 42), Visible = false, ZIndex = worldMode and 60 or 12,
})
local toastText = label(toast, "", {
	Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 1, -8),
	TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = worldMode and 61 or 13,
})
local feed = create("Frame", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 103),
	Size = UDim2.fromOffset(300, 180), BackgroundTransparency = 1,
}, root)
create("UIListLayout", {
	Padding = UDim.new(0, 5), HorizontalAlignment = Enum.HorizontalAlignment.Right,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, feed)
local feedOrder = 0

local deathPanel = panel(root, {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.39),
	Size = UDim2.fromOffset(360, 114), Visible = false, ZIndex = 15,
})
local deathTitle = label(deathPanel, "ÉLIMINÉ", {
	Position = UDim2.fromOffset(15, 15), Size = UDim2.new(1, -30, 0, 25),
	TextSize = 21, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = palette.Gold, ZIndex = 16,
})
local respawnLabel = label(deathPanel, "Retour au lobby après le combat", {
	Position = UDim2.fromOffset(15, 49), Size = UDim2.new(1, -30, 0, 52),
	TextSize = 12, TextColor3 = palette.Muted, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 16,
})

local scoreboard = panel(root, {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46),
	Size = UDim2.fromOffset(540, 410), Visible = false, ZIndex = 30,
})
label(scoreboard, "LES COMBATTANTS", {
	Position = UDim2.fromOffset(21, 18), Size = UDim2.new(1, -74, 0, 26),
	TextSize = 19, TextColor3 = palette.Gold, Font = Enum.Font.GothamBold, ZIndex = 31,
})
local closeScores = button(scoreboard, "×", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -15, 0, 14),
	Size = UDim2.fromOffset(32, 32), TextSize = 22, ZIndex = 32,
})
label(scoreboard, "JOUEUR", {
	Position = UDim2.fromOffset(22, 62), Size = UDim2.new(0.62, -22, 0, 20),
	TextSize = 10, TextColor3 = palette.Muted, ZIndex = 31,
})
label(scoreboard, "KILLS        MORTS", {
	Position = UDim2.new(0.62, 0, 0, 62), Size = UDim2.new(0.38, -22, 0, 20),
	TextSize = 10, TextColor3 = palette.Muted, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 31,
})
local scoreRows = create("ScrollingFrame", {
	Position = UDim2.fromOffset(15, 89), Size = UDim2.new(1, -30, 1, -112),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
	ScrollBarImageColor3 = palette.Gold, CanvasSize = UDim2.new(), ZIndex = 31,
}, scoreboard)
local rowLayout = create("UIListLayout", { Padding = UDim.new(0, 5) }, scoreRows)
rowLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scoreRows.CanvasSize = UDim2.fromOffset(0, rowLayout.AbsoluteContentSize.Y)
end)

local character = player.Character
local humanoid
local deadAt
local snapshot
local worldSnapshot
local receivedAt = 0
local shiftHeld = {}
local touchSprintInput
local sprinting = false
local lastAttack = -math.huge
local toastId = 0
local markerId = 0
local compact = false
local deathConnection
local cameraWasSpectating = false
local spectatorTarget
local watchingName
local lobbyUI
local cameraLock = CameraLock.new(player)
local lockButton = button(root, "CAMÉRA\nLIBRE", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -330),
	Size = UDim2.fromOffset(85, 49), TextSize = 10, Visible = UserInputService.TouchEnabled,
})
lockButton.Activated:Connect(function() cameraLock:Toggle() end)

local function activity()
	return player:GetAttribute("Activity") or "Lobby"
end

local function menuOpen()
	return scoreboard.Visible or (lobbyUI ~= nil and lobbyUI:IsOpen())
end

local function alive()
	return character ~= nil and character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function canAct()
	local activeSession = worldMode and activity() == "World" and character and character:GetAttribute("Combatant") == true
		or (not worldMode and activity() == "Battle" and snapshot ~= nil and snapshot.Phase == "Battle")
	return alive() and activeSession and not menuOpen()
		and player:GetAttribute("Spectating") ~= true and player:GetAttribute("Eliminated") ~= true
end

local function potionCooldown()
	local readyAt = character and character:GetAttribute("PotionReadyAt")
	if type(readyAt) ~= "number" then return 0 end
	return math.max(0, math.ceil(readyAt - workspace:GetServerTimeNow()))
end

local function setSprint(active)
	active = active and canAct() and true or false
	if sprinting == active then return end
	sprinting = active
	Action:FireServer("Sprint", { Active = active })
	sprintButton.BackgroundColor3 = active and Color3.fromRGB(95, 79, 45) or palette.Panel
end

local function releaseSprint()
	table.clear(shiftHeld)
	touchSprintInput = nil
	setSprint(false)
end

local function showToast(message)
	if type(message) ~= "string" or message == "" then return end
	toastId += 1
	local id = toastId
	toastText.Text = message
	toast.Visible = true
	task.delay(3.2, function()
		if toastId == id then toast.Visible = false end
	end)
end

local function attack()
	if not canAct() or UserInputService:GetFocusedTextBox() then return end
	local now = os.clock()
	if now - lastAttack < Config.Combat.AttackCooldown then return end
	lastAttack = now
	local camera = workspace.CurrentCamera
	local direction = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		direction = rootPart and rootPart.CFrame.LookVector or Vector3.new(0, 0, -1)
	end
	Action:FireServer("Attack", { Aim = direction.Unit })
end

local function drink(size)
	if canAct() and potionCooldown() == 0 and not UserInputService:GetFocusedTextBox() then
		Action:FireServer("Potion", { Size = size })
	end
end

for size, entry in pairs(potionButtons) do
	entry.Button.Activated:Connect(function() drink(size) end)
end
attackButton.Activated:Connect(attack)
sprintButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		touchSprintInput = input
		setSprint(true)
	end
end)

local function statValue(subject, name)
	local stats = subject:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild(name)
	return value and value.Value or 0
end

local function refreshScoreboard()
	for _, row in ipairs(scoreRows:GetChildren()) do
		if row:IsA("Frame") then row:Destroy() end
	end
	local allPlayers = Players:GetPlayers()
	table.sort(allPlayers, function(a, b)
		local aKills, bKills = statValue(a, "Kills"), statValue(b, "Kills")
		if aKills == bKills then return a.Name < b.Name end
		return aKills > bKills
	end)
	for index, subject in ipairs(allPlayers) do
		local team = Config.Teams[subject:GetAttribute("TeamId")]
		local row = create("Frame", {
			Size = UDim2.new(1, -5, 0, 39), BorderSizePixel = 0,
			BackgroundColor3 = subject == player and Color3.fromRGB(48, 49, 45) or palette.Inset,
			BackgroundTransparency = 0.15, LayoutOrder = index, ZIndex = 32,
		}, scoreRows)
		corners(row, 5)
		create("Frame", {
			Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(0, 6),
			BackgroundColor3 = team and rgb(team.Color) or palette.Muted, BorderSizePixel = 0, ZIndex = 33,
		}, row)
		label(row, subject.DisplayName .. (subject == player and " · vous" or ""), {
			Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.68, -18, 1, 0),
			TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 33,
		})
		label(row, tostring(statValue(subject, "Kills")), {
			Position = UDim2.new(0.68, 0, 0, 0), Size = UDim2.new(0.15, 0, 1, 0),
			TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 33,
		})
		label(row, tostring(statValue(subject, "Deaths")), {
			Position = UDim2.new(0.83, 0, 0, 0), Size = UDim2.new(0.17, -5, 1, 0),
			TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 33,
		})
	end
	scoreRows.CanvasSize = UDim2.fromOffset(0, rowLayout.AbsoluteContentSize.Y)
end

local function showScoreboard(visible)
	scoreboard.Visible = visible
	cameraLock:SetMenuOpen(menuOpen())
	if visible then releaseSprint() refreshScoreboard() end
end
scoresButton.Activated:Connect(function() showScoreboard(not scoreboard.Visible) end)
closeScores.Activated:Connect(function() showScoreboard(false) end)

if worldMode then
	local WorldUI = require(script.Parent:WaitForChild("WorldUI"))
	lobbyUI = WorldUI.new(player, root, Action, Config, function(open)
		if open then releaseSprint() end
		cameraLock:SetMenuOpen(open or scoreboard.Visible)
	end)
	World.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then return end
		worldSnapshot = state
		lobbyUI:SetWorld(state)
	end)
else
	lobbyUI = LobbyUI.new(player, root, Action, Config, Catalog, function(open)
		if open then releaseSprint() end
		cameraLock:SetMenuOpen(open or scoreboard.Visible)
	end)
	Lobby.OnClientEvent:Connect(function(lobby) lobbyUI:SetLobby(lobby) end)
	Profile.OnClientEvent:Connect(function(profile) lobbyUI:SetProfile(profile) end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		attack()
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		if menuOpen() then return end
		shiftHeld[input.KeyCode] = true
		setSprint(true)
	elseif input.KeyCode == Enum.KeyCode.Z then drink("Small")
	elseif input.KeyCode == Enum.KeyCode.X then drink("Medium")
	elseif input.KeyCode == Enum.KeyCode.C then drink("Large")
	elseif input.KeyCode == Enum.KeyCode.Tab then showScoreboard(true)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		shiftHeld[input.KeyCode] = nil
		setSprint(next(shiftHeld) ~= nil or touchSprintInput ~= nil)
	end
	if input == touchSprintInput then
		touchSprintInput = nil
		setSprint(next(shiftHeld) ~= nil)
	end
	if input.KeyCode == Enum.KeyCode.Tab then showScoreboard(false) end
end)
UserInputService.WindowFocusReleased:Connect(function()
	releaseSprint()
	showScoreboard(false)
end)
UserInputService.TextBoxFocused:Connect(releaseSprint)

local function bindCharacter(model)
	releaseSprint()
	if deathConnection then deathConnection:Disconnect() end
	character = model
	humanoid = nil
	deadAt = nil
	deathPanel.Visible = false
	lastAttack = -math.huge
	local found = model:WaitForChild("Humanoid", 10)
	if character ~= model or not found or not found:IsA("Humanoid") then return end
	humanoid = found
	local camera = workspace.CurrentCamera
	if camera and (activity() == "Lobby" or player:GetAttribute("Spectating") ~= true) then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = found
		cameraWasSpectating = false
		spectatorTarget = nil
		watchingName = nil
	end
	deathConnection = found.Died:Connect(function()
		deadAt = os.clock()
		releaseSprint()
		showScoreboard(false)
	end)
end
player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(function(model)
	if character == model then
		releaseSprint()
		character = nil
		humanoid = nil
	end
end)
if character then task.spawn(bindCharacter, character) end

local function layout()
	local viewport = root.AbsoluteSize
	compact = viewport.X < 900 or (UserInputService.TouchEnabled and viewport.X < 1200)
	local touch = UserInputService.TouchEnabled
	local narrowTouch = touch and viewport.X < 560
	heading.Visible = not compact
	teamLabel.Visible = not compact
	helpLabel.Visible = not touch and not compact
	attackButton.Visible = touch and activity() == "Battle"
	sprintButton.Visible = touch and activity() == "Battle"
	lockButton.Visible = touch
	lockButton.Position = UDim2.new(1, -26, 1, narrowTouch and -326 or -263)
	if worldMode and narrowTouch then
		lockButton.AnchorPoint = Vector2.new(1, 0)
		lockButton.Position = UDim2.new(1, -16, 0, 132)
		lockButton.Size = UDim2.fromOffset(65, 49)
	else
		lockButton.AnchorPoint = Vector2.new(1, 1)
		lockButton.Size = UDim2.fromOffset(85, 49)
	end
	scorePanel.Size = UDim2.fromOffset(math.min(compact and 390 or 460, viewport.X - 30), compact and 66 or 76)
	blueScore.TextSize = compact and 15 or 20
	redScore.TextSize = compact and 15 or 20
	phaseLabel.Position = UDim2.new(0, 10, 0, compact and 43 or 47)
	phaseLabel.TextSize = compact and 10 or 11
	scoresButton.Text = worldMode and (compact and "PLAYERS" or "PLAYERS · TAB") or (compact and "JOUEURS" or "JOUEURS · TAB")
	scoresButton.Size = UDim2.fromOffset(compact and 87 or 141, 33)
	scoresButton.Position = UDim2.new(1, -16, 0, compact and 88 or 23)
	vitals.Size = UDim2.fromOffset(compact and math.min(245, math.max(150, viewport.X - 120)) or 290, compact and 92 or 118)
	if compact then
		vitals.AnchorPoint = Vector2.new(0, 0)
		vitals.Position = UDim2.fromOffset(15, 88)
		staminaBar.Title.Position = UDim2.fromOffset(15, 48)
		staminaBar.Number.Position = UDim2.fromOffset(15, 48)
		staminaBar.Fill.Parent.Position = UDim2.fromOffset(15, 71)
		protectionLabel.Position = UDim2.fromOffset(17, 184)
	else
		vitals.AnchorPoint = Vector2.new(0, 0)
		vitals.Position = UDim2.new(0, 24, 1, -145)
		staminaBar.Title.Position = UDim2.fromOffset(15, 62)
		staminaBar.Number.Position = UDim2.fromOffset(15, 62)
		staminaBar.Fill.Parent.Position = UDim2.fromOffset(15, 85)
		protectionLabel.Position = UDim2.new(0, 25, 1, -171)
	end
	local slotWidth = narrowTouch and math.min(70, math.max(42, math.floor((viewport.X - 160) / 3))) or (compact and 75 or 94)
	hotbar.Size = UDim2.fromOffset((slotWidth + 8) * 3, 89)
	hotbar.AnchorPoint = Vector2.new(narrowTouch and 0 or 0.5, 1)
	hotbar.Position = UDim2.new(0.5, 0, 1, touch and -14 or -25)
	if narrowTouch then hotbar.Position = UDim2.new(0, 15, 1, -160) end
	attackButton.Position = UDim2.new(1, -26, 1, narrowTouch and -160 or -182)
	sprintButton.Position = UDim2.new(1, narrowTouch and -26 or -128, 1, narrowTouch and -247 or -164)
	for _, entry in pairs(potionButtons) do entry.Button.Size = UDim2.fromOffset(slotWidth, 89) end
	toast.Size = UDim2.fromOffset(math.min(390, viewport.X - 30), 42)
	toast.Position = UDim2.new(0.5, 0, 0, compact and 207 or 105)
	feed.Visible = not (compact and viewport.Y < 500)
	feed.Position = UDim2.new(1, -16, 0, viewport.X < 560 and 255 or (compact and 129 or 103))
	feed.Size = UDim2.fromOffset(compact and math.max(150, math.min(230, viewport.X - 285)) or 300, compact and 72 or 180)
	scoreboard.Size = UDim2.fromOffset(math.min(540, viewport.X - 30), math.min(410, viewport.Y - 40))
	deathPanel.Size = UDim2.fromOffset(math.min(360, viewport.X - 30), 114)
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(layout)
layout()

State.OnClientEvent:Connect(function(newState)
	if type(newState) ~= "table" then return end
	snapshot = newState
	receivedAt = os.clock()
	if not canAct() then releaseSprint() end
end)
for _, attribute in ipairs({ "Spectating", "Eliminated", "Activity" }) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if not canAct() then releaseSprint() end
		if attribute == "Activity" then
			if not worldMode then lobbyUI:SetActivity(activity()) end
			if activity() == "Lobby" then
				deadAt = nil
				deathPanel.Visible = false
			end
			layout()
		end
	end)
end

local function updateSpectatorCamera()
	local camera = workspace.CurrentCamera
	if not camera then return end
	-- Lobby players always keep their own physical character and camera.
	local spectator = activity() ~= "Lobby" and (player:GetAttribute("Spectating") == true
		or player:GetAttribute("Eliminated") == true or (deadAt ~= nil and not alive()))
	cameraLock:SetSpectating(spectator)
	if not spectator then
		if cameraWasSpectating and humanoid and humanoid.Health > 0 then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
		end
		cameraWasSpectating = false
		spectatorTarget = nil
		watchingName = nil
		return
	end
	cameraWasSpectating = true
	local allied, others = {}, {}
	local teamId = player:GetAttribute("TeamId")
	for _, model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") and model ~= character and model:GetAttribute("Combatant") == true
			and (worldMode or (snapshot and model:GetAttribute("MatchRound") == snapshot.Round)) then
			local targetHumanoid = model:FindFirstChildOfClass("Humanoid")
			if targetHumanoid and targetHumanoid.Health > 0 and model:FindFirstChild("HumanoidRootPart") then
				local list = teamId ~= nil and model:GetAttribute("TeamId") == teamId and allied or others
				table.insert(list, model)
			end
		end
	end
	local candidates = #allied > 0 and allied or others
	if not table.find(candidates, spectatorTarget) then
		table.sort(candidates, function(a, b) return a.Name < b.Name end)
		spectatorTarget = candidates[1]
	end
	if spectatorTarget then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = spectatorTarget:FindFirstChildOfClass("Humanoid")
		local targetPlayer = Players:GetPlayerFromCharacter(spectatorTarget)
		watchingName = targetPlayer and targetPlayer.DisplayName or spectatorTarget.Name
	else
		-- With no survivors, keep a clear overview until the next characters are spawned.
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 55, 70), Vector3.new(0, 4, 0))
		watchingName = nil
	end
end

local effectFolder = Instance.new("Folder")
effectFolder.Name = "LocalBattleEffects"
effectFolder.Parent = workspace
local activeEffects = 0
local function effectPart(color, cframe, size, duration, expand)
	if activeEffects >= 70 then return end
	activeEffects += 1
	local part = create("Part", {
		Name = "BattleSpark", Anchored = true, CanCollide = false, CanTouch = false,
		CanQuery = false, CastShadow = false, Material = Enum.Material.Neon,
		Color = color, Size = size, CFrame = cframe, Transparency = 0.15,
	}, effectFolder)
	local target = { Transparency = 1 }
	if expand then target.Size = size * expand end
	TweenService:Create(part, TweenInfo.new(duration), target):Play()
	Debris:AddItem(part, duration + 0.05)
	task.delay(duration + 0.06, function() activeEffects -= 1 end)
	return part
end

local function effectPosition(data)
	if typeof(data.Position) == "Vector3" then return data.Position end
	local model = data.Target or data.Actor
	if typeof(model) == "Instance" and model:IsA("Model") then
		local part = model:FindFirstChild("HumanoidRootPart")
		if part then return part.Position end
	end
	return nil
end

Effects.OnClientEvent:Connect(function(kind, data)
	if type(data) ~= "table" then return end
	if kind == "Toast" then
		showToast(data.Text)
	elseif kind == "Killfeed" then
		if activity() == "Lobby" then return end
		feedOrder += 1
		local line = label(feed, tostring(data.Killer or "Un combattant") .. "  >  " .. tostring(data.Victim or "un adversaire"), {
			Size = UDim2.new(1, 0, 0, 23), BackgroundColor3 = palette.Inset,
			TextSize = compact and 10 or 12, TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = -feedOrder,
		})
		line.BackgroundTransparency = 0.15
		corners(line, 4)
		Debris:AddItem(line, 5)
		local lines = {}
		for _, child in ipairs(feed:GetChildren()) do
			if child:IsA("TextLabel") then table.insert(lines, child) end
		end
		table.sort(lines, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for index = compact and 3 or 6, #lines do lines[index]:Destroy() end
	elseif kind == "Swing" then
		local actor = data.Actor
		local rootPart = typeof(actor) == "Instance" and actor:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end
		local forward = typeof(data.Direction) == "Vector3" and data.Direction or rootPart.CFrame.LookVector
		forward = Vector3.new(forward.X, 0, forward.Z)
		if forward.Magnitude < 0.01 then return end
		forward = forward.Unit
		local right = forward:Cross(Vector3.yAxis)
		local center = rootPart.Position + Vector3.new(0, 0.6, 0)
		local team = Config.Teams[actor:GetAttribute("TeamId")]
		local color = team and rgb(team.Color) or palette.Gold
		for segment = 0, 5 do
			local side = data.Side == -1 and -1 or 1
			local a = math.rad((-55 + segment * 18) * side)
			local b = math.rad((-55 + (segment + 1) * 18) * side)
			local p1 = center + (forward * math.cos(a) + right * math.sin(a)) * 3.8
			local p2 = center + (forward * math.cos(b) + right * math.sin(b)) * 3.8
			task.delay(segment * 0.014, function()
				effectPart(color, CFrame.lookAt((p1 + p2) / 2, p2), Vector3.new(0.07, 0.07, (p2 - p1).Magnitude), 0.2)
			end)
		end
	elseif kind == "Hit" then
		local position = effectPosition(data)
		if position then
			local spark = effectPart(palette.Gold, CFrame.new(position + Vector3.new(0, 1, 0)), Vector3.new(0.4, 0.4, 0.4), 0.19, 2)
			if spark then spark.Shape = Enum.PartType.Ball end
		end
		if data.Actor == character then
			markerId += 1
			local id = markerId
			hitMarker.Text = tostring(data.Damage or Config.Combat.AttackDamage)
			task.delay(0.5, function() if id == markerId then hitMarker.Text = "" end end)
		end
		if data.Target == character then
			damageFlash.BackgroundTransparency = 0.86
			TweenService:Create(damageFlash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		end
	elseif kind == "Potion" then
		local position = effectPosition(data)
		if not position then return end
		local potion = Config.Potions[data.Size] or Config.Potions.Small
		for index = 1, 5 do
			local angle = index * math.pi * 0.4
			local p = position + Vector3.new(math.cos(angle) * 1.3, 0.4 + index * 0.25, math.sin(angle) * 1.3)
			local spark = effectPart(rgb(potion.Color), CFrame.new(p), Vector3.new(0.23, 0.23, 0.23), 0.65, 0.4)
			if spark then
				spark.Shape = Enum.PartType.Ball
				TweenService:Create(spark, TweenInfo.new(0.65), { Position = p + Vector3.new(0, 2, 0) }):Play()
			end
		end
	end
end)

local updateElapsed = 0
local scoreElapsed = 0
local cameraElapsed = 0
RunService.Heartbeat:Connect(function(dt)
	updateElapsed += dt
	scoreElapsed += dt
	cameraElapsed += dt
	if cameraElapsed >= 0.3 then
		cameraElapsed = 0
		updateSpectatorCamera()
	end
	if scoreElapsed > 1 and scoreboard.Visible then
		scoreElapsed = 0
		refreshScoreboard()
	end
	if updateElapsed < 0.08 then return end
	updateElapsed = 0
	lobbyUI:Step()
	cameraLock:SetMenuOpen(menuOpen())
	lockButton.Text = cameraLock.Enabled and "CAMÉRA\nVERROUILLÉE" or "CAMÉRA\nLIBRE"
	local inLobby = activity() == "Lobby"
	scorePanel.Visible = not inLobby and not worldMode
	vitals.Visible = not inLobby
	hotbar.Visible = not inLobby
	attackButton.Visible = UserInputService.TouchEnabled and not inLobby
	sprintButton.Visible = UserInputService.TouchEnabled and not inLobby
	helpLabel.Visible = not compact and not UserInputService.TouchEnabled and not inLobby
	feed.Visible = not inLobby and not worldMode and not (compact and root.AbsoluteSize.Y < 500)
	local maxHealth = humanoid and humanoid.MaxHealth or Config.Player.MaxHealth
	local health = humanoid and math.max(0, humanoid.Health) or 0
	local maxStamina = character and character:GetAttribute("MaxStamina") or Config.Combat.MaxStamina
	local stamina = character and character:GetAttribute("Stamina") or maxStamina
	maxStamina = math.max(1, maxStamina)
	healthBar.Number.Text = string.format("%d / %d", math.ceil(health), maxHealth)
	healthBar.Fill.Size = UDim2.fromScale(math.clamp(health / math.max(1, maxHealth), 0, 1), 1)
	healthBar.Fill.BackgroundColor3 = health <= maxHealth * 0.25 and palette.Danger or palette.Health
	staminaBar.Number.Text = string.format("%d / %d", math.floor(stamina + 0.5), maxStamina)
	staminaBar.Fill.Size = UDim2.fromScale(math.clamp(stamina / maxStamina, 0, 1), 1)
	staminaBar.Fill.BackgroundColor3 = stamina < Config.Combat.AttackCost and palette.Danger or palette.Gold
	staminaBar.Title.Text = worldMode
		and (character and character:GetAttribute("Sprinting") and "STAMINA · SPRINTING" or "STAMINA")
		or (character and character:GetAttribute("Sprinting") and "ENDURANCE · COURSE" or "ENDURANCE")
	protectionLabel.Visible = not inLobby and alive() and character:GetAttribute("SpawnProtected") == true
	local actionable = canAct()
	if worldMode then
		local serverNow = workspace:GetServerTimeNow()
		local regenAt = character and character:GetAttribute("HealthRegenReadyAt")
		healthBar.Title.Text = health < maxHealth and health > 0 and type(regenAt) == "number" and serverNow >= regenAt
			and "HEALTH · RECOVERING" or "HEALTH"
		local attackAt = character and character:GetAttribute("AttackReadyAt")
		local cooldown = type(attackAt) == "number" and math.max(0, attackAt - serverNow) or 0
		swingStatus.Visible = actionable
		swingStatus.Text = cooldown > 0 and string.format("SWING · %.1f s", cooldown) or "SWORD READY"
	end
	local remainingCooldown = potionCooldown()
	attackButton.Interactable = actionable
	sprintButton.Interactable = actionable
	attackButton.AutoButtonColor = actionable
	sprintButton.AutoButtonColor = actionable
	for size, entry in pairs(potionButtons) do
		local count = character and character:GetAttribute("Potions" .. size)
		if type(count) ~= "number" then count = Config.Potions[size].Count end
		local available = actionable and count > 0 and remainingCooldown == 0
		entry.Count.Text = "×" .. count
		entry.Button.BackgroundColor3 = available and palette.Panel or palette.Inset
		entry.Button.Interactable = available
		entry.Button.AutoButtonColor = available
		entry.Count.TextColor3 = available and palette.Text or palette.Muted
		entry.Cooldown.Visible = remainingCooldown > 0
		entry.Cooldown.Text = tostring(remainingCooldown) .. " s"
	end
	local team = Config.Teams[player:GetAttribute("TeamId")]
	teamLabel.Text = worldMode and (team and ("Kingdom · " .. team.Name) or "Choose your kingdom")
		or (inLobby and "Lobby · combats sur invitation" or (team and ("Votre équipe · " .. team.Name) or "Combat en cours"))
	teamLabel.TextColor3 = team and rgb(team.Color) or palette.Muted
	local dead = humanoid ~= nil and humanoid.Health <= 0
	if dead and not deadAt then deadAt = os.clock() end
	local eliminated = not inLobby and (player:GetAttribute("Eliminated") == true or (deadAt ~= nil and not alive()))
	local spectating = not inLobby and player:GetAttribute("Spectating") == true
	deathPanel.Visible = not worldMode and (eliminated or spectating)
	crosshair.Visible = actionable
	if eliminated or spectating then
		deathTitle.Text = eliminated and (worldMode and "FALLEN IN BATTLE" or "ÉLIMINÉ") or "SPECTATEUR"
		if worldMode then
			local readyAt = worldSnapshot and worldSnapshot.RespawnAt
			local seconds = type(readyAt) == "number" and math.max(0, math.ceil(readyAt - workspace:GetServerTimeNow())) or 0
			respawnLabel.Text = seconds > 0 and ("Returning to your kingdom in " .. seconds .. " s") or "Preparing your next life…"
		else
			respawnLabel.Text = (watchingName and ("Vous regardez " .. watchingName .. ".\n") or "")
				.. "Retour au lobby à la fin du combat."
		end
	end
	if snapshot and not inLobby then
		local scores = snapshot.Scores or {}
		local survivors = snapshot.Alive or {}
		local teamSize = snapshot.TeamSize or Config.Game.TeamSize or 2
		blueScore.Text = "BLEUS  " .. tostring(survivors.Dawn or 0) .. "/" .. teamSize
		redScore.Text = tostring(survivors.Ember or 0) .. "/" .. teamSize .. "  ROUGES"
		blueWins.Text = tostring(scores.Dawn or 0) .. ((scores.Dawn or 0) > 1 and " VICTOIRES" or " VICTOIRE")
		redWins.Text = tostring(scores.Ember or 0) .. ((scores.Ember or 0) > 1 and " VICTOIRES" or " VICTOIRE")
		local elapsedSinceState = os.clock() - receivedAt
		local seconds
		if snapshot.Phase == "Battle" then
			seconds = math.max(0, math.floor((tonumber(snapshot.Elapsed) or 0) + elapsedSinceState))
		else
			seconds = math.max(0, math.ceil((tonumber(snapshot.TimeLeft) or 0) - elapsedSinceState))
		end
		timerLabel.Text = string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
		if snapshot.Phase == "Results" then
			local winner = Config.Teams[snapshot.Winner]
			phaseLabel.Text = "COMBAT TERMINÉ · RETOUR AU LOBBY"
			deathPanel.Visible = true
			deathTitle.Text = winner and (snapshot.Winner == player:GetAttribute("TeamId") and "VICTOIRE !" or "DÉFAITE") or "FIN DU COMBAT"
			local message = type(snapshot.Message) == "string" and snapshot.Message ~= "" and snapshot.Message
				or (winner and ("Les " .. winner.Name .. " remportent le combat.") or "Le combat est terminé.")
			respawnLabel.Text = message .. "\nRetour au lobby dans " .. seconds .. " s."
		elseif snapshot.Phase == "Preparing" then
			phaseLabel.Text = "PRÉPARATION · " .. tostring(teamSize) .. " CONTRE " .. tostring(teamSize)
			deathPanel.Visible = true
			deathTitle.Text = "PRÉPAREZ-VOUS"
			respawnLabel.Text = "Chargement des combattants…\nPréparation · " .. seconds .. " s restantes."
		else
			phaseLabel.Text = tostring(teamSize) .. " CONTRE " .. tostring(teamSize) .. " · DERNIÈRE ÉQUIPE EN VIE"
		end
	end
end)

Action:FireServer("Ready", {})
