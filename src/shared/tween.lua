--!strict

local tween = {
  _VERSION     = 'tween 2.1.1',
  _DESCRIPTION = 'tweening for lua',
  _URL         = 'https://github.com/kikito/tween.lua',
  _LICENSE     = [[
    MIT LICENSE

    Copyright (c) 2014 Enrique García Cota, Yuichi Tateno, Emmanuel Oga

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ]]
}

-- easing

-- Adapted from https://github.com/EmmanuelOga/easing. See LICENSE.txt for credits.
-- For all easing functions:
-- t = time == how much time has to pass for the tweening to complete
-- b = begin == starting property value
-- c = change == ending - beginning
-- d = duration == running time. How much time has passed *right now*

-- the extra optional params are amplitude/period for the elastic family and overshoot for the back family
export type EasingFn = (t: number, b: number, c: number, d: number, a: number?, p: number?) -> number

local sin, cos, pi, sqrt, abs, asin = math.sin, math.cos, math.pi, math.sqrt, math.abs, math.asin
local function pow(x: number, y: number): number return x ^ y end

-- linear
local function linear(t: number, b: number, c: number, d: number): number return c * t / d + b end

-- quad
local function inQuad(t: number, b: number, c: number, d: number): number return c * pow(t / d, 2) + b end
local function outQuad(t: number, b: number, c: number, d: number): number
  t = t / d
  return -c * t * (t - 2) + b
end
local function inOutQuad(t: number, b: number, c: number, d: number): number
  t = t / d * 2
  if t < 1 then return c / 2 * pow(t, 2) + b end
  return -c / 2 * ((t - 1) * (t - 3) - 1) + b
end
local function outInQuad(t: number, b: number, c: number, d: number): number
  if t < d / 2 then return outQuad(t * 2, b, c / 2, d) end
  return inQuad((t * 2) - d, b + c / 2, c / 2, d)
end

-- cubic
local function inCubic (t: number, b: number, c: number, d: number): number return c * pow(t / d, 3) + b end
local function outCubic(t: number, b: number, c: number, d: number): number return c * (pow(t / d - 1, 3) + 1) + b end
local function inOutCubic(t: number, b: number, c: number, d: number): number
  t = t / d * 2
  if t < 1 then return c / 2 * t * t * t + b end
  t = t - 2
  return c / 2 * (t * t * t + 2) + b
end
local function outInCubic(t: number, b: number, c: number, d: number): number
  if t < d / 2 then return outCubic(t * 2, b, c / 2, d) end
  return inCubic((t * 2) - d, b + c / 2, c / 2, d)
end

-- quart
local function inQuart(t: number, b: number, c: number, d: number): number return c * pow(t / d, 4) + b end
local function outQuart(t: number, b: number, c: number, d: number): number return -c * (pow(t / d - 1, 4) - 1) + b end
local function inOutQuart(t: number, b: number, c: number, d: number): number
  t = t / d * 2
  if t < 1 then return c / 2 * pow(t, 4) + b end
  return -c / 2 * (pow(t - 2, 4) - 2) + b
end
local function outInQuart(t: number, b: number, c: number, d: number): number
  if t < d / 2 then return outQuart(t * 2, b, c / 2, d) end
  return inQuart((t * 2) - d, b + c / 2, c / 2, d)
end

-- quint
local function inQuint(t: number, b: number, c: number, d: number): number return c * pow(t / d, 5) + b end
local function outQuint(t: number, b: number, c: number, d: number): number return c * (pow(t / d - 1, 5) + 1) + b end
local function inOutQuint(t: number, b: number, c: number, d: number): number
  t = t / d * 2
  if t < 1 then return c / 2 * pow(t, 5) + b end
  return c / 2 * (pow(t - 2, 5) + 2) + b
end
local function outInQuint(t: number, b: number, c: number, d: number): number
  if t < d / 2 then return outQuint(t * 2, b, c / 2, d) end
  return inQuint((t * 2) - d, b + c / 2, c / 2, d)
end

-- sine
local function inSine(t: number, b: number, c: number, d: number): number return -c * cos(t / d * (pi / 2)) + c + b end
local function outSine(t: number, b: number, c: number, d: number): number return c * sin(t / d * (pi / 2)) + b end
local function inOutSine(t: number, b: number, c: number, d: number): number return -c / 2 * (cos(pi * t / d) - 1) + b end
local function outInSine(t: number, b: number, c: number, d: number): number
  if t < d / 2 then return outSine(t * 2, b, c / 2, d) end
  return inSine((t * 2) -d, b + c / 2, c / 2, d)
end

-- expo
local function inExpo(t: number, b: number, c: number, d: number): number
  if t == 0 then return b end
  return c * pow(2, 10 * (t / d - 1)) + b - c * 0.001
end
local function outExpo(t: number, b: number, c: number, d: number): number
  if t == d then return b + c end
  return c * 1.001 * (-pow(2, -10 * t / d) + 1) + b
end
local function inOutExpo(t: number, b: number, c: number, d: number): number
  if t == 0 then return b end
  if t == d then return b + c end
  t = t / d * 2
  if t < 1 then return c / 2 * pow(2, 10 * (t - 1)) + b - c * 0.0005 end
  return c / 2 * 1.0005 * (-pow(2, -10 * (t - 1)) + 2) + b
end
local function outInExpo(t: number, b: number, c: number, d: number): number
  if t < d / 2 then return outExpo(t * 2, b, c / 2, d) end
  return inExpo((t * 2) - d, b + c / 2, c / 2, d)
end

-- circ
local function inCirc(t: number, b: number, c: number, d: number): number return(-c * (sqrt(1 - pow(t / d, 2)) - 1) + b) end
local function outCirc(t: number, b: number, c: number, d: number): number  return(c * sqrt(1 - pow(t / d - 1, 2)) + b) end
local function inOutCirc(t: number, b: number, c: number, d: number): number
  t = t / d * 2
  if t < 1 then return -c / 2 * (sqrt(1 - t * t) - 1) + b end
  t = t - 2
  return c / 2 * (sqrt(1 - t * t) + 1) + b
end
local function outInCirc(t: number, b: number, c: number, d: number): number
  if t < d / 2 then return outCirc(t * 2, b, c / 2, d) end
  return inCirc((t * 2) - d, b + c / 2, c / 2, d)
end

-- elastic
local function calculatePAS(p: number?, a: number?, c: number, d: number): (number, number, number)
  local pp = p or d * 0.3
  local aa = a or 0
  if aa < abs(c) then return pp, c, pp / 4 end -- p, a, s
  return pp, aa, pp / (2 * pi) * asin(c / aa) -- p,a,s
end
local function inElastic(t: number, b: number, c: number, d: number, a: number?, p: number?): number
  if t == 0 then return b end
  t = t / d
  if t == 1  then return b + c end
  local pp, aa, s = calculatePAS(p, a, c, d)
  t = t - 1
  return -(aa * pow(2, 10 * t) * sin((t * d - s) * (2 * pi) / pp)) + b
end
local function outElastic(t: number, b: number, c: number, d: number, a: number?, p: number?): number
  if t == 0 then return b end
  t = t / d
  if t == 1 then return b + c end
  local pp, aa, s = calculatePAS(p, a, c, d)
  return aa * pow(2, -10 * t) * sin((t * d - s) * (2 * pi) / pp) + c + b
end
local function inOutElastic(t: number, b: number, c: number, d: number, a: number?, p: number?): number
  if t == 0 then return b end
  t = t / d * 2
  if t == 2 then return b + c end
  local pp, aa, s = calculatePAS(p, a, c, d)
  t = t - 1
  if t < 0 then return -0.5 * (aa * pow(2, 10 * t) * sin((t * d - s) * (2 * pi) / pp)) + b end
  return aa * pow(2, -10 * t) * sin((t * d - s) * (2 * pi) / pp ) * 0.5 + c + b
end
local function outInElastic(t: number, b: number, c: number, d: number, a: number?, p: number?): number
  if t < d / 2 then return outElastic(t * 2, b, c / 2, d, a, p) end
  return inElastic((t * 2) - d, b + c / 2, c / 2, d, a, p)
end

-- back
local function inBack(t: number, b: number, c: number, d: number, s: number?): number
  local ss = s or 1.70158
  t = t / d
  return c * t * t * ((ss + 1) * t - ss) + b
end
local function outBack(t: number, b: number, c: number, d: number, s: number?): number
  local ss = s or 1.70158
  t = t / d - 1
  return c * (t * t * ((ss + 1) * t + ss) + 1) + b
end
local function inOutBack(t: number, b: number, c: number, d: number, s: number?): number
  local ss = (s or 1.70158) * 1.525
  t = t / d * 2
  if t < 1 then return c / 2 * (t * t * ((ss + 1) * t - ss)) + b end
  t = t - 2
  return c / 2 * (t * t * ((ss + 1) * t + ss) + 2) + b
end
local function outInBack(t: number, b: number, c: number, d: number, s: number?): number
  if t < d / 2 then return outBack(t * 2, b, c / 2, d, s) end
  return inBack((t * 2) - d, b + c / 2, c / 2, d, s)
end

-- bounce
local function outBounce(t: number, b: number, c: number, d: number): number
  t = t / d
  if t < 1 / 2.75 then return c * (7.5625 * t * t) + b end
  if t < 2 / 2.75 then
    t = t - (1.5 / 2.75)
    return c * (7.5625 * t * t + 0.75) + b
  elseif t < 2.5 / 2.75 then
    t = t - (2.25 / 2.75)
    return c * (7.5625 * t * t + 0.9375) + b
  end
  t = t - (2.625 / 2.75)
  return c * (7.5625 * t * t + 0.984375) + b
end
local function inBounce(t: number, b: number, c: number, d: number): number return c - outBounce(d - t, 0, c, d) + b end
local function inOutBounce(t: number, b: number, c: number, d: number): number
  if t < d / 2 then return inBounce(t * 2, 0, c, d) * 0.5 + b end
  return outBounce(t * 2 - d, 0, c, d) * 0.5 + c * .5 + b
end
local function outInBounce(t: number, b: number, c: number, d: number): number
  if t < d / 2 then return outBounce(t * 2, b, c / 2, d) end
  return inBounce((t * 2) - d, b + c / 2, c / 2, d)
end

tween.easing = {
  linear    = linear,
  inQuad    = inQuad,    outQuad    = outQuad,    inOutQuad    = inOutQuad,    outInQuad    = outInQuad,
  inCubic   = inCubic,   outCubic   = outCubic,   inOutCubic   = inOutCubic,   outInCubic   = outInCubic,
  inQuart   = inQuart,   outQuart   = outQuart,   inOutQuart   = inOutQuart,   outInQuart   = outInQuart,
  inQuint   = inQuint,   outQuint   = outQuint,   inOutQuint   = inOutQuint,   outInQuint   = outInQuint,
  inSine    = inSine,    outSine    = outSine,    inOutSine    = inOutSine,    outInSine    = outInSine,
  inExpo    = inExpo,    outExpo    = outExpo,    inOutExpo    = inOutExpo,    outInExpo    = outInExpo,
  inCirc    = inCirc,    outCirc    = outCirc,    inOutCirc    = inOutCirc,    outInCirc    = outInCirc,
  inElastic = inElastic, outElastic = outElastic, inOutElastic = inOutElastic, outInElastic = outInElastic,
  inBack    = inBack,    outBack    = outBack,    inOutBack    = inOutBack,    outInBack    = outInBack,
  inBounce  = inBounce,  outBounce  = outBounce,  inOutBounce  = inOutBounce,  outInBounce  = outInBounce
} :: { [string]: EasingFn }



-- private stuff

-- subject/target/initial are recursive trees of numbers ("table or userdata"), walked dynamically,
-- so they stay `any` throughout
local function copyTables(destination: any, keysTable: any, valuesTable: any?): any
  local values = valuesTable or keysTable
  local mt = getmetatable(keysTable)
  if mt and getmetatable(destination) == nil then
    -- the cast keeps the new type solver from re-binding destination to setmetatable's result type
    setmetatable(destination :: any, mt)
  end
  for k,v in pairs(keysTable) do
    if type(v) == 'table' then
      destination[k] = copyTables({}, v, values[k])
    else
      destination[k] = values[k]
    end
  end
  return destination
end

local function checkSubjectAndTargetRecursively(subject: any, target: any, path: { string }?)
  local currentPath: { string } = path or {}
  for k,targetValue in pairs(target) do
    local targetType, newPath = type(targetValue), copyTables({}, currentPath)
    table.insert(newPath, tostring(k))
    if targetType == 'number' then
      assert(type(subject[k]) == 'number', "Parameter '" .. table.concat(newPath,'/') .. "' is missing from subject or isn't a number")
    elseif targetType == 'table' then
      checkSubjectAndTargetRecursively(subject[k], targetValue, newPath)
    else
      -- the cast lets both type solvers accept this always-failing assert (targetType is known to
      -- be neither 'number' nor 'table' here)
      assert((targetType :: string) == 'number', "Parameter '" .. table.concat(newPath,'/') .. "' must be a number or table of numbers")
    end
  end
end

local function checkNewParams(duration: number, subject: any, target: any, easing: EasingFn)
  assert(type(duration) == 'number' and duration > 0, "duration must be a positive number. Was " .. tostring(duration))
  local tsubject = type(subject)
  assert(tsubject == 'table' or tsubject == 'userdata', "subject must be a table or userdata. Was " .. tostring(subject))
  assert(type(target)== 'table', "target must be a table. Was " .. tostring(target))
  assert(type(easing)=='function', "easing must be a function. Was " .. tostring(easing))
  checkSubjectAndTargetRecursively(subject, target)
end

local function getEasingFunction(easing: (string | EasingFn)?): EasingFn
  local chosen: string | EasingFn = easing or "linear"
  if type(chosen) == 'string' then
    local fn = tween.easing[chosen]
    if type(fn) ~= 'function' then
      error("The easing function name '" .. chosen .. "' is invalid")
    end
    return fn
  end
  return chosen
end

local function performEasingOnSubject(subject: any, target: any, initial: any, clock: number, duration: number, easing: EasingFn)
  for k,v in pairs(target) do
    if type(v) == 'table' then
      performEasingOnSubject(subject[k], v, initial[k], clock, duration, easing)
    else
      local t,b,c,d = clock, initial[k], v - initial[k], duration
      subject[k] = easing(t,b,c,d)
    end
  end
end

-- Tween methods

export type Tween = {
  duration: number,
  subject: any,
  target: any,
  easing: EasingFn,
  clock: number,
  initial: any?,
  set: (self: Tween, clock: number) -> boolean,
  reset: (self: Tween) -> boolean,
  update: (self: Tween, dt: number) -> boolean,
}

local Tween = {}
local Tween_mt = {__index = Tween}

function Tween.set(self: Tween, clock: number): boolean
  assert(type(clock) == 'number', "clock must be a positive number or 0")

  self.initial = self.initial or copyTables({}, self.target, self.subject)
  self.clock = clock

  if self.clock <= 0 then

    self.clock = 0
    copyTables(self.subject, self.initial)

  elseif self.clock >= self.duration then -- the tween has expired

    self.clock = self.duration
    copyTables(self.subject, self.target)

  else

    performEasingOnSubject(self.subject, self.target, self.initial, self.clock, self.duration, self.easing)

  end

  return self.clock >= self.duration
end

function Tween.reset(self: Tween): boolean
  return self:set(0)
end

function Tween.update(self: Tween, dt: number): boolean
  assert(type(dt) == 'number', "dt must be a number")
  return self:set(self.clock + dt)
end


-- Public interface

function tween.new(duration: number, subject: any, target: any, easing: (string | EasingFn)?): Tween
  local easingFn = getEasingFunction(easing)
  checkNewParams(duration, subject, target, easingFn)
  return (setmetatable({
    duration  = duration,
    subject   = subject,
    target    = target,
    easing    = easingFn,
    clock     = 0
  }, Tween_mt) :: any) :: Tween
end

return tween
