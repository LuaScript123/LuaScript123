-- An original arena built entirely from Roblox primitives. No downloaded assets.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("MedievalShared"):WaitForChild("Config"))

local MapBuilder = {}

local COLORS = {
    Stone = Color3.fromRGB(155, 146, 124),
    StoneLight = Color3.fromRGB(189, 179, 151),
    StoneDark = Color3.fromRGB(107, 105, 94),
    Road = Color3.fromRGB(169, 152, 120),
    Grass = Color3.fromRGB(91, 117, 69),
    Wood = Color3.fromRGB(95, 65, 43),
    Plaster = Color3.fromRGB(225, 207, 168),
    Roof = Color3.fromRGB(113, 68, 57),
    Leaf = Color3.fromRGB(66, 101, 63),
    Gold = Color3.fromRGB(235, 187, 91),
}

function MapBuilder.Build()
    local previous = workspace:FindFirstChild("FerEtFiolesArena")
    if previous then previous:Destroy() end
    local arena = Instance.new("Model")
    arena.Name = "FerEtFiolesArena"

    local function part(name, size, cf, color, material, collidable, shape)
        local object = Instance.new("Part")
        object.Name = name
        object.Anchored = true
        object.Size = size
        object.CFrame = cf
        object.Color = color
        object.Material = material or Enum.Material.Slate
        object.TopSurface = Enum.SurfaceType.Smooth
        object.BottomSurface = Enum.SurfaceType.Smooth
        object.CanCollide = collidable ~= false
        if shape then object.Shape = shape end
        object.Parent = arena
        return object
    end

    local function block(name, size, position, color, material, collidable)
        return part(name, size, CFrame.new(position), color, material, collidable)
    end

    local function disc(name, radius, height, position, color, material, collidable)
        return part(name, Vector3.new(height, radius * 2, radius * 2),
            CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2),
            color, material, collidable, Enum.PartType.Cylinder)
    end

    local function roof(name, x, z, width, depth, baseHeight, color)
        for _, side in ipairs({ -1, 1 }) do
            local wedge = Instance.new("WedgePart")
            wedge.Name = name
            wedge.Anchored = true
            wedge.Size = Vector3.new(width, 5, depth / 2)
            wedge.CFrame = CFrame.new(x, baseHeight + 2.5, z + side * depth / 4)
                * CFrame.Angles(0, side == 1 and math.pi or 0, 0)
            wedge.Color = color
            wedge.Material = Enum.Material.Slate
            wedge.TopSurface = Enum.SurfaceType.Smooth
            wedge.BottomSurface = Enum.SurfaceType.Smooth
            wedge.Parent = arena
        end
    end

    local function light(position)
        local frame = block("LanternFrame", Vector3.new(1.4, 2.2, 1.4), position,
            COLORS.Wood, Enum.Material.Wood, false)
        local flame = block("LanternGlow", Vector3.new(1, 1.5, 1), position,
            Color3.fromRGB(255, 207, 117), Enum.Material.Neon, false)
        local glow = Instance.new("PointLight")
        glow.Color = Color3.fromRGB(255, 211, 145)
        glow.Brightness = 1.4
        glow.Range = 22
        glow.Shadows = true
        glow.Parent = flame
        return frame
    end

    local function flag(x, z, baseHeight, color, facing)
        block("BannerPole", Vector3.new(0.35, 11, 0.35), Vector3.new(x, baseHeight + 5.5, z),
            COLORS.Wood, Enum.Material.Wood, false)
        local cloth = part("TeamBanner", Vector3.new(0.18, 4, 4.5),
            CFrame.new(x, baseHeight + 8.1, z + 2.15 * facing), color,
            Enum.Material.Fabric, false)
        cloth.CastShadow = false
        block("BannerTrim", Vector3.new(0.24, 0.3, 4.6),
            cloth.Position + Vector3.new(0, -1.85, 0), COLORS.Gold, Enum.Material.Metal, false)
    end

    local function tower(x, z, color)
        disc("TowerFoot", 7.7, 1.4, Vector3.new(x, 0.7, z), COLORS.StoneDark)
        disc("Watchtower", 6.5, 15, Vector3.new(x, 7.5, z), COLORS.Stone)
        disc("TowerCrown", 7.2, 1.5, Vector3.new(x, 15.5, z), COLORS.StoneLight)
        for index = 0, 7 do
            local angle = index * math.pi / 4
            local position = Vector3.new(x + math.cos(angle) * 6.3, 17.3, z + math.sin(angle) * 6.3)
            part("TowerBattlement", Vector3.new(2.5, 3, 2.5),
                CFrame.new(position) * CFrame.Angles(0, -angle, 0), COLORS.StoneLight)
        end
        flag(x, z, 16.3, color, z < 0 and -1 or 1)
    end

    local function house(x, z, color, roofColor)
        block("VillageHouse", Vector3.new(17, 11, 16), Vector3.new(x, 5.5, z),
            color, Enum.Material.Plaster)
        block("HouseFoundation", Vector3.new(18, 1.2, 17), Vector3.new(x, 0.6, z), COLORS.StoneDark)
        roof("PitchedRoof", x, z, 20, 20, 11, roofColor)
        for _, side in ipairs({ -1, 1 }) do
            block("TimberCorner", Vector3.new(0.6, 11, 0.6), Vector3.new(x + side * 8.4, 5.5, z - 8.05),
                COLORS.Wood, Enum.Material.Wood)
            block("Window", Vector3.new(3, 3.5, 0.2), Vector3.new(x + side * 4.6, 7, z - 8.13),
                Color3.fromRGB(84, 116, 120), Enum.Material.Glass, false)
            block("WindowMullion", Vector3.new(0.25, 3.5, 0.3), Vector3.new(x + side * 4.6, 7, z - 8.25),
                COLORS.Wood, Enum.Material.Wood, false)
        end
        block("HouseBeam", Vector3.new(17.5, 0.6, 0.6), Vector3.new(x, 10.2, z - 8.1),
            COLORS.Wood, Enum.Material.Wood)
        block("Door", Vector3.new(3, 5.5, 0.3), Vector3.new(x, 2.75, z - 8.17),
            COLORS.Wood, Enum.Material.Wood)
        block("Chimney", Vector3.new(2.5, 7, 3), Vector3.new(x + 5, 14, z + 3), COLORS.StoneDark)
    end

    local function tree(x, z, scale)
        block("TreeTrunk", Vector3.new(1.7, 9, 1.7) * scale,
            Vector3.new(x, 4.5 * scale, z), COLORS.Wood, Enum.Material.Wood)
        for index = 0, 2 do
            part("TreeCrown", Vector3.new(10 - index * 1.5, 7, 10 - index * 1.5) * scale,
                CFrame.new(x + (index % 2) * scale, (9 + index * 2.6) * scale, z),
                index == 1 and Color3.fromRGB(80, 119, 67) or COLORS.Leaf,
                Enum.Material.Grass, false, Enum.PartType.Ball)
        end
    end

    -- The floor top is exactly y=0. Main paths have no raised lips or steps.
    block("ArenaGround", Vector3.new(184, 4, 164), Vector3.new(0, -2, 0), COLORS.Grass, Enum.Material.Grass)
    block("SurroundingMeadow", Vector3.new(340, 4, 320), Vector3.new(0, -4.1, 0),
        Color3.fromRGB(77, 99, 63), Enum.Material.Grass)
    block("CampRoad", Vector3.new(166, 0.08, 32), Vector3.new(0, 0.04, 0), COLORS.Road, Enum.Material.Cobblestone, false)
    block("VillageRoad", Vector3.new(20, 0.09, 132), Vector3.new(0, 0.05, 0), COLORS.Road, Enum.Material.Cobblestone, false)
    disc("CentralPlazaBorder", 26, 0.1, Vector3.new(0, 0.07, 0), COLORS.StoneDark, Enum.Material.Cobblestone, false)
    disc("CentralPlaza", 24.8, 0.1, Vector3.new(0, 0.13, 0), COLORS.StoneLight, Enum.Material.Cobblestone, false)
    disc("ArenaInsignia", 5.5, 0.12, Vector3.new(0, 0.2, 0), COLORS.Road, Enum.Material.Sandstone, false)
    -- Decorative paving is noncolliding; the single stable floor carries characters.
    for _, x in ipairs({ -36, -18, 18, 36 }) do
        block("RoadInlay", Vector3.new(1, 0.08, 29), Vector3.new(x, 0.13, 0),
            COLORS.StoneLight, Enum.Material.Sandstone, false)
    end

    -- An enclosing wall keeps combatants inside a 180 x 160 play area.
    for _, side in ipairs({ -1, 1 }) do
        block("BoundarySide", Vector3.new(3, 12, 164), Vector3.new(side * 91, 6, 0), COLORS.StoneDark)
        block("BoundaryEnd", Vector3.new(180, 12, 3), Vector3.new(0, 6, side * 81), COLORS.StoneDark)
        block("BoundaryCoping", Vector3.new(4, 0.7, 164), Vector3.new(side * 91, 12.35, 0), COLORS.Stone)
        block("BoundaryCoping", Vector3.new(180, 0.7, 4), Vector3.new(0, 12.35, side * 81), COLORS.Stone)
        for x = -84, 84, 12 do
            block("WallBattlement", Vector3.new(4, 2.5, 3), Vector3.new(x, 13.7, side * 81), COLORS.Stone)
        end
        for z = -68, 68, 12 do
            block("WallBattlement", Vector3.new(3, 2.5, 4), Vector3.new(side * 91, 13.7, z), COLORS.Stone)
        end
    end

    local spawns = { Dawn = {}, Ember = {} }
    for _, teamId in ipairs(Config.TeamOrder) do
        local sign = teamId == "Dawn" and -1 or 1
        local teamColor = Color3.fromRGB(table.unpack(Config.Teams[teamId].Color))
        local x = sign * 73
        for _, z in ipairs({ -8, 0, 8 }) do
            -- R6 HumanoidRootPart center is three studs above the ground.
            table.insert(spawns[teamId], CFrame.lookAt(Vector3.new(x, 3.5, z), Vector3.new(0, 3.5, z)))
        end
        block("CampStone", Vector3.new(25, 0.12, 29), Vector3.new(x, 0.1, 0),
            COLORS.StoneLight, Enum.Material.Cobblestone, false)
        block("SpawnCanopy", Vector3.new(25, 1.3, 32), Vector3.new(x, 13.8, 0),
            COLORS.Wood, Enum.Material.WoodPlanks)
        for _, z in ipairs({ -15, 15 }) do
            block("CanopyPillar", Vector3.new(1.5, 13.5, 1.5), Vector3.new(x - sign * 10.5, 6.75, z),
                COLORS.Wood, Enum.Material.Wood)
            block("CampSideCover", Vector3.new(25, 7, 2), Vector3.new(x, 3.5, z + (z < 0 and -2 or 2)),
                COLORS.Stone)
            light(Vector3.new(x, 10, z))
        end
        block("CampBack", Vector3.new(2, 13, 34), Vector3.new(sign * 86, 6.5, 0), COLORS.Stone)
        for _, z in ipairs({ -17, 17 }) do
            block("GatePillar", Vector3.new(5, 14, 5), Vector3.new(sign * 53, 7, z), COLORS.StoneLight)
            block("GateCapital", Vector3.new(6.5, 1.5, 6.5), Vector3.new(sign * 53, 14.2, z), COLORS.StoneDark)
        end
        block("GateArchLintel", Vector3.new(6, 3, 39), Vector3.new(sign * 53, 16, 0), COLORS.Stone)
        block("GateTeamStripe", Vector3.new(6.1, 1, 36), Vector3.new(sign * 53, 16.2, 0), teamColor, Enum.Material.Fabric, false)
        tower(sign * 55, -30, teamColor)
        tower(sign * 55, 30, teamColor)
        for _, z in ipairs({ -48, 48 }) do
            block("FortCurtain", Vector3.new(4, 9, 21), Vector3.new(sign * 55, 4.5, z), COLORS.Stone)
            house(sign * 75, z, COLORS.Plaster, teamColor:Lerp(COLORS.Roof, 0.55))
        end
        flag(sign * 66, -14, 13.8, teamColor, 1)
        flag(sign * 66, 14, 13.8, teamColor, -1)
    end

    -- The side village offers cover while leaving the complete center lane open.
    for _, position in ipairs({ Vector3.new(-25, 0, -52), Vector3.new(25, 0, -52), Vector3.new(-25, 0, 52), Vector3.new(25, 0, 52) }) do
        house(position.X, position.Z, COLORS.Plaster, COLORS.Roof)
    end
    for _, z in ipairs({ -29, 29 }) do
        for _, x in ipairs({ -27, 27 }) do
            block("LowCover", Vector3.new(11, 3.5, 3), Vector3.new(x, 1.75, z), COLORS.Stone)
            block("CoverCoping", Vector3.new(11.6, 0.5, 3.6), Vector3.new(x, 3.75, z), COLORS.StoneLight)
        end
    end

    -- Braziers flank the plaza without obstructing a spawn-to-center route.
    for _, z in ipairs({ -20, 20 }) do
        disc("BrazierFoot", 2, 1, Vector3.new(0, 0.5, z), COLORS.StoneDark)
        block("BrazierPlinth", Vector3.new(1.6, 3, 1.6), Vector3.new(0, 2, z), COLORS.Stone)
        disc("BrazierBowl", 2.2, 0.7, Vector3.new(0, 3.8, z), COLORS.Wood, Enum.Material.Metal)
        local fire = block("BrazierEmbers", Vector3.new(2.1, 0.35, 2.1), Vector3.new(0, 4.25, z),
            Color3.fromRGB(255, 149, 62), Enum.Material.Neon, false)
        local flame = Instance.new("Fire")
        flame.Size = 3
        flame.Heat = 3
        flame.Color = Color3.fromRGB(255, 174, 68)
        flame.SecondaryColor = Color3.fromRGB(255, 220, 120)
        flame.Parent = fire
        light(Vector3.new(0, 4, z))
    end

    for _, position in ipairs({
        Vector3.new(-42, 0, -66), Vector3.new(42, 0, -66), Vector3.new(-42, 0, 66), Vector3.new(42, 0, 66),
        Vector3.new(-10, 0, -69), Vector3.new(10, 0, 69), Vector3.new(-76, 0, -70), Vector3.new(76, 0, 70),
    }) do
        tree(position.X, position.Z, 0.85 + (math.abs(position.X) % 3) * 0.08)
    end
    for _, position in ipairs({ Vector3.new(-37, 0, -41), Vector3.new(37, 0, 41), Vector3.new(39, 0, -35), Vector3.new(-39, 0, 35) }) do
        for index = 0, 1 do
            block("SupplyCrate", Vector3.new(3, 3, 3), position + Vector3.new(index * 3.2, 1.5, 0),
                COLORS.Wood, Enum.Material.WoodPlanks)
        end
    end

    Lighting.ClockTime = 16.4
    Lighting.Brightness = 2.4
    Lighting.Ambient = Color3.fromRGB(113, 117, 133)
    Lighting.OutdoorAmbient = Color3.fromRGB(137, 143, 156)
    Lighting.GlobalShadows = true
    Lighting.ExposureCompensation = 0.05
    local atmosphere = Lighting:FindFirstChild("MedievalAtmosphere")
    if not atmosphere then
        atmosphere = Instance.new("Atmosphere")
        atmosphere.Name = "MedievalAtmosphere"
        atmosphere.Parent = Lighting
    end
    atmosphere.Density = 0.22
    atmosphere.Offset = 0.1
    atmosphere.Color = Color3.fromRGB(225, 219, 195)
    atmosphere.Decay = Color3.fromRGB(142, 151, 165)
    atmosphere.Glare = 0.12
    atmosphere.Haze = 1.2
    arena.Parent = workspace
    return { Model = arena, Spawns = spawns, Center = Vector3.new(0, 3, 0) }
end

return MapBuilder
