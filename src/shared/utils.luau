--!strict

local Attributes = require("./Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("./Enums")

local utils = {}

function utils.waitAll(arr: { Tween }, callback: () -> ())
	-- maybe should add another one that's like 10s (configurable?) and warn if it fires?
	local countRemaining = #arr
	--print("waiting for", countRemaining)
	for _, waitable in arr do
		waitable.Completed:Connect(
			function ()
				countRemaining -= 1
				--print("down to", countRemaining)
				if countRemaining == 0 then
					callback()
				end
			end
		)
	end
end

function utils.findFirstDescendantOfClass(parent: Instance, className: string): Instance?
    for _, descendant in parent:GetDescendants() do
        if descendant:IsA(className) then
            return descendant
        end
    end
    return nil
end

function utils.findFirstDescendant(parent: Instance, name: string): Instance?
    for _, descendant in parent:GetDescendants() do
        if descendant.Name == name then
            return descendant
        end
    end
    return nil
end

function utils.findFirstDescendantOfClassAndName(parent: Instance, className: string, name: string): Instance?
    for _, descendant in parent:GetDescendants() do
        if descendant:IsA(className) and descendant.Name == name then
            return descendant
        end
    end
    return nil
end

function utils.findFirstDescendantWithAttribute(parent: Instance, attributeName: string, value: any): Instance?
    for _, descendant in parent:GetDescendants() do
        if descendant:GetAttribute(attributeName) == value then
            return descendant
        end
    end
    return nil
end

function utils.findFirstDescendantWithNameAndAttribute(parent: Instance, name: string, attributeName: string, value: any): Instance?
    for _, descendant in parent:GetDescendants() do
        if descendant.Name == name and descendant:GetAttribute(attributeName) == value then
            return descendant
        end
    end
    return nil
end

function utils.findFirstDescendantWithTagAndAttribute(parent: Instance, tag: string, attributeName: string, value: any): Instance?
	local collectionService = game:GetService("CollectionService")

    for _, descendant in parent:GetDescendants() do
		if collectionService:HasTag(descendant, tag) and descendant:GetAttribute(attributeName) == value then
            return descendant
        end
    end
    return nil
end

function utils.getAllDescendantsByName(parent: Instance, name: string): { Instance }
	local retval: { Instance } = {}
    for _, descendant in parent:GetDescendants() do
        if descendant.Name == name then
			table.insert(retval, descendant)
        end
    end
    return retval
end

function utils.getAllDescendantsWithAttribute(parent: Instance, attributeName: string, value: any): { Instance }
	local retval: { Instance } = {}
    for _, descendant in parent:GetDescendants() do
        if descendant:GetAttribute(attributeName) == value then
			table.insert(retval, descendant)
        end
    end
    return retval
end

function utils.setPropertyTreeClassName(root: Instance, className: string, propertyName: string, value: any)
	if root:IsA(className) then
		local rootAny = root :: any
		rootAny[propertyName] = value
	end

    for _, descendant in root:GetDescendants() do
		if not descendant:IsA(className) then
			continue
		end

		local descendantAny = descendant :: any
		descendantAny[propertyName] = value
	end
end

function utils.setPropertyTreeBaseParts(root: Instance, propertyName: string, value: any)
	return utils.setPropertyTreeClassName(root, "BasePart", propertyName, value)
end

function utils.setPropertyTreeBasePartsFromTemplate(root: Instance, propertyName: string, template: Instance)
	if root:IsA("BasePart") then
		local rootAny = root :: any
		rootAny[propertyName] = (template :: any)[propertyName]
	end

    for _, descendant in root:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		local templateParts = (template :: any):QueryDescendants(string.format("[$PartIndex=%i]", descendant:GetAttribute("PartIndex") :: any))
		if #templateParts == 1 then
			local templatePart = templateParts[1]
			--print("found template, setting", descendant, propertyName, templatePart, templatePart[propertyName])
			local descendantAny = descendant :: any
			descendantAny[propertyName] = templatePart[propertyName]
		end
	end

end

function utils.getTableSize(t: { [any]: any }): number
    local count = 0
    for _, _ in t do
        count = count + 1
    end
    return count
end

--[[
  raycasts down to our terrain
]]
function utils.getGroundHeight(x: number, z: number): number?
	local originY = 80 -- Start a bit above the expected terrain
	local origin = Vector3.new(x, originY, z)
	local direction = Vector3.new(0, -1, 0) -- Downwards direction
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = {workspace.Level :: Folder}

	local raycastResult = workspace:Raycast(origin, direction * 150, raycastParams)

	if not raycastResult then
		--print("No terrain found at", x, z)
		return nil
	end

	local height = raycastResult.Position.Y
	--print("Ground height at", x, z, "is", height)
	return height
end

--[[
  raycasts up to our terrain
]]
function utils.getGroundHeightAbove(position: Vector3): number?
	local direction = Vector3.yAxis
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = {workspace.Level :: Folder}

	local raycastResult = workspace:Raycast(position, direction * 500, raycastParams)

	if not raycastResult then
		--print("No terrain found at", position)
		return nil
	end

	local height = raycastResult.Position.Y
	--print("Ground height above", position, "is", height)
	return height
end

--[[
  raycasts up to our terrain
]]
function utils.getGroundHeightBelow(position: Vector3): number?
	local direction = -Vector3.yAxis
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = {workspace.Level :: Folder}

	local raycastResult = workspace:Raycast(position, direction * 500, raycastParams)

	if not raycastResult then
		--print("No terrain found at", position)
		return nil
	end

	local height = raycastResult.Position.Y
	--print("Ground height below", position, "is", height)
	return height
end

function utils.getGroundPosition(x: number, z: number): Vector3
	local y = utils.getGroundHeight(x, z) or 0
	return Vector3.new(x, y, z)
end

function utils.getGroundPositionForLocation(location: Vector3): Vector3
	return utils.getGroundPosition(location.X, location.Z)
end

--[[
	Finds the Vector3 of the circle that is closest to p3.
	The circle must have a radius 'radius' and must contain at least one of the
	two points, p1 or p2, on its circumference, while containing the other point.
	All calculations are performed on the XZ plane.

	@param p1 Vector3 The first point.
	@param p2 Vector3 The second point.
	@param p3 Vector3 The third point to which the circle should be closest.
	@param radius number The radius of the circle.

	@return Vector3? The Vector3 of the closest circle's center, or nil if no circle exists.
]]
function utils.findClosestContainedCircleCenterXZ(p1: Vector3, p2: Vector3, p3: Vector3, radius: number): Vector3?
	-- Step 1: Project all points to the XZ plane
	local p1_xz = Vector3.new(p1.X, 0, p1.Z)
	local p2_xz = Vector3.new(p2.X, 0, p2.Z)
	local p3_xz = Vector3.new(p3.X, 0, p3.Z)

	local validCandidates: { Vector3 } = {}

	-- Step 2: Handle circles that pass through both p1 and p2
	local v_xz = p2_xz - p1_xz
	local dist_p1_p2 = v_xz.Magnitude

	if dist_p1_p2 <= 2 * radius then
		if dist_p1_p2 == 0 then
			-- Both points are the same; the circle can be centered anywhere at radius 'r' from p1
			local v_p1_p3 = p3_xz - p1_xz
			local dir_p1_p3 = v_p1_p3.Unit

			local centerP1 = p1_xz + dir_p1_p3 * radius
			table.insert(validCandidates, centerP1)

		else
			-- Case 1 & 2 overlap: These centers are equidistant from both p1 and p2
			local midpoint_xz = (p1_xz + p2_xz) / 2
			local d = math.sqrt(radius^2 - (dist_p1_p2 / 2)^2)
			local perp_dir_xz = Vector3.new(-v_xz.Z, 0, v_xz.X).Unit

			table.insert(validCandidates, midpoint_xz + perp_dir_xz * d)
			table.insert(validCandidates, midpoint_xz - perp_dir_xz * d)
		end
	end

	-- Step 3: Handle circles that pass through p1 and contain p2
	local v_p1_p3 = p3_xz - p1_xz
	local dir_p1_p3 = v_p1_p3.Unit
	local centerP1 = p1_xz + dir_p1_p3 * radius

	if (centerP1 - p2_xz).Magnitude <= radius then
		table.insert(validCandidates, centerP1)
	end

	-- Step 4: Handle circles that pass through p2 and contain p1
	local v_p2_p3 = p3_xz - p2_xz
	local dir_p2_p3 = v_p2_p3.Unit
	local centerP2 = p2_xz + dir_p2_p3 * radius

	if (centerP2 - p1_xz).Magnitude <= radius then
		table.insert(validCandidates, centerP2)
	end

	-- Step 5: Find the closest center from all valid candidates
	if #validCandidates == 0 then
		warn("No valid circle could be found for the given points and radius.")
		return nil
	end

	local closestCenter = validCandidates[1]
	local minDistance = (closestCenter - p3_xz).Magnitude

	for i = 2, #validCandidates do
		local currentCenter = validCandidates[i]
		local currentDistance = (currentCenter - p3_xz).Magnitude
		if currentDistance < minDistance then
			minDistance = currentDistance
			closestCenter = currentCenter
		end
	end

	return Vector3.new(closestCenter.X, 0, closestCenter.Z)
end

export type Circle = {
	center: Vector3,
	radius: number,
}

function utils.isPositionInCircleXZ(position: Vector3, circle: Circle): boolean
    local distance = utils.getMagnitudeXZ(circle.center - position)
    local epsilon = 1e-6 -- A small value for floating-point comparison
    return distance <= circle.radius + epsilon
end

function utils.calculateCircumcenterXZ(p1: Vector3, p2: Vector3, p3: Vector3): Vector3?
    -- Extract x and z coordinates for 2D calculation
    local x1, z1 = p1.X, p1.Z
    local x2, z2 = p2.X, p2.Z
    local x3, z3 = p3.X, p3.Z

    -- Calculate the terms for the formula
    local A = x2 - x1
    local B = z2 - z1
    local C = x3 - x1
    local D = z3 - z1

    local E = A * (x1 + x2) + B * (z1 + z2)
    local F = C * (x1 + x3) + D * (z1 + z3)

    local G = 2 * (A * D - B * C)

    -- Check if the points are collinear (G will be zero or very close to zero)
    if math.abs(G) < 1e-9 then
        -- Points are collinear, a circumcenter cannot be found
        return nil
    end

    -- Calculate the circumcenter coordinates
    local Cx = (D * E - B * F) / G
    local Cz = (A * F - C * E) / G

    return Vector3.new(Cx, 0, Cz)
end

function utils.calculateCentroidXZ(p1: Vector3, p2: Vector3, p3: Vector3): Vector3
	local centroid = (p1 + p2 + p3) / 3
	-- Vector3.new treats a nil argument as 0, so "or 0" keeps the old behavior when there is no ground
	centroid = Vector3.new(centroid.X, utils.getGroundHeight(centroid.X, centroid.Z) or 0, centroid.Z)
	return centroid
end

local function getSmallestCircleWithPositions(R: { Vector3 }): Circle
	--print("gSCWP called with len", #R)
    local numPositions = #R

    if numPositions == 0 then
        return {
            center = Vector3.new(0, 0, 0),
            radius = 0
        }
    elseif numPositions == 1 then
        return {
            center = R[1],
            radius = 0
        }
    elseif numPositions == 2 then
        local p1 = R[1]
        local p2 = R[2]
        local center = (p1 + p2) / 2
        local radius = utils.getMagnitudeXZ(p1 - p2) / 2
        return {
            center = center,
            radius = radius
        }
	end

	if numPositions > 3 then
		warn("only up to 3 positions are supported in getSmallestCircleWithPositions")
	end

	local p1 = R[1]
	local p2 = R[2]
	local p3 = R[3]

	-- Check for obtuse triangle case
	if (p1 - p2):Dot(p3 - p2) <= 0 then
		return getSmallestCircleWithPositions({p1, p3})
	elseif (p2 - p1):Dot(p3 - p1) <= 0 then
		return getSmallestCircleWithPositions({p2, p3})
	elseif (p1 - p3):Dot(p2 - p3) <= 0 then
		return getSmallestCircleWithPositions({p1, p2})
	end

	-- Circumcenter of the triangle
	local a = p1.X * (p2.Z - p3.Z) - p1.Z * (p2.X - p3.X) + p2.X * p3.Z - p3.X * p2.Z
	local b = 0.5 * (p1.X * p1.X + p1.Z * p1.Z) * (p2.Z - p3.Z) - 0.5 * (p2.X * p2.X + p2.Z * p2.Z) * (p1.Z - p3.Z) + 0.5 * (p3.X * p3.X + p3.Z * p3.Z) * (p1.Z - p2.Z)
	local c = 0.5 * (p1.X * p1.X + p1.Z * p1.Z) * (p3.X - p2.X) - 0.5 * (p2.X * p2.X + p2.Z * p2.Z) * (p3.X - p1.X) + 0.5 * (p3.X * p3.X + p3.Z * p3.Z) * (p2.X - p1.X)
	local center_x = b / a
	local center_z = c / a

	local center = Vector3.new(center_x, 0, center_z)
	local radius = utils.getMagnitudeXZ(center - p1)
	return {
		center = center,
		radius = radius
	}
end

--[[
	this is the core of Welzl's algorithm
	@param P[1..nextUsePosition] array positions not yet considered
	@param R array boundary of current smallest enclosing circle
]]
local function getSmallestEnclosingCircleXZHelper(P: { Vector3 }, nextUsePosition: number, R: { Vector3 }): Circle
	--print("helper called with", P, nextUsePosition, R)
    if nextUsePosition == 0 or #R == 3 then
        return getSmallestCircleWithPositions(R)
    end

    local p = P[nextUsePosition]

    local circle = getSmallestEnclosingCircleXZHelper(P, nextUsePosition - 1, R)

    if not utils.isPositionInCircleXZ(p, circle) then
        table.insert(R, p)
        circle = getSmallestEnclosingCircleXZHelper(P, nextUsePosition - 1, R)
        table.remove(R, #R)
    end

	--print("helper returning", circle)

    return circle
end


local getSmallestCircleRandom = Random.new()

function utils.getSmallestEnclosingCircleXZ(positions: { Vector3 }): Circle
	local usePositions: { Vector3 }

	if #positions > 10 then
		-- random shuffle makes the performance much better; read about Welzl's algorithm
		usePositions = table.clone(positions)
		getSmallestCircleRandom:Shuffle(usePositions)
	else
		usePositions = positions
	end

    return getSmallestEnclosingCircleXZHelper(usePositions, #usePositions, {})
end

function utils.doesArrayContain<T>(tbl: { T }, value: T): boolean
    for i = 1, #tbl do
        if tbl[i] == value then
            return true
        end
    end
    return false
end

function utils.arrayFindIndexOf<T>(tbl: { T }, value: T): number?
    for i = 1, #tbl do
        if tbl[i] == value then
            return i
        end
    end
    return nil
end

function utils.arrayAppend<T>(arr1: { T }, arr2: { T })
	for _, value in arr2 do
		table.insert(arr1, value)
	end
end

function utils.getArrayUnion<T>(arr1: { T }, arr2: { T }): { T }
	local retval: { T } = {}
    local seen: { [any]: boolean } = {} -- A table to keep track of seen elements for de-duplication

    -- Add elements from the first array
    for _, value in arr1 do
        if not seen[value] then
            table.insert(retval, value)
            seen[value] = true
        end
    end

    -- Add elements from the second array
    for _, value in arr2 do
        if not seen[value] then
            table.insert(retval, value)
            seen[value] = true
        end
    end

    return retval
end

function utils.shallowCopy(obj: any): any
	-- If the object is not a table, it's a primitive and can be returned directly
	if typeof(obj) ~= "table" then
		return obj
	end

	local newTable: { [any]: any } = {}
	for key, value in obj do
		newTable[key] = value
	end
	return newTable
end

-- seen: an optional map to handle circular references (recursive tables)
function utils.deepCopy(obj: any, seen: { [any]: any }?): any
	-- If the object is not a table, it's a primitive and can be returned directly
	if typeof(obj) ~= "table" then
		return obj
	end

	-- Check if the table has already been copied to handle recursive tables.
	if seen and seen[obj] then
		return seen[obj]
	end

	-- Create a new table to store the copy.
	local newTable: { [any]: any } = {}

	-- Store the new table in the seen map to handle circular references.
	local seenMap: { [any]: any } = seen or {}
	seenMap[obj] = newTable

	-- Get the metatable of the original object and apply it to the new one.
	local metatable = getmetatable(obj)
	if metatable then
		setmetatable(newTable, utils.deepCopy(metatable, seenMap))
	end

	-- Recursively deep-copy each key-value pair in the original table.
	for k, v in obj do
		newTable[utils.deepCopy(k, seenMap)] = utils.deepCopy(v, seenMap)
	end

	return newTable
end

function utils.calculateMass(model: Instance): number
    local mass = 0
    for _, v in model:GetDescendants() do
        if v:IsA("BasePart") then
            mass += v:GetMass()
        end
    end

    return mass;
end

function utils.convertDurationSecToString(duration: number): string
	local days = duration // (3600 * 24)
	local hours = (duration - days * 3600 * 24) // 3600
	local minutes = (duration - days * 3600 * 24 - hours * 3600) // 60
	local sec = (duration - days * 3600 * 24 - hours * 3600 - minutes * 60) % 60
	if days > 0 then
		return string.format("%i:%02i:%02i:%02i", days, hours, minutes, sec)
	end
	if hours > 0 then
		return string.format("%2i:%02i:%02i", hours, minutes, sec)
	end

	return string.format("%2i:%02i", minutes, sec)
end

function utils.isPositionInOrNearModelXZ(position: Vector3, model: Instance?, nearDistance: number): boolean
    if not model or not model:IsA("Model") then
        warn("Invalid arguments to isPositionInModelXZ: model must be a Model", model)
        return false
    end

    -- Get the bounding box of the model.
    -- This returns the center of the box (CFrame) and its size (Vector3).
	-- gemini says:
    -- The CFrame from GetBoundingBox is axis-aligned and does not contain model rotation.
	-- but I, Chris, do not think this is true and it should just use the orientation returned from GetBoundingBox
    -- To handle orientation correctly, we get the model's pivot and the bounding box size separately.
    local modelPivot = model:GetPivot()
    local _orientation, boundingBoxSize = model:GetBoundingBox()
	--print("orientation is", orientation)
	--modelPivot = orientation

    -- Transform the part's world position into the model's local coordinate space,
    -- relative to its pivot. This effectively aligns the part's position with the
    -- model's own axes, making the check simple.
    local partPositionInModelSpace = modelPivot:PointToObjectSpace(position)

    -- Check if the part's transformed X and Z coordinates are within the model's bounds.
    -- We use math.abs because the local position is relative to the center and can be negative.
    local halfSize = boundingBoxSize / 2

    if math.abs(partPositionInModelSpace.X) > (halfSize.X + nearDistance) or math.abs(partPositionInModelSpace.Z) > (halfSize.Z + nearDistance) then
        return false
    end

	return true
end

-- written by gemini in response to "write Roblox luau function to determine if the results of getBoundingBox of two models intersect, even if their axes are not aligned"
function utils.doModelBoundingBoxesIntersect(modelA: Model, modelB: Model): boolean
	local cf1, size1 = modelA:GetBoundingBox()
	local cf2, size2 = modelB:GetBoundingBox()

    local h1 = size1 * 0.5
    local h2 = size2 * 0.5

    -- Local axes for each box
    local axes1 = {cf1.RightVector, cf1.UpVector, cf1.LookVector}
    local axes2 = {cf2.RightVector, cf2.UpVector, cf2.LookVector}

    -- Relative center vector
    local L = cf2.Position - cf1.Position

    -- All 15 axes to test (3 + 3 + 9 cross products)
    local testAxes: { Vector3 } = {}
    for _, a in ipairs(axes1) do table.insert(testAxes, a) end
    for _, a in ipairs(axes2) do table.insert(testAxes, a) end
    for _, a1 in ipairs(axes1) do
        for _, a2 in ipairs(axes2) do
            local cross = a1:Cross(a2)
            if cross.Magnitude > 0.001 then -- Avoid near-parallel axes
                table.insert(testAxes, cross.Unit)
            end
        end
    end

    -- Project both boxes onto each axis
    for _, axis in ipairs(testAxes) do
        -- Projection radius of box 1
        local r1 = math.abs(axes1[1]:Dot(axis)) * h1.X +
                   math.abs(axes1[2]:Dot(axis)) * h1.Y +
                   math.abs(axes1[3]:Dot(axis)) * h1.Z

        -- Projection radius of box 2
        local r2 = math.abs(axes2[1]:Dot(axis)) * h2.X +
                   math.abs(axes2[2]:Dot(axis)) * h2.Y +
                   math.abs(axes2[3]:Dot(axis)) * h2.Z

        -- Distance between projected centers
        local distance = math.abs(L:Dot(axis))

        -- If distance is greater than sum of radii, there is a gap (no intersection)
        if distance > (r1 + r2) then
            return false
        end
    end

    -- No gaps found on any axis
    return true
end


-- recreate a cframe with a new up vector of the y axis
function utils.getCFrameParallelToGround(cframe: CFrame): CFrame
	-- as gemini describes it:
	-- Get the current CFrame and the desired target upVector.
	-- Calculate the axis and angle needed to rotate the current upVector to the target upVector.
	-- Create a new CFrame by rotating the current CFrame by that axis and angle.
	local targetUpVector = Vector3.yAxis
	local startUpVector = cframe.UpVector
	local axis = startUpVector:Cross(targetUpVector)
	if axis.Magnitude < 1e-5 then
		-- already facing the right way, nothing to change (and if we try we'll get NaNs)
		return cframe
	end
	local dot = startUpVector:Dot(targetUpVector)
	--print("vectors dotted is", dot)

	-- we need to clamp because due to some floating point issues, this dot product is sometimes just slightly more than 1 (or less than -1)
	-- (if we didn't clamp, math.acos would return math.nan)
	local clampedDot = math.clamp(dot, -1, 1)
	--print("clamped to", clampedDot)
	local angle = math.acos(clampedDot)

	return CFrame.fromAxisAngle(axis, angle) * cframe.Rotation + cframe.Position
end

-- calculate angle (in radians) between cframe up vector and y axis
function utils.getAngleFromVertical(cframe: CFrame): number
	local targetUpVector = Vector3.yAxis
	local startUpVector = cframe.UpVector
	local axis = startUpVector:Cross(targetUpVector)
	if axis.Magnitude < 1e-5 then
		-- very close already
		return 0
	end
	local dot = startUpVector:Dot(targetUpVector)
	--print("vectors dotted is", dot)

	-- we need to clamp because due to some floating point issues, this dot product is sometimes just slightly more than 1 (or less than -1)
	-- (if we didn't clamp, math.acos would return math.nan)
	local clampedDot = math.clamp(dot, -1, 1)
	--print("clamped to", clampedDot)
	local angle = math.acos(clampedDot)

	return angle
end

function utils.getMagnitudeXZ(vec3: Vector3): number
	return math.sqrt(vec3.X * vec3.X + vec3.Z * vec3.Z)
end

function utils.getMagnitudeXZSquared(vec3: Vector3): number
	return vec3.X * vec3.X + vec3.Z * vec3.Z
end

function utils.isLocationInRectangleXZ(location: Vector3, cornerA: Vector3, cornerB: Vector3): boolean
    -- Find min and max corners
    local minX = math.min(cornerA.X, cornerB.X)
    local maxX = math.max(cornerA.X, cornerB.X)
    local minZ = math.min(cornerA.Z, cornerB.Z)
    local maxZ = math.max(cornerA.Z, cornerB.Z)

    -- Check if the location is within all bounds
    return location.X >= minX and location.X <= maxX and
           location.Z >= minZ and location.Z <= maxZ
end

function utils.destroyDescendantsByName(inst: Instance, name: string)
    for _, descendant in inst:GetDescendants() do
        if descendant.Name ~= name then
			continue
		end
		descendant:Destroy()
    end
end

function utils.getColoredText(str: string, color: Color3): string
	local colorStr = color:ToHex()
	return string.format("<font color=\"#%s\">%s</font>", colorStr, str)
end

function utils.getColorForRarity(rarity: number?): Color3
	if rarity == nil or rarity == enums.Rarity.COMMON then
		return Color3.fromRGB(240, 240, 240)
	end

	if rarity == enums.Rarity.UNCOMMON then
		return Color3.fromRGB(16, 240, 16)
	end

	if rarity == enums.Rarity.RARE then
		return Color3.fromRGB(16, 128, 240)
	end

	if rarity == enums.Rarity.EPIC then
		return Color3.fromRGB(192, 24, 192)
	end

	warn("unknown rarity", rarity)
	return Color3.new(0, 0, 0)
end

function utils.getColoredTextForRarity(str: string, rarity: number?): string
	local color = utils.getColorForRarity(rarity)
	return utils.getColoredText(str, color)
end

function utils.getLowStaminaColor(): Color3
	return Color3.fromRGB(255, 0, 0)
end

function utils.get2DColorForPrimaryElement(primaryElement: number?): Color3
	if primaryElement == enums.PrimaryElements.FIRE then
		return Color3.fromRGB(255, 38, 0)
	end

	if primaryElement == enums.PrimaryElements.NATURE then
		return Color3.fromRGB(0, 249, 0)
	end

	if primaryElement == enums.PrimaryElements.WATER then
		return Color3.fromRGB(0, 150, 255)
	end

	-- this check used to be against enums.PrimaryElements.AIR, which no longer exists (so the key
	-- evaluated to nil and this branch matched nil elements); keep returning the old AIR color for
	-- nil to preserve that behavior
	if primaryElement == nil then
		return Color3.fromRGB(215, 131, 255)
	end

	warn("unknown primary element", primaryElement)
	return Color3.new(0, 0, 0)
end

function utils.getEffectColorForPrimaryElement(primaryElement: number?): Color3
	if primaryElement == enums.PrimaryElements.FIRE then
		return Color3.fromRGB(148, 17, 0)
	end

	if primaryElement == enums.PrimaryElements.NATURE then
		return Color3.fromRGB(0, 142, 0)
	end

	if primaryElement == enums.PrimaryElements.WATER then
		return Color3.fromRGB(0, 83, 146)
	end

	-- non-elemental things
	return Color3.fromRGB(255, 255, 255)
end

local normalColors = {
	Color3.fromRGB(255, 255, 255),
}

local bronzeColors = {
	Color3.fromRGB(255, 89, 89),
}

local silverColors = {
	Color3.fromRGB(192, 192, 192),
}

local goldColors = {
	Color3.fromRGB(255, 215, 0),
}

local verdantColors = {
	Color3.fromRGB(0, 255, 0),
	Color3.fromRGB(40, 127, 71),
}

local azureColors = {
	Color3.fromRGB(9, 137, 207),
	Color3.fromRGB(13, 105, 172),
}

local crimsonColors = {
	Color3.fromRGB(220, 20, 60),
	Color3.fromRGB(178, 34, 34),
}

local rainbowColors = {
	Color3.fromRGB(255, 38, 0),
	Color3.fromRGB(148, 82, 0),
	Color3.fromRGB(255, 251, 0),
	Color3.fromRGB(0, 249, 0),
	Color3.fromRGB(0, 150, 255),
	Color3.fromRGB(83, 27, 147),
	Color3.fromRGB(148, 55, 255),
}

local celestialColors = {
	Color3.fromRGB(0, 84, 147),
	Color3.fromRGB(0, 150, 255),
	Color3.fromRGB(118, 214, 255),
	Color3.fromRGB(122, 129, 255),
	Color3.fromRGB(4, 51, 255),
}

local mutationColorsMap: { [number]: { Color3 } } = {
	[enums.Mutations.NORMAL] = normalColors,
	[enums.Mutations.BRONZE] = bronzeColors,
	[enums.Mutations.SILVER] = silverColors,
	[enums.Mutations.GOLD] = goldColors,
	[enums.Mutations.RAINBOW] = rainbowColors,
	[enums.Mutations.CELESTIAL] = celestialColors,
	[enums.Mutations.VERDANT] = verdantColors,
	[enums.Mutations.AZURE] = azureColors,
	[enums.Mutations.CRIMSON] = crimsonColors,
}

function utils.getColorsForMutation(mutation: number?): { Color3 }
	local colors = if mutation ~= nil then mutationColorsMap[mutation] else nil
	if not colors then
		warn("unknown mutation", mutation, debug.traceback())
		return {Color3.fromRGB(0,0,0)}
	end

	return colors
end

function utils.isMutationFastCycle(mutation: number?): boolean
	return mutation == enums.Mutations.RAINBOW or mutation == enums.Mutations.CELESTIAL
end

function utils.getColoredTextForMutation(str: string, mutation: number?): string
	local colors = utils.getColorsForMutation(mutation)

	if #colors == 1 then
		return utils.getColoredText(str, colors[1])
	end

	local s = ""

	local colorIndex = 1

	for i = 1, #str do
		local ch = str:sub(i, i)
		local colorStr = colors[colorIndex]:ToHex()
		s = s .. string.format("<font color=\"#%s\">%s</font>", colorStr, ch)
		colorIndex = (colorIndex % #colors) + 1
	end

	return s
end

function utils.getColorForModification(modification: number?): Color3
	if modification == nil or modification == enums.Modifications.WET then
		return Color3.fromRGB(240, 240, 240)
	end

	if modification == enums.Modifications.BLOOM then
		return Color3.fromRGB(240, 240, 240)
	end

	if modification == enums.Modifications.WINDY then
		return Color3.fromRGB(240, 240, 240)
	end

	if modification == enums.Modifications.HOT then
		return Color3.fromRGB(240, 240, 240)
	end

	if modification == enums.Modifications.GREEN_FLAME then
		return Color3.fromRGB(0, 249, 0)
	end

	if modification == enums.Modifications.BLUE_FLAME then
		return Color3.fromRGB(0, 150, 255)
	end

	if modification == enums.Modifications.RED_FLAME then
		return Color3.fromRGB(255, 38, 0)
	end

	warn("unknown modification", modification)
	return Color3.new(0, 0, 0)
end

function utils.getColoredTextForModification(str: string, modification: number?): string
	local color = utils.getColorForModification(modification)
	return utils.getColoredText(str, color)
end

function utils.getColoredTextForModifications(modifications: { number }): string
	local retval = ""

	if #modifications == 0 then
		return retval
	end

	for i, modification in modifications do
		if i > 1 then
			retval = retval .. ", "
		end
		-- every modification has a public name, so the assert cannot fire for valid values
		local modificationName = assert(enums.getPublicName(enums.Modifications, modification))
		retval = retval .. utils.getColoredTextForModification(modificationName, modification)
	end

	return retval
end

function utils.getDecodedModifications(encodedModifications: string?): { number }
	local modifications: { number } = {}
	if encodedModifications then
		modifications = game:GetService("HttpService"):JSONDecode(encodedModifications)
	end
	return modifications
end

function utils.getMutModText(mutation: number?, modifications: { number }?): string
	local mutationName: string? = nil
	if mutation ~= enums.Mutations.NORMAL then
		mutationName = enums.getPublicName(enums.Mutations, mutation)
	end
	local mutationSuffix = ""
	if mutationName then
		mutationSuffix = " (" .. mutationName .. ")"
	end

	local modificationSuffix = ""

	if modifications and #modifications > 0 then
		if mutationSuffix ~= "" then
			mutationSuffix = mutationSuffix .. " "
		end

		modificationSuffix = " ["
		for i, modification in modifications do
			if i > 1 then
				modificationSuffix = modificationSuffix .. ", "
			end
			-- every modification has a public name, so the assert cannot fire for valid values
			modificationSuffix = modificationSuffix .. assert(enums.getPublicName(enums.Modifications, modification))
		end
		modificationSuffix = modificationSuffix .. "]"
	end

	return mutationSuffix .. modificationSuffix
end

function utils.getMutModRichText(mutation: number?, modifications: { number }): string
	local mText = ""
	if mutation and mutation ~= enums.Mutations.NORMAL then
		-- every mutation except NORMAL has a public name, so the assert cannot fire here
		local rawMutationText = assert(enums.getPublicName(enums.Mutations, mutation))

		mText = mText .. utils.getColoredTextForMutation(rawMutationText, mutation)
	end

	--print("inst", inst, "has modifications", inst:GetAttribute(Attributes.MODIFICATIONS))
	local modificationText = utils.getColoredTextForModifications(modifications)
	if mText ~= "" and modificationText ~= "" then
		mText = mText .. " - "
	end
	mText = mText .. modificationText

	return mText
end

function utils.getMutModRichTextForInstance(inst: Instance): string
	local mutation = inst:GetAttribute(Attributes.MUTATION) :: number?
	local encodedModifications = inst:GetAttribute(Attributes.MODIFICATIONS) :: string?
	local modifications = utils.getDecodedModifications(encodedModifications)

	return utils.getMutModRichText(mutation, modifications)
end

function utils.getContrastingColor(color: Color3): Color3
	local isBright = false
	if color.R > 0.6 or color.G > 0.6 or color.B > 0.6 then
		isBright = true
	end
	if color.R + color.G + color.B > 1.5 then
		isBright = true
	end

	if isBright then
		-- darken it
		return Color3.new(color.R / 2, color.G / 2, color.B / 2)
	end

	-- lighten it
	return Color3.new(color.R  + (1 - color.R) / 2, color.G + (1 - color.G) / 2, color.B + (1 - color.B) / 2)
end

function utils.getCountNewlines(text: string): number
    local count = 0
    -- The pattern "[\n]" matches each occurrence of a newline character.
    for _ in string.gmatch(text, "[\n]") do
        count += 1
    end
    return count
end

-- sec is an initial delay
function utils.safelyDisposeOfParticle(effect: ParticleEmitter, sec: number?)
	task.delay(sec or 0,
		function()
			effect.Enabled = false
			task.wait(effect.Lifetime.Max)
			-- use debris service for safety in case effect gets destroyed another way
			game:GetService("Debris"):AddItem(effect, 0)
		end
	)
end

-- sec is an initial delay
function utils.safelyDisposeOfParticleParent(parent: Instance, sec: number?, func: (() -> ())?)
	local totalSec = sec or 0
	for _, inst in parent:GetDescendants() do
		if not inst:IsA("ParticleEmitter") then
			continue
		end
		utils.safelyDisposeOfParticle(inst, sec)
		totalSec = math.max(totalSec, (sec or 0) + inst.Lifetime.Max)
	end

	task.delay(totalSec,
		function()
			-- use debris service for safety in case effect gets destroyed another way
			game:GetService("Debris"):AddItem(parent, 0)

			if func then
				func()
			end
		end
	)
end

function utils.getInstanceSize(inst: Instance): Vector3
	local size: Vector3
	if inst:IsA("Model") then
		size = inst:GetExtentsSize()
	else
		size = (inst :: BasePart).Size
	end
	return size
end

function utils.getInstanceHeight(inst: Instance): number
	return utils.getInstanceSize(inst).Y
end

-- resolves the instance's main BasePart: the instance itself, or a model's PrimaryPart. Falls
-- back to the first BasePart descendant because PrimaryPart is a reference property that can
-- replicate to clients after the model's parts do (e.g. right after an item held in the hand is
-- placed back into the workspace, or when a model streams in), so a nil PrimaryPart on a client
-- does not mean the part is missing
function utils.getMainPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end

	if inst:IsA("Model") then
		local primaryPart = inst.PrimaryPart
		if primaryPart then
			return primaryPart
		end
		return inst:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

function utils.getPathReference(root: Instance, path: string): Instance?
	local pathArr = string.split(path, ".")
	local inst = root
	for _, pathNodeStr in pathArr do
		local parent = inst
		inst = parent:WaitForChild(pathNodeStr)
		if (inst :: Instance?) == nil then
			warn("failed to load game asset", path, parent, pathNodeStr)
			return nil
		end
	end

	return inst
end

function utils.getGameAssetPathReference(path: string): Instance?
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
	return utils.getPathReference(GameAssets, path)
end

function utils.getHoldingToolWithHandle(player: Player): Tool?
	-- assert keeps the same crash-if-no-character behavior this had before being typed
	local character = assert(player.Character, "player has no character")
	local tool = character:FindFirstChildOfClass("Tool")
	if tool and not tool:FindFirstChild("Handle") then
		tool = nil
	end
	return tool
end

-- if you call this, no guarantee we check held items because we may not have character yet
function utils.getPlayerHandles(player: Player): { Instance }
	local tbl: { Instance } = {}

	for _, tool in player.Backpack:GetChildren() do
		if not tool:IsA("Tool") then
			continue
		end

		local handle = tool:FindFirstChild("Handle")
		if not handle then
			continue
		end

		table.insert(tbl, handle)
	end

	local character = player.Character
	-- we don't do "or player.CharacterAdded:Wait()" because that can hang for seconds or minutes
	if not character then
		return tbl
	end

	for _, tool in character:GetChildren() do
		if not tool:IsA("Tool") then
			continue
		end

		local handle = tool:FindFirstChild("Handle")
		if not handle then
			continue
		end

		table.insert(tbl, handle)
	end

	return tbl
end

-- if you call this, no guarantee we check held items because we may not have character yet
function utils.getPlayerUnequippables(player: Player): { Instance }
	local tbl: { Instance } = {}

	for _, tool in player.Backpack:GetChildren() do
		if not tool:IsA("Tool") then
			continue
		end

		local unequippable = tool:FindFirstChild(Constants.UNEQUIPPABLE_NAME)
		if not unequippable then
			continue
		end

		table.insert(tbl, unequippable)
	end

	return tbl
end

function utils.tryGetHandleForPlayerAndItemId(player: Player, itemId: number): Instance?
	local tbl = utils.getPlayerHandles(player)
	for _, part in tbl do
		if part:GetAttribute(Attributes.ITEM_ID) == itemId then
			return part
		end
	end

	return nil
end

-- model must have Attributes.USER_ID and Attributes.ITEM_ID
function utils.tryGetHandleForModel(inst: Instance): Instance?
	local itemId = inst:GetAttribute(Attributes.ITEM_ID) :: number
	local userId = inst:GetAttribute(Attributes.USER_ID) :: number
	local playersService = game:GetService("Players")
	local player = playersService:GetPlayerByUserId(userId)
	if not player then
		return nil
	end
	return utils.tryGetHandleForPlayerAndItemId(player, itemId)
end

function utils.tryGetUnequippableForPlayerAndItemId(player: Player, itemId: number): Instance?
	local tbl = utils.getPlayerUnequippables(player)
	for _, part in tbl do
		if part:GetAttribute(Attributes.ITEM_ID) == itemId then
			return part
		end
	end

	return nil
end

function utils.tryGetModelForPlayerAndItemId(player: Player, itemId: number): Instance?
	for _, inst in player.Backpack:GetChildren() do
		-- checking exactly Model, because tools are models
		if inst.ClassName ~= "Model" then
			continue
		end

		if inst:GetAttribute(Attributes.ITEM_ID) ~= itemId then
			continue
		end

		return inst
	end

	return nil
end

function utils.tryGetObjByPlayerAndItemId(player: Player, itemId: number): Instance?
	local part = utils.tryGetHandleForPlayerAndItemId(player, itemId) or utils.tryGetUnequippableForPlayerAndItemId(player, itemId)
	if not part then
		return nil
	end

	local model = utils.tryGetModelForPlayerAndItemId(player, part:GetAttribute(Attributes.ITEM_ID) :: number)
	local obj = model and model or part
	if not obj then
		return nil
	end

	return obj
end

function utils.getAssembliesInModel(model: Model): { BasePart }
	local assemblies: { BasePart } = {}
	local touchedAssemblies: { [BasePart]: boolean } = {}

	-- Iterate through all descendants to find BaseParts
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		local rootPart = descendant.AssemblyRootPart

		-- The rootPart will be nil if the part is not in the Workspace
		-- or not part of a physical assembly.
		-- Assemblies are only active within the Workspace or a WorldModel.
		if rootPart and not touchedAssemblies[rootPart] then
			-- Add the unique assembly root to the results
			table.insert(assemblies, rootPart)
			-- Mark this assembly root as found to avoid duplicates
			touchedAssemblies[rootPart] = true
		end
	end

	return assemblies
end

function utils.addTreeToCollisionGroup(root: Instance, collisionGroupName: string)
	if root:IsA("BasePart") then
		root.CollisionGroup = collisionGroupName
	end

	for _, descendant in root:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		descendant.CollisionGroup = collisionGroupName
	end
end

function utils.pulseAttribute(inst: Instance, attribute: string, value: any)
	inst:SetAttribute(attribute, value)

	--print("turning attribute off momentarily; delaying because instant change to/from a value don't get replicated to the client")
	task.delay(0.02,
		function()
			inst:SetAttribute(attribute, nil)
		end
	)
end

function utils.capitalize(str: string): string
	-- outer parentheses force only one return value, discarding the rest of gsub's results
	return (str:gsub("^%l", string.upper))
end

function utils.getMessageFromTable(messageTable: { [string]: string }, number: number): string
	local numberStr = tostring(number)
	local defaultMessage = ""
	for key, message in messageTable do
		if key == numberStr then
			return message
		end
		if key == "default" then
			defaultMessage = message
		end
	end
	return defaultMessage
end

function utils.trimString(s: string): string
	-- this pattern matches every string, so the assert cannot fire
    return assert(string.match(s, "^%s*(.-)%s*$"))
end

-- this is a somewhat hacked-up version of ClientMutationManager. Couldn't use that directly because that works on items
function utils.applyMutationToObj(obj: Instance, mutation: number, mutationSurfaceAppearanceName: string?)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Mutations = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("Mutations")

	local checkParts = obj:GetDescendants()

	local colors = utils.getColorsForMutation(mutation)
	local color = colors[1]

	if mutationSurfaceAppearanceName then
		for _, part in checkParts do
			if not part:IsA("MeshPart") then
				continue
			end
			-- xxx hack, should mark this better
			if part.Name == "Saddle" then
				continue
			end

			-- parts that will get set with no texture and neon shouldn't get a surface appearance
			if part:GetAttribute(Attributes.MUTATION_TARGET) == true then
				continue
			end

			local surfaceAppearanceTemplate = assert(utils.findFirstDescendant(Mutations, mutationSurfaceAppearanceName), "missing mutation surface appearance " .. mutationSurfaceAppearanceName)

			-- create surface appearance
			local surfaceAppearance = surfaceAppearanceTemplate:Clone() :: SurfaceAppearance
			surfaceAppearance.Name = mutationSurfaceAppearanceName
			surfaceAppearance.Parent = part

			-- configure surface appearance
			surfaceAppearance.Color = color
			surfaceAppearance.EmissiveTint = color
		end
	end

	-- set the neon parts
	local mutationParts = utils.getAllDescendantsWithAttribute(obj, Attributes.MUTATION_TARGET, true)
	for _, mutationPart in mutationParts do
		-- mutation targets are always parts
		local mutationBasePart = mutationPart :: BasePart
		mutationBasePart.Material = Enum.Material.Neon
		mutationBasePart.Color = color
		if mutationBasePart:IsA("MeshPart") then
			mutationBasePart.TextureID = ""
		end
	end
end

function utils.formatLargePositiveInteger(number: number): string
	if number < 1000000 then
		return tostring(number)
	end
	local millions = number // 1000000
	local frac = number - (millions * 1000000)
	local fracLimit = math.floor(frac / 1000 + 0.5)
	if fracLimit == 0 then
		return string.format("%iM", millions)
	end
	return string.format("%i.%03iM", millions, fracLimit)
end

function utils.formatLargeInteger(number: number): string
	if number < 0 then
		return "-" .. utils.formatLargePositiveInteger(-number)
	end

	return utils.formatLargePositiveInteger(number)
end

return utils