--!strict

-- Dubins path planner for Roblox

local Dubins = {}

local Types = require("./Types")

export type Plan = Types.DubinsPlan

local function mod2pi(theta: number): number
    local twopi = 2 * math.pi
    return theta - twopi * math.floor(theta / twopi)
end

local function transformToLocal(start: CFrame, goal: CFrame): (number, number, number)
    -- Returns (dx, dy, dtheta) in start's local frame
    local dx = goal.Position.X - start.Position.X
	local dz = goal.Position.Z - start.Position.Z
    local heading = math.atan2(start.LookVector.Z, start.LookVector.X)
    local goalHeading = math.atan2(goal.LookVector.Z, goal.LookVector.X)
    local localX = math.cos(heading) * dx + math.sin(heading) * dz
    local localY = math.sin(heading) * dx - math.cos(heading) * dz
    local dtheta = mod2pi(goalHeading - heading)

	--print("transformed to local: localX", localX, "localY", localY, "dtheta", dtheta)
	--print("current heading deg", math.deg(heading), "goal heading deg", math.deg(goalHeading))

    return localX, localY, dtheta
end

local PathType = {
    LSL = 1, RSR = 2, LSR = 3, RSL = 4, RLR = 5, LRL = 6
}
local PathTypeNames = {"LSL", "RSR", "LSR", "RSL", "RLR", "LRL"}

local function dubinsParameters(localX: number, localY: number, dtheta: number, radius: number): { { number } }
    -- Returns a table of {t1, t2, t3, type, totalLength}
    local params: { { number } } = {}
    local dx = localX
    local dy = localY
    local D = math.sqrt(dx*dx + dy*dy)
    local d = D / radius
    local theta = mod2pi(math.atan2(dy, dx))
	--print("dy", dy, "dx", dx, "atan2", math.atan2(dy, dx), "theta", theta)
	--print("theta", theta)
    local alpha = mod2pi(-theta)
	--print("alpha", alpha)
    local beta = mod2pi(dtheta - theta)
	--print("beta components", dtheta, theta)
	--print("beta", beta)

    local ca = math.cos(alpha)
    local sa = math.sin(alpha)
    local cb = math.cos(beta)
    local sb = math.sin(beta)
	local cab = math.cos(alpha - beta)

    -- LSL
    local p_squared = 2 + (d*d) - (2*cab) + (2*d*(sa - sb))
    if p_squared >= 0 then
		local tmp0 = d + sa - sb
        local p = math.sqrt(p_squared)
		--print("calling atan2 with", cb - ca, tmp0)
		local tmp1 = math.atan2((cb - ca), tmp0)
        local t1 = mod2pi(tmp1 - alpha)
        local t2 = p
        local t3 = mod2pi(beta - tmp1)
		--print("LSL tmp0", tmp0, "tmp1", tmp1)
		--print("LSL OK")
        table.insert(params, {t1, t2, t3, PathType.LSL, (t1 + t2 + t3) * radius})
    end

    -- RSR
    p_squared = 2 + (d*d) - (2*cab) + (2*d*(sb - sa))
    if p_squared >= 0 then
        local p = math.sqrt(p_squared)
		local tmp0 = d - sa + sb
		local tmp1 = math.atan2((ca - cb), tmp0)
        local t1 = mod2pi(alpha - tmp1)
        local t2 = p
        local t3 = mod2pi(tmp1 - beta)
		--print("RSR OK")
        table.insert(params, {t1, t2, t3, PathType.RSR, (t1 + t2 + t3) * radius})
    end

    -- LSR
    p_squared = -2 + (d*d) + (2*cab) + (2*d*(sa + sb))
    if p_squared >= 0 then
        local p = math.sqrt(p_squared)
		local tmp0 = math.atan2(-ca - cb, (d + sa + sb)) - math.atan2(-2, p)
        local t1 = mod2pi(tmp0 - alpha)
        local t2 = p
        local t3 = mod2pi(tmp0 - beta)
		--print("LSR OK")
		--print("LSR tmp0", tmp0)
		--print("LSR result", t1, t2, t3)
        table.insert(params, {t1, t2, t3, PathType.LSR, (t1 + t2 + t3) * radius})
    end

    -- RSL
    p_squared = -2 + (d*d) + (2*cab) - (2*d*(sa + sb))
    if p_squared >= 0 then
        local p = math.sqrt(p_squared)
		local tmp0 = math.atan2((ca + cb), (d - sa - sb)) - math.atan2(2, p)
        local t1 = mod2pi(alpha - tmp0)
        local t2 = p
        local t3 = mod2pi(beta - tmp0)
		--print("RSL OK")
		--print("RSL tmp0", tmp0)
		--print("RSL result", t1, t2, t3)
        table.insert(params, {t1, t2, t3, PathType.RSL, (t1 + t2 + t3) * radius})
    end

    -- RLR
    local tmp_rlr = (6 - d*d + 2*cab + 2*d*(sa - sb)) / 8
    if math.abs(tmp_rlr) <= 1 then
		local phi = math.atan2(ca - cb, d - sa + sb)
        local p = mod2pi(2 * math.pi - math.acos(tmp_rlr))
		local t = mod2pi(alpha - phi + mod2pi(p/2))
		local t1 = t
		local t2 = p
		local t3 = mod2pi(alpha - beta - t + mod2pi(p))

        --local t1 = mod2pi(alpha - p/2)
        --local t2 = p
        --local t3 = mod2pi(beta - alpha + p/2)
		--print("RLR OK")
		--print("RLR tmp_rlr", tmp_rlr)
		--print("RLR result", t1, t2, t3)
        table.insert(params, {t1, t2, t3, PathType.RLR, (t1 + t2 + t3) * radius})
    end

	-- checked to here
    -- LRL
    local tmp_lrl = (6 - d*d + 2*cab + 2*d*(sb - sa)) / 8
	--print("d^2", d*d, "cab", cab, "sa", sa, "sb", sb, "tmp_lrl", tmp_lrl);
    if math.abs(tmp_lrl) <= 1 then
		local phi = math.atan2(ca - cb, d + sa - sb)
        local p = mod2pi(2 * math.pi - math.acos(tmp_lrl))
        local t = mod2pi(-alpha - phi + p/2)
        local t1 = t
        local t2 = p
		local t3 = mod2pi(mod2pi(beta) - alpha - t + mod2pi(p))
		--print("LRL OK")
		--print("LRL tmp_lrl", tmp_lrl, "phi", phi, "p", p, "t", t)
		--print("LRL result", t1, t2, t3, "cost", (t1 + t2 + t3))
		--print("inserting lrl")
        table.insert(params, {t1, t2, t3, PathType.LRL, (t1 + t2 + t3) * radius})
    end

    return params
end

local function addSegment(path: { CFrame }, stepSize: number, segmentType: string, segTheta: number, segLength: number, segRadius: number)
	--print("adding segment", segmentType, segTheta, segLength, segRadius)

	if segLength == 0 then
		segLength = segRadius * segTheta
	end

	local steps = math.max(1, math.floor((segTheta ~= 0 and math.abs(segTheta * segRadius) or segLength) / stepSize))
	--print("total steps", steps)
	local frac = 1 / steps

	local fracLength = frac * segLength

	local fracTheta = frac * segTheta
	for i = 1, steps do
		local prev = path[#path]

		local nextRotation: CFrame
		if segmentType == "L" then
			nextRotation = CFrame.fromEulerAnglesXYZ(0, fracTheta, 0) * prev.Rotation
		elseif segmentType == "R" then
			nextRotation = CFrame.fromEulerAnglesXYZ(0, -fracTheta, 0) * prev.Rotation
		elseif segmentType == "S" then
			nextRotation = prev.Rotation
		end

		-- whether turning or going straight, we always move a bit
		local nextPosition = prev.Position + prev.LookVector * fracLength

		local current = nextRotation + nextPosition

		--local current = rotation * prev.Rotation + (prev.Position + translation)
		--print("inserting", current.Position, "looking at", current.LookVector)
		table.insert(path, current)
	end
end

-- Returns an array of CFrames along the Dubins path
local function generatePath(startCFrame: CFrame, radius: number, stepSize: number, t1: number, t2: number, t3: number, pathType: number): { CFrame }
    local path: { CFrame } = {startCFrame}
    if pathType == PathType.LSL then
        addSegment(path, stepSize, "L", t1, 0, radius)
        addSegment(path, stepSize, "S", 0, t2*radius, 0)
        addSegment(path, stepSize, "L", t3, 0, radius)
    elseif pathType == PathType.RSR then
        addSegment(path, stepSize, "R", t1, 0, radius)
        addSegment(path, stepSize, "S", 0, t2*radius, 0)
        addSegment(path, stepSize, "R", t3, 0, radius)
    elseif pathType == PathType.LSR then
        addSegment(path, stepSize, "L", t1, 0, radius)
        addSegment(path, stepSize, "S", 0, t2*radius, 0)
        addSegment(path, stepSize, "R", t3, 0, radius)
    elseif pathType == PathType.RSL then
        addSegment(path, stepSize, "R", t1, 0, radius)
        addSegment(path, stepSize, "S", 0, t2*radius, 0)
        addSegment(path, stepSize, "L", t3, 0, radius)
    elseif pathType == PathType.RLR then
        addSegment(path, stepSize, "R", t1, 0, radius)
        addSegment(path, stepSize, "L", t2, 0, radius)
        addSegment(path, stepSize, "R", t3, 0, radius)
    elseif pathType == PathType.LRL then
        addSegment(path, stepSize, "L", t1, 0, radius)
        addSegment(path, stepSize, "R", t2, 0, radius)
        addSegment(path, stepSize, "L", t3, 0, radius)
    end

    return path
end

function Dubins.tryCalculatePlan(startCFrame: CFrame, endCFrame: CFrame, minRadius: number, stepSize: number): Plan?
	--[[
	-- visualize beginning and end
	local blah = Instance.new("Part")
	blah.CFrame = startCFrame
	blah.Anchored = true
	blah.Parent = workspace

	blah = Instance.new("Part")
	blah.CFrame = endCFrame
	blah.Anchored = true
	blah.Parent = workspace
	]]

    local localX, localY, dtheta = transformToLocal(startCFrame, endCFrame)
    local candidates = dubinsParameters(localX, localY, dtheta, minRadius)
    if #candidates == 0 then
        return nil
    end

    -- Find shortest
	local bestIndexChoices: { number } = {}
    for i = 1, #candidates do
		--print("path", PathTypeNames[candidates[i][4]], "values", candidates[i][1], candidates[i][2], candidates[i][3], "cost", candidates[i][5]/minRadius, "raw", candidates[i][5]/minRadius, "raw")
		if #bestIndexChoices == 0 then
			table.insert(bestIndexChoices, i)
		else
			if candidates[i][5] < candidates[bestIndexChoices[1]][5] + 1e-5 then
				if math.abs(candidates[i][5] - candidates[bestIndexChoices[1]][5]) < 1e-5 then
					--print("got essentially equivalent", i, bestIndexChoices[1])
					table.insert(bestIndexChoices, i)
				else
					bestIndexChoices = {}
					table.insert(bestIndexChoices, i)
				end

			end
		end
    end
    local best: { number } = {0, 0, 0, 0, math.huge}
	local random = Random.new()
	if #bestIndexChoices > 0 then
		--print("have", #bestIndexChoices, "choices")
		local bestIndex = random:NextInteger(1, #bestIndexChoices)
		best = candidates[bestIndex]
	end
    local t1, t2, t3, pathType = best[1], best[2], best[3], best[4]
	local bestName = PathTypeNames[best[4]]
	--print("best is", bestName)
    local path = generatePath(startCFrame, minRadius, stepSize, t1, t2, t3, pathType)

	return {
		path = path,
		type = bestName,
	}
end

return Dubins
