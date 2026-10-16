-- Offline check of the estimators: movement paths -> brackets -> estimates.
-- Run from the repo root: luajit tools/sim.lua
local Estimator = dofile("Estimator.lua")

local RANGES = { 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 25, 30, 35, 38, 40, 45, 50, 55, 60 }
local TICK = 0.05
local REACH = 2.0   -- true combined reach; the estimator assumes 1.5

local function bracket(d)
  local lo, hi = 0, nil
  for _, r in ipairs(RANGES) do
    if d <= r then hi = r; break end
    lo = r
  end
  return lo, hi
end

-- Each scenario: duration and step(t) -> player x, y, target x, y (target speed derived).
-- The target stands at the origin unless the scenario moves it.
local function legs(list)
  -- list of { duration, vx, vy } for the player starting at list.start
  return function(t)
    local x, y = list.start[1], list.start[2]
    local left = t
    for _, l in ipairs(list) do
      local d = math.min(left, l[1])
      x, y = x + l[2] * d, y + l[3] * d
      left = left - d
      if left <= 0 then break end
    end
    return x, y, 0, 0
  end
end

local scenarios = {
  { "run in to melee, stop, walk straight out", 14,
    legs { start = { 0, 40 }, { 5.6, 0, -7 }, { 2, 0, 0 }, { 6, 0, 7 } } },
  { "run in to melee, stop, walk out sideways", 14,
    legs { start = { 0, 40 }, { 5.6, 0, -7 }, { 2, 0, 0 }, { 6, 7, 0 } } },
  { "stop at 20, turn around, leave", 10,
    legs { start = { 0, 40 }, { 2.6, 0, -7 }, { 2, 0, 0 }, { 5, 0, 7 } } },
  { "circle strafe at 12", 12, function(t)
      local a = t * 7 / 13.5
      return 13.5 * math.cos(a), 13.5 * math.sin(a), 0, 0 end },
  { "kite back and forth 18..33", 12, function(t)
      local p = (t * 7) % 30
      return 0, 2 + ((p < 15) and (33 - p) or (18 + p - 15)), 0, 0 end },
  { "mob charges you (you stand)", 5.5, function(t) return 0, 0, 0, 42 - 7 * t end },
  { "mob charges to melee, then steps around you", 12, function(t)
      local arrive = (42 - 3.5) / 7
      if t < arrive then return 0, 0, 0, 42 - 7 * t end
      -- after a second, a 0.3 s step at run speed every 1.5 s: around you, not away
      local k = math.max(0, t - arrive - 1)
      local n = math.floor(k / 1.5)
      local a = (n * 0.3 + math.min(k - n * 1.5, 0.3)) * 7 / 3.5
      return 0, 0, 3.5 * math.sin(a), 3.5 * math.cos(a) end },
}

local function run(path, dur, withPos)
  local e = Estimator.new()
  local s, sa, n, worst = 0, 0, 0, 0
  local t = 0
  local opx, opy, otx, oty = path(0)
  while t <= dur do
    local px, py, tx, ty = path(t)
    local ps = math.sqrt((px - opx) ^ 2 + (py - opy) ^ 2) / TICK
    local sp = ps + math.sqrt((tx - otx) ^ 2 + (ty - oty) ^ 2) / TICK
    local still = math.abs(tx - otx) + math.abs(ty - oty) < 1e-9
    opx, opy, otx, oty = px, py, tx, ty
    local d = math.max(0, math.sqrt((px - tx) ^ 2 + (py - ty) ^ 2) - REACH)
    local lo, hi = bracket(d)
    if withPos then e:update(t, TICK, lo, hi, sp, px, py, still, ps)
    else e:update(t, TICK, lo, hi, sp, nil, nil, nil, ps) end
    if hi and t > 0.5 then
      local b = e:valueB(lo, hi)
      local a = e:valueA(t, lo, hi)
      s, sa, n = s + math.abs(b - d), sa + math.abs(a - d), n + 1
      worst = math.max(worst, math.abs(b - d))
    end
    t = t + TICK
  end
  return sa / n, s / n, worst
end

print(("%-42s %8s %16s %18s"):format("", "A", "B no position", "B with position"))
for _, sc in ipairs(scenarios) do
  local a, b1, w1 = run(sc[3], sc[2], false)
  local _, b2, w2 = run(sc[3], sc[2], true)
  print(("%-42s %8.2f %9.2f (max %.1f) %9.2f (max %.1f)"):format(sc[1], a, b1, w1, b2, w2))
end
