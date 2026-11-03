--!strict

local ClientDragonBodyTrail = {}
ClientDragonBodyTrail.__index = ClientDragonBodyTrail

local runService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local DragonFlightSettings = require("@game/ReplicatedStorage/Shared/DragonFlightSettings")
local DragonTrailMath = require("@game/ReplicatedStorage/Shared/DragonTrailMath")

-- The procedural body trail (Control/DragonFlight.useLegacyFlight = false). A dragon's body is a chain of separate parts joined by
-- ball sockets. In the legacy flight those joints are simulated; here they are switched off and only the head moves for real: each
-- frame every body part is placed behind the part in front of it (follow the path of the leader, bend limited, plus a sine bob).
-- Adapted from the Dragon Riders package (DragonFlightVisuals, studied 2026-november-2).
--
-- The chain is read from the model itself: the ball-socket tree from the PrimaryPart. At every part the child with the longest
-- chain behind it is the spine (Head, Body_01..N, Tail); other children (legs) and anything welded or loose are rigid followers.
--
-- It steps on Heartbeat, after the physics step (PreRender runs before it), from a smoothed head position, because the head's position read
-- once a frame is uneven and the camera follows the rider on the body.

local SEAT_NAME = "Saddle"
-- ClientDragonManager flaps these every frame from attachments on the head, so the trail leaves them alone
local FLAPPED_PART_NAMES: { [string]: boolean } = { Wing_Left = true, Wing_Right = true }

local MIN_LINK_DISTANCE = 0.01
local LIFT_FOLLOW_RATE = 8 -- per second
local MAX_HEAD_LAG_STUDS = 1

type Node = {
	part: BasePart,
	parentIndex: number, -- index in nodes of the part in front of this one; 0 is the head
	isSpine: boolean,
	spineIndex: number, -- 1 for the first trailing part (0 for followers)
	distance: number, -- spine: rest distance to the part in front
	restDirectionLocal: Vector3, -- spine: unit direction to this part, in the part in front's frame
	restRotation: CFrame, -- spine: rotation of the part relative to "looking at the part in front"
	offsetPosition: Vector3, -- follower: position in the parent's frame
	offsetRotation: CFrame,
	restRelPosition: Vector3, -- rest pose in the head's frame, for the rigid pose and for resets
	restRelRotation: CFrame,
}

type Wing = {
	part: BasePart,
	anchor: BasePart, -- the part carrying the attachment the flapping code places this wing from
}

type Rig = {
	head: BasePart,
	nodes: { Node },
	spineCount: number, -- how many of the nodes are on the spine
	baseScale: number,
	headGroup: { [BasePart]: boolean }, -- the head and everything welded to it
	drivenParts: { [BasePart]: boolean }, -- the parts whose CFrame the trail sets every frame
	wings: { Wing }, -- the wings, which ClientDragonManager places each physics step from attachments on a body part (the head or a spine part)
	seatPart: BasePart?, -- the part the rider sits on; it trails with the body part it belongs to
}

type DragonState = {
	itemId: number,
	caster: Model,
	shadow: any, -- world shadow part; its attributes only exist at runtime
	rig: Rig,
	positions: { Vector3 },
	cframes: { CFrame },
	renderOffsets: { Vector3 }, -- drawn-only offsets per node (the hover sway), kept out of the chain
	anchorBefore: { [BasePart]: CFrame }, -- each wing anchor's pose at the start of the step
	bobTime: number,
	lastHeadPosition: Vector3,
	smoothPosition: Vector3, -- the head position the body is built from (see smoothPoint)
	smoothVelocity: Vector3,
	headSpeed: number,
	needsReset: boolean,
	targetLift: number, -- height the idle hover pulse has lifted the head, which the whole body shares
	lift: number, -- targetLift eased in, so the lift changing suddenly (a ride starting) does not jerk the body
}

type ClientDragonBodyTrailFields = {
	config: DragonFlightSettings.DragonFlightConfig?,
	modeOverride: string?,
	modeChangedEvent: BindableEvent,
	dragons: { [number]: DragonState },
	dragonCount: number,
	renderConnect: RBXScriptConnection?,
	warnedNames: { [string]: boolean },
}

export type ClientDragonBodyTrail = typeof(setmetatable({} :: ClientDragonBodyTrailFields, ClientDragonBodyTrail))

local function findGroupRoot(groupRoots: { [BasePart]: BasePart }, part: BasePart): BasePart
	local current = part
	while true do
		local parent: BasePart? = groupRoots[current]
		if parent == nil or parent == current then
			return current
		end
		current = parent
	end
end

local function unionGroups(groupRoots: { [BasePart]: BasePart }, partA: BasePart, partB: BasePart)
	local rootA = findGroupRoot(groupRoots, partA)
	local rootB = findGroupRoot(groupRoots, partB)
	if rootA ~= rootB then
		groupRoots[rootA] = rootB
	end
end

local function getScaledCFrame(position: Vector3, rotation: CFrame, scaleRatio: number): CFrame
	return CFrame.new(position * scaleRatio) * rotation
end

-- Reads the body of a caster in its rest pose. Returns nil and a reason when the model is not shaped like a chain this system can
-- drive; the caller then keeps that dragon on the legacy physics.
local function buildRig(caster: Model): (Rig?, string?)
	local head = caster.PrimaryPart
	if not head then
		return nil, "the model has no PrimaryPart"
	end

	-- the ball-socket tree: Attachment0 is on the part nearer the head
	local children: { [BasePart]: { BasePart } } = {}
	local hasParent: { [BasePart]: boolean } = {}
	for _, descendant in caster:GetDescendants() do
		if not descendant:IsA("BallSocketConstraint") then
			continue
		end

		local attachment0 = descendant.Attachment0
		local attachment1 = descendant.Attachment1
		local ownerPart = attachment0 and attachment0.Parent
		local childPart = attachment1 and attachment1.Parent
		if not ownerPart or not childPart or not ownerPart:IsA("BasePart") or not childPart:IsA("BasePart") then
			continue
		end
		if hasParent[childPart] then
			return nil, "a part has two ball sockets in front of it: " .. childPart.Name
		end

		hasParent[childPart] = true
		if not children[ownerPart] then
			children[ownerPart] = {}
		end
		table.insert(children[ownerPart], childPart)
	end
	if hasParent[head] then
		return nil, "the PrimaryPart hangs off another part"
	end
	if not children[head] then
		return nil, "the PrimaryPart has no ball socket behind it"
	end

	-- parts joined by welds move together
	local groupRoots: { [BasePart]: BasePart } = {}
	for _, descendant in caster:GetDescendants() do
		local partA: Instance? = nil
		local partB: Instance? = nil
		if descendant:IsA("WeldConstraint") then
			partA = descendant.Part0
			partB = descendant.Part1
		elseif descendant:IsA("JointInstance") then
			partA = descendant.Part0
			partB = descendant.Part1
		end
		if partA and partB and partA:IsA("BasePart") and partB:IsA("BasePart") then
			unionGroups(groupRoots, partA, partB)
		end
	end

	-- longest chain behind each part, to pick the spine
	local heights: { [BasePart]: number } = {}
	local visiting: { [BasePart]: boolean } = {}
	local function getHeight(part: BasePart): number
		local known = heights[part]
		if known then
			return known
		end
		if visiting[part] then
			return 0
		end
		visiting[part] = true
		local best = 0
		local kids: { BasePart }? = children[part]
		if kids then
			for _, child in kids do
				best = math.max(best, getHeight(child))
			end
		end
		visiting[part] = nil
		heights[part] = best + 1
		return best + 1
	end

	local headCFrame = head.CFrame
	local nodes: { Node } = {}
	local treeParts: { [BasePart]: boolean } = { [head] = true }
	local nodeIndexByPart: { [BasePart]: number } = { [head] = 0 }
	local partCountGuard = 0

	local function getPartCFrame(index: number): CFrame
		if index == 0 then
			return headCFrame
		end
		return nodes[index].part.CFrame
	end

	local function addNode(part: BasePart, parentIndex: number, isSpine: boolean, spineIndex: number): number
		local parentCFrame = getPartCFrame(parentIndex)
		local partCFrame = part.CFrame
		local relative = headCFrame:ToObjectSpace(partCFrame)

		local node: Node = {
			part = part,
			parentIndex = parentIndex,
			isSpine = isSpine,
			spineIndex = if isSpine then spineIndex else 0,
			distance = 0,
			restDirectionLocal = Vector3.zero,
			restRotation = CFrame.identity,
			offsetPosition = Vector3.zero,
			offsetRotation = CFrame.identity,
			restRelPosition = relative.Position,
			restRelRotation = relative.Rotation,
		}

		if isSpine then
			local toPart = partCFrame.Position - parentCFrame.Position
			node.distance = toPart.Magnitude
			if node.distance >= MIN_LINK_DISTANCE then
				node.restDirectionLocal = parentCFrame:VectorToObjectSpace(toPart.Unit)
				local lookRest = DragonTrailMath.getLookCFrame(partCFrame.Position, parentCFrame.Position, parentCFrame.UpVector)
				node.restRotation = lookRest.Rotation:Inverse() * partCFrame.Rotation
			end
		else
			local offset = parentCFrame:ToObjectSpace(partCFrame)
			node.offsetPosition = offset.Position
			node.offsetRotation = offset.Rotation
		end

		table.insert(nodes, node)
		local index = #nodes
		nodeIndexByPart[part] = index
		treeParts[part] = true
		return index
	end

	-- depth-first, so a part always comes after the part in front of it
	local failure: string? = nil
	local function visit(part: BasePart, index: number, isOnSpine: boolean, spineIndex: number)
		local kids = children[part]
		if not kids or failure then
			return
		end

		local sorted = table.clone(kids)
		table.sort(sorted, function(a: BasePart, b: BasePart)
			local heightA, heightB = getHeight(a), getHeight(b)
			if heightA ~= heightB then
				return heightA > heightB
			end
			return a.Name < b.Name
		end)

		for kidNumber, kid in sorted do
			partCountGuard += 1
			if partCountGuard > 200 then
				failure = "the ball-socket tree is too big or loops"
				return
			end
			if treeParts[kid] then
				failure = "the ball-socket tree loops at " .. kid.Name
				return
			end

			local isSpineKid = isOnSpine and kidNumber == 1
			local kidSpineIndex = if isSpineKid then spineIndex + 1 else 0
			local kidIndex = addNode(kid, index, isSpineKid, kidSpineIndex)
			if isSpineKid and nodes[kidIndex].distance < MIN_LINK_DISTANCE then
				failure = "two spine parts sit on the same spot at " .. kid.Name
				return
			end
			visit(kid, kidIndex, isSpineKid, kidSpineIndex)
		end
	end
	visit(head, 0, true, 0)
	if failure then
		return nil, failure
	end

	-- weld groups: the head's group rides the head; a group with a tree part rides that part; any other group follows the nearest part
	local headRoot = findGroupRoot(groupRoots, head)
	local headGroup: { [BasePart]: boolean } = {}
	local treeRootToIndex: { [BasePart]: number } = {}
	for _, node in nodes do
		local root = findGroupRoot(groupRoots, node.part)
		if root == headRoot then
			return nil, "a body part is welded to the head: " .. node.part.Name
		end
		if treeRootToIndex[root] then
			return nil, "two body parts are welded together: " .. node.part.Name
		end
		treeRootToIndex[root] = nodeIndexByPart[node.part]
	end

	local looseRoots: { [BasePart]: BasePart } = {}
	for _, descendant in caster:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		local root = findGroupRoot(groupRoots, descendant)
		if root == headRoot then
			headGroup[descendant] = true
		elseif not treeRootToIndex[root] and not looseRoots[root] and not FLAPPED_PART_NAMES[descendant.Name] then
			looseRoots[root] = descendant
		end
	end

	for _, loosePart in looseRoots do
		local nearestIndex = 0
		local nearestDistance = (loosePart.Position - head.Position).Magnitude
		for index, node in nodes do
			local distance = (loosePart.Position - node.part.Position).Magnitude
			if distance < nearestDistance then
				nearestIndex = index
				nearestDistance = distance
			end
		end
		addNode(loosePart, nearestIndex, false, 0)
	end

	-- the rider's seat: the Saddle if there is one, else the marked part nearest the head
	local seatPart: BasePart? = nil
	local seatDistance = math.huge
	for _, descendant in caster:GetDescendants() do
		if not descendant:IsA("BasePart") or not descendant:GetAttribute(Attributes.SEAT_LOCATION) then
			continue
		end

		local distance = (descendant.Position - head.Position).Magnitude
		if descendant.Name == SEAT_NAME then
			distance = -1
		end
		if distance < seatDistance then
			seatPart = descendant
			seatDistance = distance
		end
	end

	local drivenParts: { [BasePart]: boolean } = {}
	local spineCount = 0
	for _, node in nodes do
		drivenParts[node.part] = true
		if node.isSpine then
			spineCount += 1
		end
	end

	-- ClientDragonManager places each wing from the attachment of the same name on a body part; remember which part that is
	local wings: { Wing } = {}
	for partName in FLAPPED_PART_NAMES do
		local wingPart = caster:FindFirstChild(partName)
		if wingPart and wingPart:IsA("BasePart") then
			for _, descendant in caster:GetDescendants() do
				local anchorPart = descendant.Parent
				if descendant:IsA("Attachment") and descendant.Name == partName and anchorPart and anchorPart ~= wingPart and anchorPart:IsA("BasePart") then
					table.insert(wings, { part = wingPart, anchor = anchorPart })
					break
				end
			end
		end
	end

	local rig: Rig = {
		head = head,
		nodes = nodes,
		spineCount = spineCount,
		wings = wings,
		baseScale = caster:GetScale(),
		headGroup = headGroup,
		drivenParts = drivenParts,
		seatPart = seatPart,
	}
	return rig, nil
end

local function describeMode(isLegacy: boolean): string
	return if isLegacy then "legacy" else "new"
end

-- true when dragons built from now on get the procedural trail
function ClientDragonBodyTrail.isEnabled(self: ClientDragonBodyTrail): boolean
	if self.modeOverride == "new" then
		return true
	elseif self.modeOverride == "legacy" then
		return false
	end

	local config = self.config
	return config ~= nil and not config.useLegacyFlight
end

function ClientDragonBodyTrail.getModeName(self: ClientDragonBodyTrail): string
	return describeMode(not self:isEnabled())
end

-- fires when the effective mode changes; ClientShadowManager rebuilds the dragons' bodies
function ClientDragonBodyTrail.getModeChangedEvent(self: ClientDragonBodyTrail): RBXScriptSignal
	return self.modeChangedEvent.Event
end

function ClientDragonBodyTrail.setConfig(self: ClientDragonBodyTrail, config: any)
	local wasEnabled = self:isEnabled()
	self.config = DragonFlightSettings.normalize(config)
	if self:isEnabled() ~= wasEnabled then
		self.modeChangedEvent:Fire()
	end
end

-- dev only: "new", "legacy", or nil to follow the server's config again
function ClientDragonBodyTrail.setModeOverride(self: ClientDragonBodyTrail, mode: string?)
	local wasEnabled = self:isEnabled()
	self.modeOverride = if mode == "new" or mode == "legacy" then mode else nil
	if self:isEnabled() ~= wasEnabled then
		self.modeChangedEvent:Fire()
	end
end

-- Called every frame by the idle hover pulse (ClientDragonManager.setupIdlePulsing) with how far it has lifted the head, 0 when it is off.
function ClientDragonBodyTrail.setLift(self: ClientDragonBodyTrail, itemId: number, liftY: number)
	local state = self.dragons[itemId]
	if state then
		state.targetLift = liftY
	end
end

-- true when this caster's body is driven by the trail (its rider's seat then moves with the body, not with the head)
function ClientDragonBodyTrail.isTrailCaster(self: ClientDragonBodyTrail, caster: Instance?): boolean
	for _, state in self.dragons do
		if state.caster == caster then
			return true
		end
	end

	return false
end

function ClientDragonBodyTrail.getTrailSettings(self: ClientDragonBodyTrail): DragonFlightSettings.TrailSettings
	local config = self.config
	return if config then config.trail else DragonFlightSettings.DEFAULT_TRAIL
end

local function resetChain(state: DragonState, headCFrame: CFrame, scaleRatio: number)
	for index, node in state.rig.nodes do
		local relative = getScaledCFrame(node.restRelPosition, node.restRelRotation, scaleRatio)
		state.positions[index] = (headCFrame * relative).Position
	end
end

local function placeRigid(state: DragonState, headCFrame: CFrame, scaleRatio: number)
	for _, node in state.rig.nodes do
		node.part.CFrame = headCFrame * getScaledCFrame(node.restRelPosition, node.restRelRotation, scaleRatio)
	end
end

function ClientDragonBodyTrail.stepDragon(self: ClientDragonBodyTrail, state: DragonState, dt: number, cameraPosition: Vector3)
	local rig = state.rig
	local trail = self:getTrailSettings()
	local actualHeadCFrame = rig.head.CFrame
	local scaleRatio = state.caster:GetScale() / rig.baseScale

	-- where each wing's anchor part is before this step moves anything (the flapping code placed the wings from these poses)
	local anchorBefore = state.anchorBefore
	for _, wing in rig.wings do
		anchorBefore[wing.anchor] = wing.anchor.CFrame
	end

	-- The idle hover pulse moves the whole dragon up and down. The follow-the-leader body would stay behind a slow move like that
	-- (it only drags along its own length), so the trail works without the pulse and the pulse is added to every part afterwards.
	state.lift += (state.targetLift - state.lift) * math.min(1, dt * LIFT_FOLLOW_RATE)
	local liftVector = Vector3.new(0, state.lift, 0)
	local rawHeadCFrame = actualHeadCFrame - liftVector
	local rawHeadPosition = rawHeadCFrame.Position

	local moved = (rawHeadPosition - state.lastHeadPosition).Magnitude
	state.lastHeadPosition = rawHeadPosition
	if moved > trail.snapDistance then
		state.needsReset = true
	end

	local isRidden = state.shadow:GetAttribute(Attributes.DRAGON_RIDER) == true
	if not isRidden and (rawHeadPosition - cameraPosition).Magnitude > trail.maxActiveDistance then
		-- too far to see the trail: keep the body rigid and start clean when it comes back
		state.needsReset = true
		placeRigid(state, actualHeadCFrame, scaleRatio)
		return
	end

	if state.needsReset then
		state.needsReset = false
		state.smoothPosition = rawHeadPosition
		state.smoothVelocity = Vector3.zero
		resetChain(state, rawHeadCFrame, scaleRatio)
	else
		-- The head's position read once a frame is a little uneven (some frames the physics step has landed earlier or later). The engine
		-- hides that for the head it draws, but a body placed by script copies it, and the rider sits on the body, so the camera follows it
		-- too. Build the body from a smoothed head position instead. A flown (unanchored) head reports its real velocity, which follows a
		-- sudden turn at once; estimating it from positions made the smoothed head trail the real one and the neck stretched.
		local knownVelocity = if rig.head.Anchored then nil else rig.head.AssemblyLinearVelocity
		state.smoothPosition, state.smoothVelocity = DragonTrailMath.smoothPoint(
			state.smoothPosition,
			state.smoothVelocity,
			rawHeadPosition,
			dt,
			trail.headSmoothingSec,
			knownVelocity
		)

		-- never let the smoothed head lag the real one by more than the unevenness it exists to remove
		local lag = state.smoothPosition - rawHeadPosition
		if lag.Magnitude > MAX_HEAD_LAG_STUDS then
			state.smoothPosition = rawHeadPosition + lag.Unit * MAX_HEAD_LAG_STUDS
		end

		-- A flown head is drawn from the physics body, whose position is uneven frame to frame (the physics runs in sub-steps and the number
		-- that land in a frame varies), while the body and the rider are now steady: the head seemed to lunge ahead of the body and drift
		-- back several times a second. Put the head on the same smoothed track. The next physics step starts from here, which is what keeps
		-- it steady. (The wings are carried along with their anchor part at the end of the step.)
		if not rig.head.Anchored then
			local nudge = state.smoothPosition + liftVector - actualHeadCFrame.Position
			if nudge.Magnitude > 0 then
				rig.head.CFrame = actualHeadCFrame + nudge
			end
		end
	end
	local headCFrame = CFrame.new(state.smoothPosition) * rawHeadCFrame.Rotation

	local rawSpeed = state.smoothVelocity.Magnitude
	state.headSpeed += (rawSpeed - state.headSpeed) * math.min(1, dt * 10)
	local bobScale = DragonTrailMath.getBobScale(isRidden, state.headSpeed)
	state.bobTime += dt * bobScale * trail.bobTimeRate
	-- a ridden dragon that hovers does not bob: the rider sits on the body. A dragon on its own keeps its idle sway.
	local motion = DragonTrailMath.getMotionFactor(state.headSpeed, trail.bobMinSpeed, trail.bobFullSpeed)
	local bobStrength = if isRidden then motion else 1
	local bobAmplitude = trail.bobAmplitude * scaleRatio * rig.baseScale * bobStrength

	-- A rider hovering still gets a gentle tail sway instead: none at the seat, growing to the tail tip. It is only drawn (added when the
	-- part is placed, never stored in the chain), so its size is the setting, unlike the bob above, which the chain feeds back on itself.
	local hoverAmplitude = if isRidden then trail.hoverTailBobAmplitude * scaleRatio * rig.baseScale * (1 - motion) else 0
	local renderOffsets = state.renderOffsets

	-- gentle while the dragon flies (so a turn keeps its curve), strong once it slows or stops (so the body settles back to straight)
	local straightenRate = trail.straightenRateAtRest + (trail.straightenRate - trail.straightenRateAtRest) * motion
	local straightenFactor = DragonTrailMath.getStraightenFactor(straightenRate, dt)

	local cframes = state.cframes
	for index, node in rig.nodes do
		local parentCFrame = if node.parentIndex == 0 then headCFrame else cframes[node.parentIndex]
		local cframe: CFrame
		if node.isSpine then
			local parentPosition = parentCFrame.Position
			local restDirection = parentCFrame:VectorToWorldSpace(node.restDirectionLocal)
			local limitDeg = if node.spineIndex == 1 then trail.firstLinkJointLimitDeg else trail.jointLimitDeg
			local linkDistance = node.distance * scaleRatio

			-- ease where the link was toward straight behind its parent. The parent has already eased this frame, so the straightening
			-- runs down the body one link behind the next and the tail settles last, like a whip coming to rest.
			local oldPosition = state.positions[index]
			if straightenFactor > 0 then
				oldPosition = oldPosition:Lerp(parentPosition + restDirection * linkDistance, straightenFactor)
			end

			local position = DragonTrailMath.getLinkPosition(parentPosition, restDirection, oldPosition, linkDistance, limitDeg)
			position += Vector3.new(
				0,
				DragonTrailMath.getBobOffset(state.bobTime, node.spineIndex, trail.bobPhaseStep, bobAmplitude, bobScale),
				0
			)
			state.positions[index] = position
			cframe = DragonTrailMath.getLookCFrame(position, parentPosition, parentCFrame.UpVector) * node.restRotation

			local renderOffset = Vector3.zero
			if hoverAmplitude > 0 then
				local tailWeight = DragonTrailMath.getTailWeight(node.spineIndex, rig.spineCount)
				renderOffset = Vector3.new(
					0,
					DragonTrailMath.getBobOffset(state.bobTime, node.spineIndex, trail.bobPhaseStep, hoverAmplitude * tailWeight, 1),
					0
				)
			end
			renderOffsets[index] = renderOffset
		else
			cframe = parentCFrame * getScaledCFrame(node.offsetPosition, node.offsetRotation, scaleRatio)
			renderOffsets[index] = if node.parentIndex == 0 then Vector3.zero else renderOffsets[node.parentIndex]
		end

		cframes[index] = cframe
		node.part.CFrame = cframe + liftVector + renderOffsets[index]
	end

	-- ClientDragonManager places the wings (PostSimulation, before this step) from their anchor part's pose of the step before, so they would
	-- sit one frame behind the body. Carry each wing by however far its anchor part just moved.
	for _, wing in rig.wings do
		local before = anchorBefore[wing.anchor]
		wing.part.CFrame = wing.anchor.CFrame * before:ToObjectSpace(wing.part.CFrame)
	end
end

function ClientDragonBodyTrail.step(self: ClientDragonBodyTrail, dt: number)
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero

	for itemId, state in self.dragons do
		if not state.caster.Parent or not state.rig.head.Parent then
			-- the caster was destroyed or is being rebuilt
			self:detach(itemId)
			continue
		end

		self:stepDragon(state, dt, cameraPosition)
	end
end

local function disablePhysicsBody(caster: Model, rig: Rig)
	for _, descendant in caster:GetDescendants() do
		if descendant:IsA("BallSocketConstraint") then
			descendant.Enabled = false
		elseif descendant:IsA("AlignOrientation") then
			descendant.Enabled = false
		elseif descendant:IsA("BasePart") then
			if not rig.headGroup[descendant] then
				-- A part the trail (or the wing flapping) places by code every frame is anchored so physics leaves it alone. Anything
				-- merely welded to such a part (the saddle on Body_01) must stay unanchored: two anchored welded parts do not
				-- carry each other, but an unanchored one rides its anchored partner.
				descendant.Anchored = rig.drivenParts[descendant] == true or FLAPPED_PART_NAMES[descendant.Name] == true
				local antigravity = descendant:FindFirstChild(Constants.ANTIGRAVITY_NAME)
				if antigravity then
					antigravity:Destroy()
				end
			end
		end
	end
end

-- The rider is welded to the part marked SEAT_LOCATION, and everything that looks for the seat takes the first marked part it finds.
-- Several models mark two parts (Saddle and Body_01, a fraction of a stud apart), so leave the mark on the one the rig chose.
-- That part trails with its body part like the rest of the body, and the rider moves with it.
local function keepOnlyChosenSeat(caster: Model, rig: Rig)
	local seatPart = rig.seatPart
	if not seatPart then
		return
	end

	for _, descendant in caster:GetDescendants() do
		if descendant ~= seatPart and descendant:IsA("BasePart") and descendant:GetAttribute(Attributes.SEAT_LOCATION) then
			descendant:SetAttribute(Attributes.SEAT_LOCATION, nil)
		end
	end
end

function ClientDragonBodyTrail.detach(self: ClientDragonBodyTrail, itemId: number)
	if not self.dragons[itemId] then
		return
	end

	self.dragons[itemId] = nil
	self.dragonCount -= 1

	if self.dragonCount <= 0 and self.renderConnect then
		self.renderConnect:Disconnect()
		self.renderConnect = nil
	end
end

-- Takes over the body of a freshly built, posed caster. Returns false (leaving the caster on the legacy physics) when the model is not
-- shaped like a chain this can drive.
function ClientDragonBodyTrail.tryAttach(self: ClientDragonBodyTrail, itemId: number, caster: Model, shadow: any): boolean
	self:detach(itemId)

	local rig, reason = buildRig(caster)
	if not rig then
		local casterName = caster.Name
		if not self.warnedNames[casterName] then
			self.warnedNames[casterName] = true
			warn("ClientDragonBodyTrail: keeping the legacy flight for", casterName, "because", reason)
		end
		return false
	end

	disablePhysicsBody(caster, rig)
	keepOnlyChosenSeat(caster, rig)

	local state: DragonState = {
		itemId = itemId,
		caster = caster,
		shadow = shadow,
		rig = rig,
		positions = {},
		cframes = {},
		renderOffsets = {},
		anchorBefore = {},
		bobTime = math.random() * 100,
		lastHeadPosition = rig.head.Position,
		smoothPosition = rig.head.Position,
		smoothVelocity = Vector3.zero,
		headSpeed = 0,
		needsReset = true,
		targetLift = 0,
		lift = 0,
	}
	self.dragons[itemId] = state
	self.dragonCount += 1

	if not self.renderConnect then
		self.renderConnect = runService.Heartbeat:Connect(function(dt: number)
			self:step(dt)
		end)
	end

	return true
end

function ClientDragonBodyTrail.new(): ClientDragonBodyTrail
	local self = setmetatable({} :: ClientDragonBodyTrailFields, ClientDragonBodyTrail)

	self.config = nil
	self.modeOverride = nil
	self.modeChangedEvent = Instance.new("BindableEvent")
	self.dragons = {}
	self.dragonCount = 0
	self.renderConnect = nil
	self.warnedNames = {}

	return self
end

local singleton = ClientDragonBodyTrail.new()

return singleton
