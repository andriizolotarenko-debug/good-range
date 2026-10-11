-- PURE: turns a stream of range brackets [lo, hi] into distance estimates.
--   mid  the middle of the bracket (what bracket-only addons show)
--   A    trend: the closing rate from the last two boundary crossings, extrapolated
--   B    A plus live speeds (both stopped = freeze, faster = faster) and a slowdown
--        when a crossing the trend expects does not come
-- Every crossing is an exact distance, so the error of each estimate is measured there.
local _, ns = ...
ns = ns or {}

local Estimator = {}
Estimator.__index = Estimator

Estimator.WINDOW = 15     -- s; an older crossing is too stale to give a rate
Estimator.DECAY = 2       -- 1/s; how fast B's rate fades while pressed against a bound
Estimator.MAX_SCALE = 3   -- B never scales its rate by more than this

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if hi and v > hi then return hi end
  return v
end

local function mid(lo, hi)
  return hi and (lo + hi) / 2 or nil
end

function Estimator.new()
  return setmetatable({ stats = { n = 0, a = 0, b = 0, mid = 0, amax = 0, bmax = 0, midn = 0 } }, Estimator)
end

function Estimator:reset()
  local stats = self.stats
  for k in pairs(self) do self[k] = nil end
  self.stats = stats
end

function Estimator:resetStats()
  self.stats = { n = 0, a = 0, b = 0, mid = 0, amax = 0, bmax = 0, midn = 0 }
end

-- A's value for the bracket [lo, hi] at time now.
function Estimator:valueA(now, lo, hi)
  if not self.anchor then return mid(lo, hi) end
  return clamp(self.anchor + self.aRate * (now - self.anchorT), lo, hi)
end

function Estimator:valueB(lo, hi)
  if not self.b then return mid(lo, hi) end
  return self.b
end

-- One tick. lo: largest range known to be out (0 if none), hi: smallest range known to be in
-- (nil if none). sp: combined speed of player and target in yd/s. Returns a crossing record
-- { at, dir, a, b, mid } when a boundary was crossed this tick, else nil.
function Estimator:update(now, dt, lo, hi, sp)
  sp = sp or 0
  if self.b then
    local rate = 0
    if sp > 0.05 then
      rate = self.bRate
      if self.refSpeed and self.refSpeed > 0.5 then
        rate = rate * math.min(sp / self.refSpeed, Estimator.MAX_SCALE)
      end
    end
    self.b = self.b + rate * dt
  end
  self.spSum = (self.spSum or 0) + sp * dt
  self.spT = (self.spT or 0) + dt

  local crossing
  local oldLo, oldHi = self.lo, self.hi
  local at, dir
  if oldLo then
    if hi and oldLo > 0 and hi <= oldLo then
      at, dir = hi, -1
    elseif oldHi and lo >= oldHi then
      at, dir = lo, 1
    end
  end

  if at then
    crossing = { at = at, dir = dir, mid = mid(oldLo, oldHi) }
    if self.anchor then
      crossing.a = self:valueA(now, oldLo, oldHi)
      crossing.b = clamp(self.b, oldLo, oldHi)
      self:record(crossing)
    elseif crossing.mid then
      self.stats.mid = self.stats.mid + math.abs(crossing.mid - at)
      self.stats.midn = self.stats.midn + 1
    end

    local last = self.last
    local fresh = last and now - last.t < Estimator.WINDOW and now > last.t
    -- A: plain trend between the last two crossings (0 when the same boundary is crossed back).
    self.aRate = fresh and (at - last.at) / (now - last.t) or 0
    self.anchor, self.anchorT = at, now
    -- B: the measured rate when it agrees with this crossing's direction, otherwise assume
    -- we are moving straight along the line at the current combined speed.
    local measured = fresh and (at - last.at) / (now - last.t)
    if measured and measured * dir > 0 then
      self.bRate = measured
      self.refSpeed = self.spT > 0 and self.spSum / self.spT or sp
    else
      self.bRate = dir * math.max(sp, 1)
      self.refSpeed = math.max(sp, 1)
    end
    self.b = at
    self.spSum, self.spT = 0, 0
    self.last = { t = now, at = at }
  end

  if self.b then
    if self.b < lo then
      self.b = lo
      if self.bRate < 0 then self.bRate = self.bRate * math.max(0, 1 - Estimator.DECAY * dt) end
    elseif hi and self.b > hi then
      self.b = hi
      if self.bRate > 0 then self.bRate = self.bRate * math.max(0, 1 - Estimator.DECAY * dt) end
    end
  end

  self.lo, self.hi = lo, hi
  return crossing
end

function Estimator:record(c)
  local s = self.stats
  local ea, eb = math.abs(c.a - c.at), math.abs(c.b - c.at)
  s.n = s.n + 1
  s.a, s.b = s.a + ea, s.b + eb
  if ea > s.amax then s.amax = ea end
  if eb > s.bmax then s.bmax = eb end
  if c.mid then
    s.mid = s.mid + math.abs(c.mid - c.at)
    s.midn = s.midn + 1
  end
  c.errA, c.errB = ea, eb
end

ns.Estimator = Estimator
return Estimator
