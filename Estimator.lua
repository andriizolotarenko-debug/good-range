-- PURE: turns a stream of range brackets [lo, hi] into distance estimates.
--   mid  the middle of the bracket (what bracket-only addons show)
--   A    trend: the closing rate from the last two boundary crossings, extrapolated
--   B    where the game gives the player's position and the target stands still: the target's
--        spot, fixed at a crossing, and the distance to it. Otherwise A plus live speeds
--        (both stopped = freeze), a slowdown when an expected crossing does not come, and a
--        restart into the bracket when you start moving with the estimate pressed on its edge
-- Every crossing is an exact distance, so the error of each estimate is measured there.
local _, ns = ...
ns = ns or {}

local Estimator = {}
Estimator.__index = Estimator

Estimator.WINDOW = 15     -- s; an older crossing is too stale to give a rate
Estimator.DECAY = 2       -- 1/s; how fast B's rate fades while pressed against a bound
Estimator.MAX_SCALE = 3   -- B never scales its rate by more than this
Estimator.PIN = 0.15      -- yd; an estimate this close to a bracket edge counts as pressed on it
Estimator.REACH = 1.5     -- yd; range checks measure edge to edge, positions centre to centre
Estimator.SMOOTH = 0.15   -- s; smoothing of the player's velocity

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
-- (nil if none). sp: combined speed of player and target in yd/s. px, py: the player's world
-- position, or nil where the game hides it. still: the target is not moving.
-- Returns a crossing record { at, dir, a, b, mid } when a boundary was crossed, else nil.
function Estimator:update(now, dt, lo, hi, sp, px, py, still)
  sp = sp or 0
  self:track(dt, px, py)
  if self.tx and (not px or not still) then self.tx, self.ty = nil, nil end

  if self.tx then
    -- Position mode: the target stands at (tx, ty); the range is the distance to it.
    self.b = math.max(0, math.sqrt((px - self.tx) ^ 2 + (py - self.ty) ^ 2) - Estimator.REACH)
  elseif self.b then
    local moving = sp > 0.05
    if moving and not self.moving then
      -- Starting from rest: if the estimate sits on an edge of the bracket, the only way it can
      -- change is back into the bracket, so start moving that way.
      if self.b <= lo + Estimator.PIN then
        self.bRate, self.refSpeed = sp, sp
      elseif hi and self.b >= hi - Estimator.PIN then
        self.bRate, self.refSpeed = -sp, sp
      end
    end
    local rate = 0
    if moving then
      rate = self.bRate
      if self.refSpeed and self.refSpeed > 0.5 then
        rate = rate * math.min(sp / self.refSpeed, Estimator.MAX_SCALE)
      end
    end
    self.b = self.b + rate * dt
  end
  self.moving = sp > 0.05
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

    if px and still then
      if self.tx then
        self:pin(px, py, at)
      elseif self.vx then
        -- First fix: we cross the boundary moving straight along the line, so the target is
        -- ahead of us when we close in and behind us when we back off.
        local v = math.sqrt(self.vx ^ 2 + self.vy ^ 2)
        if v > 0.5 then
          local r = (at + Estimator.REACH) * -dir / v
          self.tx, self.ty = px + self.vx * r, py + self.vy * r
        end
      end
    end
  end

  if self.b then
    if self.b < lo then
      self.b = lo
      if self.tx then self:pin(px, py, lo) end
      if self.bRate < 0 then self.bRate = self.bRate * math.max(0, 1 - Estimator.DECAY * dt) end
    elseif hi and self.b > hi then
      self.b = hi
      if self.tx then self:pin(px, py, hi) end
      if self.bRate > 0 then self.bRate = self.bRate * math.max(0, 1 - Estimator.DECAY * dt) end
    end
  end

  self.lo, self.hi = lo, hi
  return crossing
end

-- Smoothed player velocity from position deltas.
function Estimator:track(dt, px, py)
  if not px then
    self.px, self.vx, self.vy = nil, nil, nil
    return
  end
  if self.px and dt > 0 then
    local ivx, ivy = (px - self.px) / dt, (py - self.py) / dt
    local k = math.min(1, dt / Estimator.SMOOTH)
    self.vx = (self.vx or ivx) + (ivx - (self.vx or ivx)) * k
    self.vy = (self.vy or ivy) + (ivy - (self.vy or ivy)) * k
  end
  self.px, self.py = px, py
end

-- Moves the target point along its bearing so that its range is exactly d.
function Estimator:pin(px, py, d)
  local dx, dy = self.tx - px, self.ty - py
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1e-6 then return end
  local r = (d + Estimator.REACH) / len
  self.tx, self.ty = px + dx * r, py + dy * r
end

function Estimator:mode()
  return self.tx and "pos" or "rate"
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
