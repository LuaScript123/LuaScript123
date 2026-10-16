-- Extends the common deterministic primitives/serializer from map-stub.luau.
-- Validate the actual WorldMapBuilder result, including built outpost geometry.
local function validate(map)
    assert(map.Model.Name == "FerEtFiolesArena", "World model must match the Rojo mounting name")
    local function descendant(object, parent)
        while object do
            if object == parent then return true end
            object = object.Parent
        end
        return false
    end
    local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
    local function validVector(value)
        return value and finite(value.X) and finite(value.Y) and finite(value.Z)
    end
    local builtParts, primitiveSet, geometry, obstacles, floors = {}, {}, {}, {}, {}
    local outpostCount, treeCount, mineCount, primitiveCount = 0, 0, 0, 0
    for id, point in pairs(map.Outposts) do
        outpostCount += 1
        assert(point.Id == id and type(point.Name) == "string" and #point.Name > 0, "Invalid outpost identity")
        assert(validVector(point.Position) and point.Position.Y == 0, "Invalid capture position: " .. id)
        assert(point.Flag and descendant(point.Flag, point.Model), "Flag missing from outpost: " .. id)
        assert(#point.Structure >= 5, "Buildable outpost needs a roof and supports: " .. id)
        for _, object in ipairs(point.Structure) do
            assert(descendant(object, point.Model), "Foreign buildable part: " .. id)
            assert(object.Transparency == 1 and object.CanCollide == false, "Outpost must begin unbuilt: " .. id)
            builtParts[object] = true
        end
    end
    assert(outpostCount == 3, "Expected three capturable outposts")
    for _, object in ipairs(allInstances) do
        if descendant(object, map.Model) and (object.ClassName == "Part" or object.ClassName == "WedgePart") then
            primitiveCount += 1
            primitiveSet[object] = true
            assert(object.Anchored == true, "Unanchored world part: " .. object.Name)
            assert(validVector(object.Size) and object.Size.X > 0 and object.Size.Y > 0 and object.Size.Z > 0,
                "Invalid part size: " .. object.Name)
            assert(validVector(object.Position), "Invalid part position: " .. object.Name)
            for _, value in ipairs(object.CFrame.Rotation) do assert(finite(value), "Invalid part rotation") end
            local minimum, maximum = bounds(object)
            local box = { Object = object, Min = minimum, Max = maximum }
            table.insert(geometry, box)
            if object.CanCollide or builtParts[object] then
                if maximum.Y > 0.5 and minimum.Y < 6.1 then table.insert(obstacles, box) end
                if math.abs(maximum.Y) < 0.001 then table.insert(floors, box) end
            end
        end
    end
    assert(primitiveCount < 1000, "World exceeds the primitive budget")
    local function clear(x, z, radius)
        for _, box in ipairs(obstacles) do
            if box.Min.X < x + radius and box.Max.X > x - radius
                and box.Min.Z < z + radius and box.Max.Z > z - radius then
                return false, box.Object.Name
            end
        end
        return true
    end
    local function supported(x, z, radius)
        for _, floor in ipairs(floors) do
            if floor.Min.X <= x - radius and floor.Max.X >= x + radius
                and floor.Min.Z <= z - radius and floor.Max.Z >= z + radius then return true end
        end
        return false
    end
    local worldFloor, selectionFloor
    for _, box in ipairs(geometry) do
        if box.Object.Name == "WorldGround" then worldFloor = box end
        if box.Object.Name == "SelectionGround" then selectionFloor = box end
    end
    assert(worldFloor and selectionFloor, "Battlefield and selector require independent ground planes")
    assert(selectionFloor.Min.Z - worldFloor.Max.Z >= 50, "Selection area must be isolated from combat")
    assert(validVector(map.LobbyCenter) and map.LobbyCenter.Y == 0, "Invalid neutral selection center")
    assert(clear(map.LobbyCenter.X, map.LobbyCenter.Z, 12), "Selection meeting area is obstructed")
    local kingdomCount, spawnCount, allSpawns = 0, 0, {}
    local expected = { Redcliff = true, Korblox = true, Greywolf = true, Overseer = true }
    for id, list in pairs(map.Spawns) do
        assert(expected[id], "Unexpected kingdom spawn: " .. tostring(id))
        kingdomCount += 1
        assert(#list >= 3, "Each kingdom needs at least three spawns")
        for index, frame in ipairs(list) do
            spawnCount += 1
            table.insert(allSpawns, { Name = id .. index, Position = frame.Position, World = true })
        end
    end
    assert(kingdomCount == 4 and #map.LobbySpawns == 8, "Expected four kingdoms and eight selection spawns")
    for index, frame in ipairs(map.LobbySpawns) do
        table.insert(allSpawns, { Name = "Selection" .. index, Position = frame.Position })
    end
    for _, spawn in ipairs(allSpawns) do
        local p = spawn.Position
        assert(validVector(p) and p.Y == 3.5, "R6 spawn root must be Y=3.5: " .. spawn.Name)
        assert(supported(p.X, p.Z, 1.5), "Spawn lacks stable floor: " .. spawn.Name)
        local ok, obstacle = clear(p.X, p.Z, 1.5)
        assert(ok, "Spawn collides with " .. tostring(obstacle) .. ": " .. spawn.Name)
    end
    -- Every marked road has a six-stud clear lane, checked with structures built.
    local roadCount = 0
    for _, box in ipairs(geometry) do
        if box.Object.Name == "WorldRoad" then
            roadCount += 1
            local size, p = box.Object.Size, box.Object.Position
            local horizontal = size.X > size.Z
            local length = horizontal and size.X or size.Z
            for offset = -length / 2 + 2, length / 2 - 2, 4 do
                local x, z = p.X + (horizontal and offset or 0), p.Z + (horizontal and 0 or offset)
                local ok, obstacle = clear(x, z, 3)
                assert(ok and supported(x, z, 3), "Road is obstructed or unsupported near " .. tostring(obstacle))
            end
        end
    end
    assert(roadCount >= 6, "Road grid must connect all four bases")
    -- Flood the real collision geometry, using a conservative standing capsule
    -- footprint, then prove each spawn, harvest node and flag can be approached.
    local step, minimum, width = 5, -290, 117
    local reachable, queue = {}, {}
    local function key(x, z) return z * width + x + 1 end
    local function enqueue(x, z)
        if x < 0 or z < 0 or x >= width or z >= width then return end
        local k = key(x, z)
        if reachable[k] ~= nil then return end
        local px, pz = minimum + x * step, minimum + z * step
        reachable[k] = clear(px, pz, 1.7) and supported(px, pz, 1.7)
        if reachable[k] then table.insert(queue, { x, z }) end
    end
    enqueue(58, 58)
    local cursor = 1
    while cursor <= #queue do
        local cell = queue[cursor]
        cursor += 1
        enqueue(cell[1] - 1, cell[2]); enqueue(cell[1] + 1, cell[2])
        enqueue(cell[1], cell[2] - 1); enqueue(cell[1], cell[2] + 1)
    end
    assert(#queue > 10000, "Expected a connected open battlefield")
    local function lineClear(from, target, ignoredModel)
        for _, box in ipairs(obstacles) do
            if box.Min.Y < 2 and box.Max.Y > 2 and not descendant(box.Object, ignoredModel) then
                local near, far = 0, 1
                for _, axis in ipairs({ "X", "Z" }) do
                    local delta = target[axis] - from[axis]
                    if math.abs(delta) < 0.00001 then
                        if from[axis] <= box.Min[axis] or from[axis] >= box.Max[axis] then near = 2 end
                    else
                        local a, b = (box.Min[axis] - from[axis]) / delta, (box.Max[axis] - from[axis]) / delta
                        if a > b then a, b = b, a end
                        near, far = math.max(near, a), math.min(far, b)
                    end
                end
                if near < far then return false end
            end
        end
        return true
    end
    local function approachable(position, radius, ignoredModel)
        local centerX, centerZ = math.floor((position.X - minimum) / step), math.floor((position.Z - minimum) / step)
        local reach = math.ceil(radius / step)
        for x = centerX - reach, centerX + reach do
            for z = centerZ - reach, centerZ + reach do
                if x >= 0 and x < width and z >= 0 and z < width and reachable[key(x, z)] then
                    local p = Vector3.new(minimum + x * step, 2, minimum + z * step)
                    local distanceSquared = (p.X - position.X) ^ 2 + (p.Z - position.Z) ^ 2
                    if distanceSquared <= radius * radius and lineClear(p, position, ignoredModel) then return true end
                end
            end
        end
        return false
    end
    for _, spawn in ipairs(allSpawns) do
        if spawn.World then assert(approachable(spawn.Position, 6), "Spawn disconnected from roads: " .. spawn.Name) end
    end
    for id, node in pairs(map.Nodes) do
        assert(node.Id == id and validVector(node.Position) and node.Position.Y == 2, "Invalid resource ref: " .. id)
        assert(descendant(node.Model, map.Model), "Resource model is outside world: " .. id)
        local found = false
        for object in pairs(primitiveSet) do if descendant(object, node.Model) then found = true end end
        assert(found, "Resource has no visible geometry: " .. id)
        assert(approachable(node.Position, 10, node.Model), "Resource has no reachable harvest sightline: " .. id)
        if node.Kind == "Tree" then treeCount += 1
        elseif node.Kind == "Mine" then mineCount += 1
        else error("Unexpected resource kind: " .. tostring(node.Kind)) end
    end
    assert(treeCount == 16 and mineCount == 12, "Expected sixteen trees and twelve ore nodes")
    for id, point in pairs(map.Outposts) do
        assert(approachable(point.Position, 5, point.Model), "Flag disconnected from roads: " .. id)
        local p = point.Position + Vector3.new(0, 3.5, 10)
        assert(clear(p.X, p.Z, 1.5) and supported(p.X, p.Z, 1.5), "Built outpost blocks respawn: " .. id)
    end
    print("<!-- Geometry verified: " .. primitiveCount .. " primitives; " .. spawnCount .. " kingdom and eight selection spawns supported; "
        .. treeCount .. " trees, " .. mineCount .. " mines and three outposts reachable; six road lanes clear, including built outposts. -->")
end
