-- Original, asset-free kingdom battlefield. All tuning remains provisional.
-- Gameplay refs are produced by the same builder used by the static exporter.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("MedievalShared"):WaitForChild("Config"))

local WorldMapBuilder = {}
local C = {
    Grass = Color3.fromRGB(87, 111, 65), Meadow = Color3.fromRGB(73, 95, 58),
    Road = Color3.fromRGB(164, 148, 115), Stone = Color3.fromRGB(151, 145, 125),
    Dark = Color3.fromRGB(89, 94, 89), Light = Color3.fromRGB(190, 181, 152),
    Wood = Color3.fromRGB(99, 69, 43), Leaves = Color3.fromRGB(55, 94, 57),
    LeavesLight = Color3.fromRGB(75, 112, 61), Gold = Color3.fromRGB(223, 180, 94),
    Neutral = Color3.fromRGB(165, 158, 140), Ore = Color3.fromRGB(103, 144, 157),
}

function WorldMapBuilder.Build()
    local previous = workspace:FindFirstChild("FerEtFiolesArena")
    if previous then previous:Destroy() end
    local model = Instance.new("Model")
    model.Name = "FerEtFiolesArena"

    local function group(name, parent)
        local object = Instance.new("Model")
        object.Name, object.Parent = name, parent or model
        return object
    end
    local function part(name, size, frame, color, material, collidable, parent, shape)
        local object = Instance.new("Part")
        object.Name, object.Size, object.CFrame = name, size, frame
        object.Color, object.Material = color, material or Enum.Material.Slate
        object.Anchored, object.CanCollide = true, collidable ~= false
        object.TopSurface, object.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
        if shape then object.Shape = shape end
        object.Parent = parent or model
        return object
    end
    local function block(name, size, position, color, material, collidable, parent)
        return part(name, size, CFrame.new(position), color, material, collidable, parent)
    end
    local function disc(name, radius, height, position, color, material, collidable, parent)
        return part(name, Vector3.new(height, radius * 2, radius * 2),
            CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2), color, material,
            collidable, parent, Enum.PartType.Cylinder)
    end
    local function banner(parent, x, z, color, height)
        height = height or 15
        block("FlagPole", Vector3.new(0.45, height, 0.45), Vector3.new(x, height / 2, z),
            C.Wood, Enum.Material.Wood, false, parent)
        local flag = block("Flag", Vector3.new(5.5, 4, 0.2), Vector3.new(x + 2.7, height - 3, z),
            color, Enum.Material.Fabric, false, parent)
        flag.CastShadow = false
        block("FlagFinial", Vector3.new(0.8, 0.8, 0.8), Vector3.new(x, height + 0.4, z),
            C.Gold, Enum.Material.Metal, false, parent)
        return flag
    end
    local function tower(parent, x, z, color)
        disc("Tower", 5.5, 15, Vector3.new(x, 7.5, z), C.Stone, nil, true, parent)
        disc("TowerCrown", 6.1, 1, Vector3.new(x, 15.5, z), C.Light, nil, true, parent)
        for _, offset in ipairs({ Vector3.new(-3.5, 17, -3.5), Vector3.new(3.5, 17, -3.5),
            Vector3.new(-3.5, 17, 3.5), Vector3.new(3.5, 17, 3.5) }) do
            block("Merlon", Vector3.new(2.7, 2.5, 2.7), Vector3.new(x, 0, z) + offset,
                C.Light, nil, true, parent)
        end
        block("TowerPennant", Vector3.new(0.2, 5, 4), Vector3.new(x, 18, z), color,
            Enum.Material.Fabric, false, parent)
    end

    -- One continuous support plane: every battlefield ground top is exactly y=0.
    block("WorldGround", Vector3.new(600, 6, 600), Vector3.new(0, -3, 0), C.Grass, Enum.Material.Grass)
    local paths = group("Roads")
    for _, offset in ipairs({ -220, 0, 220 }) do
        block("WorldRoad", Vector3.new(444, 0.08, 16), Vector3.new(0, 0.045, offset),
            C.Road, Enum.Material.Cobblestone, false, paths)
        block("WorldRoad", Vector3.new(16, 0.08, 444), Vector3.new(offset, 0.045, 0),
            C.Road, Enum.Material.Cobblestone, false, paths)
    end
    disc("Crossroads", 30, 0.1, Vector3.new(0, 0.09, 0), C.Light, Enum.Material.Cobblestone, false, paths)
    disc("CrossroadsCompass", 11, 0.11, Vector3.new(0, 0.16, 0), C.Dark, Enum.Material.Slate, false, paths)
    for _, angle in ipairs({ 0, math.pi / 4, math.pi / 2, math.pi * 3 / 4 }) do
        part("CompassInlay", Vector3.new(0.8, 0.06, 17), CFrame.new(0, 0.25, 0) * CFrame.Angles(0, angle, 0),
            C.Gold, Enum.Material.Metal, false, paths)
    end
    -- Simple high borders protect the walkable world edge; no outside assets.
    for _, sign in ipairs({ -1, 1 }) do
        block("WorldBoundary", Vector3.new(3, 20, 600), Vector3.new(sign * 299, 10, 0), C.Dark)
        block("WorldBoundary", Vector3.new(594, 20, 3), Vector3.new(0, 10, sign * 299), C.Dark)
    end

    local centers = {
        Redcliff = Vector3.new(-220, 0, -220), Korblox = Vector3.new(220, 0, -220),
        Greywolf = Vector3.new(-220, 0, 220), Overseer = Vector3.new(220, 0, 220),
    }
    local spawns = {}
    for _, id in ipairs(Config.KingdomOrder) do
        local center = assert(centers[id], "Missing kingdom map center: " .. id)
        local tint = Color3.fromRGB(table.unpack(Config.Kingdoms[id].Color))
        local base = group(id .. "Keep")
        local sx, sz = center.X < 0 and -1 or 1, center.Z < 0 and -1 or 1
        spawns[id] = {}
        for _, offset in ipairs({ Vector3.new(-9, 3.5, -6), Vector3.new(9, 3.5, -6),
            Vector3.new(-9, 3.5, 6), Vector3.new(9, 3.5, 6) }) do
            local p = center + offset
            table.insert(spawns[id], CFrame.lookAt(p, Vector3.new(0, p.Y, 0)))
        end
        block("KeepCourtyard", Vector3.new(72, 0.08, 72), center + Vector3.new(0, 0.06, 0),
            C.Light, Enum.Material.Cobblestone, false, base)
        -- The inward two sides remain completely open, including the roads.
        block("OuterCurtain", Vector3.new(3, 12, 76), center + Vector3.new(sx * 37, 6, 0), C.Stone, nil, true, base)
        block("OuterCurtain", Vector3.new(76, 12, 3), center + Vector3.new(0, 6, sz * 37), C.Stone, nil, true, base)
        for _, x in ipairs({ -31, 31 }) do
            for _, z in ipairs({ -31, 31 }) do tower(base, center.X + x, center.Z + z, tint) end
        end
        block("SpawnPavilionRoof", Vector3.new(38, 1.2, 34), center + Vector3.new(0, 14.5, 0),
            tint, Enum.Material.Slate, true, base)
        block("PavilionTrim", Vector3.new(39, 0.4, 35), center + Vector3.new(0, 13.8, 0),
            C.Gold, Enum.Material.Metal, false, base)
        for _, x in ipairs({ -18, 18 }) do
            for _, z in ipairs({ -16, 16 }) do
                block("PavilionPost", Vector3.new(1.5, 14, 1.5), center + Vector3.new(x, 7, z),
                    C.Wood, Enum.Material.Wood, true, base)
            end
        end
        banner(base, center.X + sx * 23, center.Z - sz * 15, tint, 18)
        local store = center + Vector3.new(sx * 21, 0, sz * 21)
        block("KeepStorehouse", Vector3.new(13, 10, 13), store + Vector3.new(0, 5, 0), C.Wood,
            Enum.Material.WoodPlanks, true, base)
        block("StorehouseRoof", Vector3.new(16, 1.5, 16), store + Vector3.new(0, 10.8, 0), tint,
            Enum.Material.Slate, true, base)
        block("StorehouseDoor", Vector3.new(3.5, 6, 0.15), store + Vector3.new(0, 3, -6.6), C.Dark,
            Enum.Material.Wood, false, base)
    end

    local nodes = {}
    local forest = group("HarvestForest")
    local treePositions = {
        { -160, -150 }, { -132, -154 }, { -104, -148 }, { -75, -134 },
        { -170, -118 }, { -142, -116 }, { -112, -108 }, { -82, -102 },
        { -164, -80 }, { -136, -72 }, { -106, -66 }, { -76, -62 },
        { -250, -130 }, { 245, -130 }, { -250, 130 }, { 245, 130 },
    }
    for index, p in ipairs(treePositions) do
        local id = string.format("Tree%02d", index)
        local tree = group(id, forest)
        local x, z = p[1], p[2]
        local scale = 0.9 + (index % 3) * 0.1
        block("HarvestTrunk", Vector3.new(2.4, 11, 2.4) * scale, Vector3.new(x, 5.5 * scale, z),
            C.Wood, Enum.Material.Wood, true, tree)
        for crown = 0, 2 do
            part("TreeCrown", Vector3.new(12 - crown * 2, 8, 12 - crown * 2) * scale,
                CFrame.new(x, (11 + crown * 3) * scale, z), crown == 1 and C.LeavesLight or C.Leaves,
                Enum.Material.Grass, false, tree, Enum.PartType.Ball)
        end
        nodes[id] = { Id = id, Kind = "Tree", Position = Vector3.new(x, 2, z), Model = tree }
    end
    local quarry = group("HarvestMines")
    local minePositions = {
        { 90, 70 }, { 118, 68 }, { 148, 74 }, { 176, 80 },
        { 88, 102 }, { 116, 108 }, { 146, 114 }, { 174, 110 },
        { -150, -240 }, { 150, -240 }, { -150, 240 }, { 150, 240 },
    }
    for index, p in ipairs(minePositions) do
        local id = string.format("Mine%02d", index)
        local mine = group(id, quarry)
        local x, z = p[1], p[2]
        part("OreRock", Vector3.new(7, 5, 6), CFrame.new(x, 2.3, z) * CFrame.Angles(0, index * 0.3, 0),
            C.Dark, Enum.Material.Slate, true, mine, Enum.PartType.Ball)
        for vein = 1, 3 do
            block("OreVein", Vector3.new(0.6, 1.3 + vein * 0.2, 2.8),
                Vector3.new(x - 2 + vein, 3.6, z - 2 + vein * 0.5), C.Ore, Enum.Material.Metal, false, mine)
        end
        nodes[id] = { Id = id, Kind = "Mine", Position = Vector3.new(x, 2, z), Model = mine }
    end
    -- The quarry arch is scenery beside the nodes, never a harvest prerequisite.
    for _, x in ipairs({ 190, 210 }) do
        block("QuarryTimber", Vector3.new(2, 15, 2), Vector3.new(x, 7.5, 100), C.Wood, Enum.Material.Wood)
    end
    block("QuarryLintel", Vector3.new(25, 2, 3), Vector3.new(200, 15, 100), C.Wood, Enum.Material.Wood)
    for _, z in ipairs({ 87, 113 }) do
        block("QuarryRockFace", Vector3.new(15, 16, 8), Vector3.new(245, 8, z), C.Dark)
    end

    local outposts = {}
    for _, spec in ipairs({
        { "Westwatch", "Westwatch", -110, 0 }, { "Eastwatch", "Eastwatch", 110, 0 },
        { "Southwatch", "Southwatch", 0, 115 },
    }) do
        local id, name, x, z = spec[1], spec[2], spec[3], spec[4]
        local camp = group(id .. "Outpost")
        disc("CaptureCircle", 18, 0.08, Vector3.new(x, 0.08, z), C.Dark, Enum.Material.Cobblestone, false, camp)
        disc("CaptureInlay", 16.5, 0.09, Vector3.new(x, 0.13, z), C.Road, Enum.Material.Sandstone, false, camp)
        local flag = banner(camp, x + 6, z - 6, C.Neutral, 17)
        local structure = {}
        local function buildPart(name_, size, position, color, material)
            local object = block(name_, size, position, color, material, false, camp)
            object.Transparency = 1
            table.insert(structure, object)
        end
        buildPart("BuiltOutpostRoof", Vector3.new(34, 1.4, 34), Vector3.new(x, 15, z), C.Wood, Enum.Material.WoodPlanks)
        for _, dx in ipairs({ -15, 15 }) do
            for _, dz in ipairs({ -15, 15 }) do
                buildPart("BuiltOutpostPost", Vector3.new(1.7, 14.5, 1.7), Vector3.new(x + dx, 7.25, z + dz),
                    C.Wood, Enum.Material.Wood)
                buildPart("BuiltOutpostCover", Vector3.new(6, 3.5, 3), Vector3.new(x + dx, 1.75, z + dz),
                    C.Stone, Enum.Material.Cobblestone)
            end
        end
        outposts[id] = { Id = id, Name = name, Position = Vector3.new(x, 0, z),
            Model = camp, Flag = flag, Structure = structure }
    end

    -- No walkable connection to combat. Only kingdom selection teleports a player.
    local lobby = group("KingdomSelection")
    local lobbyCenter = Vector3.new(0, 0, 420)
    block("SelectionGround", Vector3.new(136, 6, 128), Vector3.new(0, -3, 420), C.Light,
        Enum.Material.Cobblestone, true, lobby)
    disc("SelectionCompass", 26, 0.1, Vector3.new(0, 0.1, 420), C.Road, Enum.Material.Sandstone, false, lobby)
    for _, sign in ipairs({ -1, 1 }) do
        block("SelectionWall", Vector3.new(3, 20, 128), Vector3.new(sign * 67, 10, 420), C.Stone, nil, true, lobby)
        block("SelectionWall", Vector3.new(130, 20, 3), Vector3.new(0, 10, 420 + sign * 63), C.Stone, nil, true, lobby)
        block("SelectionCoping", Vector3.new(4, 1, 128), Vector3.new(sign * 67, 20.5, 420), C.Dark, nil, true, lobby)
        block("SelectionCoping", Vector3.new(130, 1, 4), Vector3.new(0, 20.5, 420 + sign * 63), C.Dark, nil, true, lobby)
    end
    local selectionPositions = {
        Redcliff = Vector3.new(-45, 0, 392), Korblox = Vector3.new(45, 0, 392),
        Greywolf = Vector3.new(-45, 0, 448), Overseer = Vector3.new(45, 0, 448),
    }
    for _, id in ipairs(Config.KingdomOrder) do
        local p = selectionPositions[id]
        local tint = Color3.fromRGB(table.unpack(Config.Kingdoms[id].Color))
        disc(id .. "SelectionMedallion", 11, 0.1, p + Vector3.new(0, 0.1, 0), tint,
            Enum.Material.Sandstone, false, lobby)
        block(id .. "SelectionCanopy", Vector3.new(25, 1, 25), p + Vector3.new(0, 14, 0), tint,
            Enum.Material.Slate, true, lobby)
        for _, dx in ipairs({ -10, 10 }) do
            for _, dz in ipairs({ -10, 10 }) do
                block("SelectionColumn", Vector3.new(1.4, 13.5, 1.4), p + Vector3.new(dx, 6.75, dz),
                    C.Light, nil, true, lobby)
            end
        end
        banner(lobby, p.X + (p.X < 0 and -1 or 1) * 8, p.Z, tint, 16)
    end
    local lobbySpawns = {}
    for _, z in ipairs({ 404, 436 }) do
        for _, x in ipairs({ -24, -8, 8, 24 }) do
            table.insert(lobbySpawns, CFrame.lookAt(Vector3.new(x, 3.5, z), Vector3.new(0, 3.5, 420)))
        end
    end

    Lighting.ClockTime, Lighting.Brightness = 16.4, 2.4
    Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(113, 117, 133), Color3.fromRGB(137, 143, 156)
    Lighting.GlobalShadows = true
    model.Parent = workspace
    return { Model = model, Spawns = spawns, LobbySpawns = lobbySpawns, LobbyCenter = lobbyCenter,
        Nodes = nodes, Outposts = outposts }
end

return WorldMapBuilder
