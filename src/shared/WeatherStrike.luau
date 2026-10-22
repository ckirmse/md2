--!strict

-- Constants shared by the server and client halves of a weather strike (Thunderstorm, Starlight): the server stamps the
-- struck object and grants the trait TRAIT_DELAY_SEC later, which lines up with the moment the cinematic hits.
local Enums = require("./Enums")

local WeatherStrike = {}

WeatherStrike.TRAIT_DELAY_SEC = {
	[Enums.Weather.THUNDERSTORM] = 3,
	[Enums.Weather.STARLIGHT] = 4,
} :: { [number]: number }

-- the stamp is removed after this long; it must outlast the longest cinematic
WeatherStrike.CLEAR_SEC = 15

-- a client ignores a stamp older than this, so a late join or stream-in never replays a strike
WeatherStrike.REPLAY_WINDOW_SEC = 2

return WeatherStrike
