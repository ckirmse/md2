--!strict

-- Settings for the dragon flight mode switch (Studio-only GameData.Control.DragonFlight). Pure validation and defaults, so the
-- server and the client read the same shape. A bad or missing config never stops boot: it falls back to the legacy flight.
local DragonFlightSettings = {}

export type TrailSettings = {
	jointLimitDeg: number, -- most a trailing link may bend away from straight behind the link in front of it
	firstLinkJointLimitDeg: number, -- the same for the link right behind the head, where the rider's seat is, so it stays tight
	straightenRate: number, -- per second, how fast a bent body eases back to straight while the dragon flies (0 = never)
	straightenRateAtRest: number, -- the same once the dragon has slowed to a stop; the tail finishes last. Blended by speed (bobMinSpeed to bobFullSpeed)
	bobAmplitude: number, -- studs of idle sway per link at scale 1
	hoverTailBobAmplitude: number, -- studs the tail tip sways while a rider hovers; fades to nothing at the seat and when the dragon moves
	headSmoothingSec: number, -- time constant of the smoothing of the head position the body is built from (0 = off); removes frame-to-frame jitter
	bobMinSpeed: number, -- a ridden dragon at or under this speed (studs/s) does not bob at all
	bobFullSpeed: number, -- ... and bobs fully from this speed up
	bobTimeRate: number, -- bob clock speed
	bobPhaseStep: number, -- phase added per link so the body ripples
	snapDistance: number, -- a head move bigger than this in one frame resets the body (teleport)
	maxActiveDistance: number, -- farther than this from the camera the body is rigid
}

export type DragonFlightConfig = {
	useLegacyFlight: boolean,
	trail: TrailSettings,
}

-- numbers marked "port" came from the Dragon Riders package (DragonFlightConfig.BOB_*), the rest are md2 starting values to tune
DragonFlightSettings.DEFAULT_TRAIL = {
	jointLimitDeg = 35,
	firstLinkJointLimitDeg = 15, -- port (the package uses 15 for Head to Body1 and 55 for the rest)
	straightenRate = 0.5, -- the package has no equivalent: its body froze bent when the head stopped
	straightenRateAtRest = 4,
	bobAmplitude = 0.015, -- port. Tune by eye: the chain feeds the bob back on itself, so the drawn sway is many times this number
	hoverTailBobAmplitude = 0.35,
	headSmoothingSec = 0.08,
	bobMinSpeed = 2,
	bobFullSpeed = 10,
	bobTimeRate = 2, -- port
	bobPhaseStep = 0.75, -- port
	snapDistance = 40,
	maxActiveDistance = 250,
} :: TrailSettings

local MAX_JOINT_LIMIT_DEG = 85

local TRAIL_RULES: { { key: string, min: number, max: number } } = {
	{ key = "jointLimitDeg", min = 1, max = MAX_JOINT_LIMIT_DEG },
	{ key = "firstLinkJointLimitDeg", min = 1, max = MAX_JOINT_LIMIT_DEG },
	{ key = "straightenRate", min = 0, max = 20 },
	{ key = "straightenRateAtRest", min = 0, max = 20 },
	{ key = "bobAmplitude", min = 0, max = 5 },
	{ key = "hoverTailBobAmplitude", min = 0, max = 5 },
	{ key = "headSmoothingSec", min = 0, max = 0.5 },
	{ key = "bobMinSpeed", min = 0, max = 500 },
	{ key = "bobFullSpeed", min = 0, max = 500 },
	{ key = "bobTimeRate", min = 0, max = 20 },
	{ key = "bobPhaseStep", min = 0, max = 6.3 },
	{ key = "snapDistance", min = 1, max = 1000 },
	{ key = "maxActiveDistance", min = 1, max = 5000 },
}

-- Returns nil when the table is usable, otherwise a message naming the first problem.
function DragonFlightSettings.validate(config: any): string?
	if type(config) ~= "table" then
		return "the config is not a table"
	end

	if type(config.useLegacyFlight) ~= "boolean" then
		return "useLegacyFlight must be a boolean"
	end

	local trail = config.trail
	if trail == nil then
		return nil -- every trail value then uses its default
	end
	if type(trail) ~= "table" then
		return "trail must be a table"
	end

	for _, rule in TRAIL_RULES do
		local value = trail[rule.key]
		if value ~= nil then
			if type(value) ~= "number" or value ~= value or value < rule.min or value > rule.max then
				return string.format("trail.%s must be a number from %s to %s", rule.key, tostring(rule.min), tostring(rule.max))
			end
		end
	end

	local minSpeed = trail.bobMinSpeed or DragonFlightSettings.DEFAULT_TRAIL.bobMinSpeed
	local fullSpeed = trail.bobFullSpeed or DragonFlightSettings.DEFAULT_TRAIL.bobFullSpeed
	if fullSpeed <= minSpeed then
		return "trail.bobFullSpeed must be greater than trail.bobMinSpeed"
	end

	return nil
end

-- Always returns a complete, valid config. Anything missing takes its default; an invalid table is the legacy flight.
function DragonFlightSettings.normalize(config: any): DragonFlightConfig
	local trail: TrailSettings = table.clone(DragonFlightSettings.DEFAULT_TRAIL)

	if DragonFlightSettings.validate(config) then
		return { useLegacyFlight = true, trail = trail }
	end

	local configTrail = config.trail
	if configTrail then
		for _, rule in TRAIL_RULES do
			local value = configTrail[rule.key]
			if value ~= nil then
				(trail :: any)[rule.key] = value
			end
		end
	end

	return { useLegacyFlight = config.useLegacyFlight, trail = trail }
end

return DragonFlightSettings
