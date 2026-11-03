--!strict

-- Pure math for the procedural dragon body trail (no Instances). Adapted from the Dragon Riders package
-- (DragonFlightPhysics.getChainPosition / getBobScale, studied 2026-november-2), generalised so a link can sit in any rest
-- direction behind the link in front of it and each link has its own distance.
local DragonTrailMath = {}

-- the idle bob runs faster the faster the head moves, between these scales (package values)
local BOB_SCALE_MIN = 1
local BOB_SCALE_MAX = 4
local BOB_SPEED_TO_SCALE = 0.25

local PARALLEL_DOT = 0.999

-- Where a link goes this frame: `distance` studs from `prevPosition`, toward where the link was last frame (so it follows the
-- path of the link in front), but never bent more than `limitDeg` away from `restDirection` (the unit world direction the link
-- sits in when the dragon is straight). Returns the new position, before the bob.
function DragonTrailMath.getLinkPosition(
	prevPosition: Vector3,
	restDirection: Vector3,
	oldPosition: Vector3,
	distance: number,
	limitDeg: number
): Vector3
	local offset = oldPosition - prevPosition
	local delta = if offset.Magnitude > 1e-4 then offset.Unit else restDirection

	local cosAngle = delta:Dot(restDirection)
	local limitRad = math.rad(limitDeg)
	local maxCos = math.cos(limitRad)
	if cosAngle < maxCos then
		local rejection = delta - cosAngle * restDirection
		if rejection.Magnitude > 1e-4 then
			delta = maxCos * restDirection + math.sin(limitRad) * rejection.Unit
		else
			-- exactly opposite the rest direction: any sideways direction is as good, so stay straight
			delta = restDirection
		end
	end

	return prevPosition + delta * distance
end

-- How far a link eases toward straight this frame (0 to 1): an exponential approach, so it does not depend on the frame rate. Follow-the-
-- leader alone never straightens a body whose head has stopped, since a link only moves when the link in front of it does.
function DragonTrailMath.getStraightenFactor(ratePerSec: number, dt: number): number
	if ratePerSec <= 0 or dt <= 0 then
		return 0
	end

	return 1 - math.exp(-ratePerSec * dt)
end

-- Smooths a position that arrives unevenly (a physics body read once per frame: some frames it has moved a little more than others, because
-- of when the physics step fell). A critically damped tracker with a velocity estimate, so a steady fly-by has no lag at all and only the
-- frame-to-frame unevenness is removed. Returns the new estimate and velocity. `timeConstantSec` 0 passes the measurement straight through.
function DragonTrailMath.smoothPoint(
	estimate: Vector3,
	velocity: Vector3,
	measured: Vector3,
	dt: number,
	timeConstantSec: number
): (Vector3, Vector3)
	if dt <= 0 then
		return estimate, velocity
	end
	if timeConstantSec <= 0 then
		return measured, (measured - estimate) / dt
	end

	local alpha = 1 - math.exp(-dt / timeConstantSec)
	local beta = alpha * alpha / (2 - alpha)
	local predicted = estimate + velocity * dt
	local residual = measured - predicted

	return predicted + residual * alpha, velocity + residual * (beta / dt)
end

-- A CFrame at `position` facing `target`, with `up` as the roll reference. Falls back to a sideways reference when the facing is
-- (almost) parallel to `up`, where CFrame.lookAt would be unstable.
function DragonTrailMath.getLookCFrame(position: Vector3, target: Vector3, up: Vector3): CFrame
	local toTarget = target - position
	if toTarget.Magnitude < 1e-4 then
		return CFrame.new(position)
	end

	local direction = toTarget.Unit
	local reference = up
	if math.abs(direction:Dot(up)) > PARALLEL_DOT then
		reference = if math.abs(direction.Y) < PARALLEL_DOT then Vector3.yAxis else Vector3.xAxis
	end

	return CFrame.lookAt(position, target, reference)
end

-- How fast the bob clock runs: 1 while ridden, otherwise it follows the head's speed (studs per second).
function DragonTrailMath.getBobScale(isRidden: boolean, headSpeed: number): number
	if isRidden then
		return 1
	end

	return math.clamp(headSpeed * BOB_SPEED_TO_SCALE, BOB_SCALE_MIN, BOB_SCALE_MAX)
end

-- How much the dragon counts as moving, 0 to 1: none at or under `minSpeed`, full from `fullSpeed` up, a straight ramp between. A ridden
-- dragon bobs only as much as it moves (a rider sits on the body, so a body that bobs in place would move the rider for no reason), and a
-- body straightens strongly when the dragon is slow and gently while it flies.
function DragonTrailMath.getMotionFactor(headSpeed: number, minSpeed: number, fullSpeed: number): number
	if fullSpeed <= minSpeed then
		return if headSpeed > minSpeed then 1 else 0
	end

	return math.clamp((headSpeed - minSpeed) / (fullSpeed - minSpeed), 0, 1)
end

-- How much of a body-wide effect reaches spine link `spineIndex` (the first trailing link is 1) of `spineCount`: nothing at the first link,
-- where the rider's seat is, growing in a straight line to the full effect at the tail tip. A chain with one link takes it in full.
function DragonTrailMath.getTailWeight(spineIndex: number, spineCount: number): number
	if spineCount <= 1 then
		return 1
	end

	return math.clamp((spineIndex - 1) / (spineCount - 1), 0, 1)
end

-- Vertical sway of link number `linkIndex` (the first trailing link is 1), in studs.
function DragonTrailMath.getBobOffset(bobTime: number, linkIndex: number, phaseStep: number, amplitude: number, bobScale: number): number
	return math.sin(bobTime + linkIndex * phaseStep) * amplitude * bobScale
end

return DragonTrailMath
