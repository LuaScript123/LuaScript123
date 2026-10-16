-- Keep Roblox's camera controller; Ctrl only adds the PvP shoulder offset and facing.
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local CameraLock = {}
CameraLock.__index = CameraLock

function CameraLock.new(player)
	local self = setmetatable({
		Player = player, Enabled = false, MenuOpen = false, Spectating = false,
		WindowFocused = true, RobloxMenuOpen = false, Applied = false,
		Humanoid = nil, SavedOffset = Vector3.zero, SavedAutoRotate = true,
		Connections = {},
	}, CameraLock)
	local function connect(signal, callback)
		table.insert(self.Connections, signal:Connect(callback))
	end
	connect(UserInputService.InputBegan, function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() or self.MenuOpen or self.RobloxMenuOpen then return end
		if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then self:Toggle() end
	end)
	connect(UserInputService.WindowFocusReleased, function()
		self.WindowFocused = false
		self:_release()
	end)
	connect(UserInputService.WindowFocused, function() self.WindowFocused = true end)
	connect(UserInputService.TextBoxFocused, function() self:_release() end)
	connect(GuiService.MenuOpened, function()
		self.RobloxMenuOpen = true
		self:_release()
	end)
	connect(GuiService.MenuClosed, function() self.RobloxMenuOpen = false end)
	connect(player.CharacterRemoving, function() self:_release() end)
	self.Binding = "FerEtFiolesControlLock_" .. player.UserId
	RunService:BindToRenderStep(self.Binding, Enum.RenderPriority.Camera.Value + 1, function() self:_step() end)
	return self
end

function CameraLock:_release()
	if self.Applied then
		local humanoid = self.Humanoid
		if humanoid and humanoid.Parent then
			humanoid.CameraOffset = self.SavedOffset
			humanoid.AutoRotate = self.SavedAutoRotate
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = self.SavedMouseIcon
	end
	self.Applied = false
	self.Humanoid = nil
end

function CameraLock:_step()
	local character = self.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local active = self.Enabled and self.WindowFocused and not self.MenuOpen and not self.RobloxMenuOpen
		and not self.Spectating and not UserInputService:GetFocusedTextBox()
		and humanoid and humanoid.Health > 0 and root and camera
		and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid
	if not active then self:_release() return end
	if self.Humanoid ~= humanoid then
		self:_release()
		self.Humanoid = humanoid
		self.SavedOffset = humanoid.CameraOffset
		self.SavedAutoRotate = humanoid.AutoRotate
		self.SavedMouseIcon = UserInputService.MouseIconEnabled
	end
	self.Applied = true
	humanoid.CameraOffset = self.SavedOffset + Vector3.new(1.75, 0.25, 0)
	humanoid.AutoRotate = false
	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
	local direction = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	if direction.Magnitude > 0.001 and not root.Anchored then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + direction.Unit)
	end
end

function CameraLock:Toggle()
	self.Enabled = not self.Enabled
	if not self.Enabled then self:_release() end
	return self.Enabled
end

function CameraLock:SetMenuOpen(open)
	self.MenuOpen = open == true
	if self.MenuOpen then self:_release() end
end

function CameraLock:SetSpectating(spectating)
	self.Spectating = spectating == true
	if self.Spectating then self:_release() end
end

function CameraLock:Destroy()
	self:_release()
	RunService:UnbindFromRenderStep(self.Binding)
	for _, connection in ipairs(self.Connections) do connection:Disconnect() end
end

return CameraLock
