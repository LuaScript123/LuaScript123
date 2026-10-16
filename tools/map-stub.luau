-- Minimal deterministic Roblox primitives for exporting MapBuilder in the CLI.
-- This file is joined with Config and MapBuilder by export-map.py, not used in-game.
local VectorMethods = {}
local VectorMT = { __index = VectorMethods }
local Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, VectorMT) end
VectorMT.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
VectorMT.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
VectorMT.__mul = function(a, b)
    if type(a) == "number" then a, b = b, a end
    return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end

local CFrame = {}
local FrameMT = {}
function CFrame.new(x, y, z)
    if type(x) == "table" then x, y, z = x.X, x.Y, x.Z end
    return setmetatable({ Position = Vector3.new(x or 0, y or 0, z or 0), Rotation = { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, FrameMT)
end
function CFrame.Angles(x, y, z)
    local sx, sy, sz, cx, cy, cz = math.sin(x), math.sin(y), math.sin(z), math.cos(x), math.cos(y), math.cos(z)
    local frame = CFrame.new()
    frame.Rotation = { cy * cz, -cy * sz, sy, cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy,
        sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy }
    return frame
end
function CFrame.lookAt(position, target)
    local frame = CFrame.new(position)
    local delta = target - position
    local magnitude = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
    assert(magnitude > 0 and delta.Y == 0, "Exporter currently supports horizontal spawn directions")
    local lx, lz = delta.X / magnitude, delta.Z / magnitude
    frame.Rotation = { -lz, 0, -lx, 0, 1, 0, lx, 0, -lz }
    return frame
end
FrameMT.__mul = function(a, b)
    local ar, br = a.Rotation, b.Rotation
    local frame = CFrame.new(a.Position + Vector3.new(
        ar[1] * b.Position.X + ar[2] * b.Position.Y + ar[3] * b.Position.Z,
        ar[4] * b.Position.X + ar[5] * b.Position.Y + ar[6] * b.Position.Z,
        ar[7] * b.Position.X + ar[8] * b.Position.Y + ar[9] * b.Position.Z))
    for row = 0, 2 do
        for col = 1, 3 do
            frame.Rotation[row * 3 + col] = ar[row * 3 + 1] * br[col]
                + ar[row * 3 + 2] * br[3 + col] + ar[row * 3 + 3] * br[6 + col]
        end
    end
    return frame
end

local Color3 = {}
local ColorMT = { __index = Color3 }
function Color3.fromRGB(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, ColorMT) end
function Color3:Lerp(other, alpha)
    return Color3.fromRGB((self.R + (other.R - self.R) * alpha) * 255,
        (self.G + (other.G - self.G) * alpha) * 255, (self.B + (other.B - self.B) * alpha) * 255)
end

-- Material numeric values from Roblox's public API enum. No network is needed.
local Enum = {
    Material = { Slate = 800, Wood = 512, Neon = 288, Fabric = 1312, Metal = 1088, Plaster = 2310,
        Glass = 1568, Grass = 1280, Cobblestone = 880, Sandstone = 912, WoodPlanks = 528 },
    SurfaceType = { Smooth = 0 },
    PartType = { Ball = 0, Block = 1, Cylinder = 2 },
}
for _, values in pairs(Enum) do
    setmetatable(values, { __index = function(_, key) error("Unknown enum value: " .. key) end })
end

local allInstances = {}
local ObjectMethods = {}
local ObjectMT = {}
local Instance = {}
function Instance.new(className)
    local object = setmetatable({ ClassName = className, Properties = { Name = className } }, ObjectMT)
    table.insert(allInstances, object)
    return object
end
function ObjectMT.__index(self, key)
    if key == "Position" then return self.Properties.CFrame.Position end
    return ObjectMethods[key] or self.Properties[key]
end
function ObjectMT.__newindex(self, key, value) self.Properties[key] = value end
function ObjectMethods:FindFirstChild(name)
    for _, item in ipairs(allInstances) do
        if item.Parent == self and item.Name == name and not item.Destroyed then return item end
    end
    return nil
end
function ObjectMethods:WaitForChild(name)
    local existing = self:FindFirstChild(name)
    if existing then return existing end
    local child = Instance.new("Folder")
    child.Name, child.Parent = name, self
    return child
end
function ObjectMethods:Destroy() self.Destroyed = true end

local workspace = Instance.new("Workspace")
local lighting = Instance.new("Lighting")
local storage = Instance.new("ReplicatedStorage")
local game = { GetService = function(_, name)
    if name == "Lighting" then return lighting end
    if name == "ReplicatedStorage" then return storage end
    error("Unexpected service: " .. name)
end }

-- An axis-aligned bounding box is sufficient to reject obstructions along the
-- protected spawn lane; cylinder and wedge bounds are conservative.
local function bounds(object)
    local half, frame = object.Size * 0.5, object.CFrame
    local r = frame.Rotation
    local extent = Vector3.new(math.abs(r[1]) * half.X + math.abs(r[2]) * half.Y + math.abs(r[3]) * half.Z,
        math.abs(r[4]) * half.X + math.abs(r[5]) * half.Y + math.abs(r[6]) * half.Z,
        math.abs(r[7]) * half.X + math.abs(r[8]) * half.Y + math.abs(r[9]) * half.Z)
    return frame.Position - extent, frame.Position + extent
end

local function validate(map)
    local count = 0
    local allSpawns = {}
    for team, positions in pairs(map.Spawns) do
        for index, spawn in ipairs(positions) do
            table.insert(allSpawns, { Name = team .. tostring(index), Position = spawn.Position })
        end
    end
    assert(map.LobbySpawns and #map.LobbySpawns == 8, "Expected eight lobby spawns")
    assert(map.LobbyCenter and map.LobbyCenter.Z >= 240, "Lobby must be separated from arena")
    for index, spawn in ipairs(map.LobbySpawns) do
        table.insert(allSpawns, { Name = "Lobby" .. tostring(index), Position = spawn.Position })
    end
    local supported = {}
    local arenaFloor, lobbyFloor
    for _, object in ipairs(allInstances) do
        if object.ClassName == "Part" or object.ClassName == "WedgePart" then
            count += 1
            if object.CanCollide then
                local minimum, maximum = bounds(object)
                if object.Name == "ArenaGround" then arenaFloor = { Min = minimum, Max = maximum } end
                if object.Name == "LobbyGround" then lobbyFloor = { Min = minimum, Max = maximum } end
                if minimum.Y < 6.2 and maximum.Y > 0.3 then
                    assert(not (maximum.X > -75 and minimum.X < 75 and minimum.Z < 12 and maximum.Z > -12),
                        "Obstacle in arena central lane: " .. object.Name)
                    local center = map.LobbyCenter
                    assert(not (maximum.X > center.X - 18 and minimum.X < center.X + 18
                        and maximum.Z > center.Z - 24 and minimum.Z < center.Z + 24),
                        "Obstacle in lobby central meeting area: " .. object.Name)
                end
                for _, spawn in ipairs(allSpawns) do
                    local p = spawn.Position
                    assert(p.Y == 3.5, "R6 spawn must use root Y=3.5: " .. spawn.Name)
                    assert(not (minimum.X < p.X + 1.5 and maximum.X > p.X - 1.5
                        and minimum.Z < p.Z + 1.5 and maximum.Z > p.Z - 1.5
                        and minimum.Y < p.Y + 2.5 and maximum.Y > p.Y - 2.5),
                        "Spawn collision: " .. spawn.Name .. " / " .. object.Name)
                    if minimum.X < p.X - 1.5 and maximum.X > p.X + 1.5
                        and minimum.Z < p.Z - 1.5 and maximum.Z > p.Z + 1.5
                        and math.abs(maximum.Y) < 0.01 then
                        supported[spawn.Name] = true
                    end
                end
            end
        end
    end
    for _, spawn in ipairs(allSpawns) do
        assert(supported[spawn.Name], "No stable floor below spawn: " .. spawn.Name)
    end
    assert(arenaFloor and lobbyFloor, "Both zones need a stable collision floor")
    assert(lobbyFloor.Min.Z - arenaFloor.Max.Z >= 100, "Lobby and arena must remain separated")
    assert(count < 1000, "Map exceeds primitive budget")
    assert(#map.Spawns.Dawn == 3 and #map.Spawns.Ember == 3, "Expected three spawns per team")
    print("<!-- Geometry verified: " .. count .. " primitives; six arena and eight lobby spawns clear and supported; both meeting lanes clear. -->")
end

local function escape(value)
    return tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end
local function number(value) return string.format("%.8g", value) end
local function colorProperty(name, color)
    return '<Color3 name="' .. name .. '"><R>' .. number(color.R) .. '</R><G>' .. number(color.G)
        .. '</G><B>' .. number(color.B) .. '</B></Color3>'
end
local function emit(object)
    print('<Item class="' .. object.ClassName .. '"><Properties>')
    print('<string name="Name">' .. escape(object.Name) .. '</string>')
    local keys = {}
    for key in pairs(object.Properties) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local value = object.Properties[key]
        if key ~= "Name" and key ~= "Parent" and key ~= "Destroyed" then
            if key == "Color" and (object.ClassName == "Part" or object.ClassName == "WedgePart") then
                local packed = 4278190080 + math.round(value.R * 255) * 65536
                    + math.round(value.G * 255) * 256 + math.round(value.B * 255)
                print('<Color3uint8 name="Color3uint8">' .. string.format("%.0f", packed) .. '</Color3uint8>')
            elseif getmetatable(value) == ColorMT then
                print(colorProperty(key, value))
            elseif getmetatable(value) == VectorMT then
                print('<Vector3 name="' .. key .. '"><X>' .. number(value.X) .. '</X><Y>' .. number(value.Y)
                    .. '</Y><Z>' .. number(value.Z) .. '</Z></Vector3>')
            elseif getmetatable(value) == FrameMT then
                local tags = { "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22" }
                local fields = '<X>' .. number(value.Position.X) .. '</X><Y>' .. number(value.Position.Y)
                    .. '</Y><Z>' .. number(value.Position.Z) .. '</Z>'
                for index, tag in ipairs(tags) do fields ..= '<' .. tag .. '>' .. number(value.Rotation[index]) .. '</' .. tag .. '>' end
                print('<CoordinateFrame name="' .. key .. '">' .. fields .. '</CoordinateFrame>')
            elseif type(value) == "boolean" then
                print('<bool name="' .. key .. '">' .. tostring(value) .. '</bool>')
            elseif type(value) == "number" then
                local tag = (key == "Material" or key == "Shape" or key == "TopSurface" or key == "BottomSurface") and "token" or "float"
                print('<' .. tag .. ' name="' .. key .. '">' .. number(value) .. '</' .. tag .. '>')
            else
                error("Unsupported export property: " .. object.ClassName .. "." .. key)
            end
        end
    end
    print('</Properties>')
    for _, child in ipairs(allInstances) do
        if child.Parent == object and not child.Destroyed then emit(child) end
    end
    print('</Item>')
end

local function export(map)
    validate(map)
    print('<roblox version="4">')
    emit(map.Model)
    print('</roblox>')
end
