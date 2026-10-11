-- Offline check of the estimators: true distance paths -> brackets -> estimates.
-- Run: luajit tools/sim.lua  (from the repo root)
package.path = "./?.lua;" .. package.path
local Estimator = dofile("Estimator.lua")

local RANGES = { 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 25, 30, 35, 38, 40, 45, 50, 55, 60 }
local TICK = 0.05

local function bracket(d)
  local lo, hi = 0, nil
  for _, r in ipairs(RANGES) do
    if d <= r then hi = r; break end
    lo = r
  end
  return lo, hi
end

-- path(t) -> distance, combined speed reported by the game
local scenarios = {
  { "run straight in 45->5 @7", 6, function(t) return 45 - 7 * t, 7 end },
  { "run in, stop 2 s at ~24, run on", 8, function(t)
      if t < 3 then return 45 - 7 * t, 7 elseif t < 5 then return 24, 0 else return 24 - 7 * (t - 5), 7 end end },
  { "mob charges you @7 (you stand)", 5.5, function(t) return 40 - 7 * t, 7 end },
  { "strafe: speed 7, closing 3.5", 10, function(t) return 42 - 3.5 * t, 7 end },
  { "kite: back and forth 18..33 @7", 12, function(t)
      local p = (t * 7) % 30; return (p < 15) and (33 - p) or (18 + p - 15), 7 end },
  { "mount 14 then dismount 7", 6, function(t)
      if t < 2 then return 55 - 14 * t, 14 else return 27 - 7 * (t - 2), 7 end end },
}

for _, sc in ipairs(scenarios) do
  local name, dur, path = sc[1], sc[2], sc[3]
  local e = Estimator.new()
  local sm, sa, sb, n = 0, 0, 0, 0
  local mm, ma, mb = 0, 0, 0
  local t = 0
  while t <= dur do
    local d, sp = path(t)
    local lo, hi = bracket(d)
    e:update(t, TICK, lo, hi, sp)
    if hi then
      local m = (lo + hi) / 2
      local a, b = e:valueA(t, lo, hi), e:valueB(lo, hi)
      local em, ea, eb = math.abs(m - d), math.abs(a - d), math.abs(b - d)
      sm, sa, sb, n = sm + em, sa + ea, sb + eb, n + 1
      mm, ma, mb = math.max(mm, em), math.max(ma, ea), math.max(mb, eb)
    end
    t = t + TICK
  end
  print(("%-34s mid %.2f (max %.1f)   A %.2f (max %.1f)   B %.2f (max %.1f)"):format(
    name, sm / n, mm, sa / n, ma, sb / n, mb))
end
