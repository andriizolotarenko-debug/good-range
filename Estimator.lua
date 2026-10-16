-- PURE: turns a stream of range brackets [lo, hi] into distance estimates.
--   mid  the middle of the bracket (what bracket-only addons show)
--   A    trend: the closing rate from the last two boundary crossings, extrapolated
--   B    where the game gives the player's position and the target stands still: the target's
--        spot, fitted to the last few crossings, and the distance to it. Otherwise A plus live speeds
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
Estimator.SOFT = 2        -- yd; a guessed rate slows down this close to the bracket edge ahead
Estimator.CREEP = 0.25    -- the slowest it gets there, as a part of the rate
Estimator.RUN = 7         -- yd/s; run speed, the guess when the game hides every speed
Estimator.FIXES = 6       -- crossings kept to place a standing target (see solve)
Estimator.DAMP = 0.1      -- how firmly solve keeps the target point where it was

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
-- (nil if none). sp: combined speed of player and target in yd/s, or nil where the game hides
-- it (dungeons): then the estimate stands until a crossing shows something moves, and from there
-- keeps the rate of the last crossings, easing into the next edge. px, py: the player's world
-- position, or nil where the game hides it. still: the target is not moving. mine: the player's
-- own part of sp, or nil if unknown.
-- Returns a crossing record { at, dir, a, b, mid } when a boundary was crossed, else nil.
function Estimator:update(now, dt, lo, hi, sp, px, py, still, mine)
  local known = sp ~= nil
  -- Inside the smallest step, a target that has stopped is next to you (in melee): when it moves
  -- again it mostly steps around you, not away, so from then on only your own movement moves the
  -- estimate, until it leaves that step.
  if known and mine and sp - mine >= 0.1 then self.targetMovedAt = now end
  if known and mine and lo == 0 and hi then
    if not self.parked and sp - mine < 0.1 then
      self.parked = true
      -- One that ran up to you stops wherever it can hit you from, and its run in is too short
      -- to time: the estimate would stay on whatever it reached, the bottom of the step or its
      -- top alike. Nothing says where in the step it stands, so take the middle.
      if self.b and not self.tx and self.targetMovedAt and now - self.targetMovedAt < 1 then
        self.b = mid(lo, hi)
      end
    end
    if self.parked then sp = mine end
  else
    self.parked = nil
  end
  sp = sp or 0
  if known then
    self.evidence = nil
  elseif self.evidence == nil then
    self.evidence = false   -- speed just went unknown: nothing has shown movement yet
  end
  self:track(dt, px, py)
  if self.tx and (not px or not still) then self.tx, self.ty, self.fixes = nil, nil, nil end

  if self.tx then
    -- Position mode: the target stands at (tx, ty); the range is the distance to it.
    self.b = math.max(0, math.sqrt((px - self.tx) ^ 2 + (py - self.ty) ^ 2) - Estimator.REACH)
  elseif self.b then
    local moving = known and sp > 0.05 or not known and self.evidence
    if known and moving and not self.moving then
      -- Starting from rest: if the estimate sits on an edge of the bracket, the only way it can
      -- change is back into the bracket, so start moving that way.
      if self.b <= lo + Estimator.PIN then
        self.bRate, self.refSpeed, self.guessed = sp, sp, true
      elseif hi and self.b >= hi - Estimator.PIN then
        self.bRate, self.refSpeed, self.guessed = -sp, sp, true
      end
    end
    local rate = 0
    if moving then
      rate = self.bRate
      if known and self.refSpeed and self.refSpeed > 0.5 then
        rate = rate * math.min(sp / self.refSpeed, Estimator.MAX_SCALE)
      end
      -- A guessed rate (straight at the target at full speed) is often too fast: rather than
      -- run into the next edge and stop dead there until the game confirms the crossing, ease
      -- in over the last SOFT yards.
      local edge = rate > 0 and hi or rate < 0 and lo or nil
      if (self.guessed or not known) and edge then
        local gap = math.abs(edge - self.b)
        if gap < Estimator.SOFT then rate = rate * math.max(Estimator.CREEP, gap / Estimator.SOFT) end
      end
    end
    self.b = self.b + rate * dt
  end
  self.moving = known and sp > 0.05 or not known and self.evidence
  if known then
    self.spSum = (self.spSum or 0) + sp * dt
    self.spT = (self.spT or 0) + dt
  end

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
    -- it happened between the last check and this one: on average half a tick ago
    local t = now - dt / 2
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
    local fresh = last and t - last.t < Estimator.WINDOW and t > last.t
    -- A: plain trend between the last two crossings (0 when the same boundary is crossed back).
    self.aRate = fresh and (at - last.at) / (t - last.t) or 0
    self.anchor, self.anchorT = at, t
    -- B: the measured rate when it agrees with this crossing's direction, otherwise assume
    -- we are moving straight along the line at the current combined speed.
    local measured = fresh and (at - last.at) / (t - last.t)
    if measured and measured * dir > 0 then
      self.bRate = measured
      self.refSpeed = (self.spT or 0) > 0 and self.spSum / self.spT or nil
      self.guessed = false
      self.pace = math.abs(measured)
    else
      -- with no speed to go by, the pace measured last time (or a run)
      local guess = known and math.max(sp, 1) or self.pace or Estimator.RUN
      self.bRate = dir * guess
      self.refSpeed = known and guess or nil
      self.guessed = true
    end
    -- and it has moved on since: by half a tick at the rate it moves now
    self.b = at + ((known and sp > 0.05 or not known and self.evidence) and self.bRate * dt / 2 or 0)
    if not known then self.evidence = true end
    self.spSum, self.spT = 0, 0
    self.last = { t = t, at = at }

    if px and still then
      -- where you stood at the crossing, half a tick back
      local cx, cy = px - (self.vx or 0) * dt / 2, py - (self.vy or 0) * dt / 2
      self.fixes = self.fixes or {}
      table.insert(self.fixes, { cx, cy, at + Estimator.REACH })
      if #self.fixes > Estimator.FIXES then table.remove(self.fixes, 1) end
      if self.tx then
        if #self.fixes > 1 then self:solve() else self:pin(px, py, at) end
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

-- Places the target point to fit the kept crossings best: each says the target is on a circle
-- (its range plus REACH) around where you stood. A few damped Gauss-Newton steps from the current
-- point, so a straight run, which says nothing about left or right, keeps the point's side. A
-- point on the line you ran along can't move off it that way, so the solve also starts from a
-- point to each side of it and from its mirror image across that line, and keeps the best fit.
local function fit(fixes, tx, ty)
  local err
  for step = 1, 6 do
    local a, b, c, gx, gy = Estimator.DAMP, 0, Estimator.DAMP, 0, 0
    err = 0
    for _, f in ipairs(fixes) do
      local dx, dy = tx - f[1], ty - f[2]
      local len = math.sqrt(dx * dx + dy * dy)
      if len > 1e-6 then
        local ux, uy, r = dx / len, dy / len, len - f[3]
        a, b, c = a + ux * ux, b + ux * uy, c + uy * uy
        gx, gy = gx + ux * r, gy + uy * r
        err = err + r * r
      end
    end
    local det = a * c - b * b
    if step == 6 or det < 1e-9 then break end
    tx, ty = tx - (c * gx - b * gy) / det, ty - (a * gy - b * gx) / det
  end
  return tx, ty, err
end

function Estimator:solve()
  local tx, ty = self.tx, self.ty
  local bx, by, best = fit(self.fixes, tx, ty)
  local v = self.vx and math.sqrt(self.vx ^ 2 + self.vy ^ 2) or 0
  if v > 0.5 and self.px then
    -- the same point mirrored across the line you run along, and a nudge to each side of it
    local ux, uy = self.vx / v, self.vy / v
    local side = (tx - self.px) * -uy + (ty - self.py) * ux
    for _, off in ipairs({ -2 * side, 2, -2 }) do
      local x, y, err = fit(self.fixes, tx - uy * off, ty + ux * off)
      if err < best - 1e-6 then bx, by, best = x, y, err end
    end
  end
  self.tx, self.ty = bx, by
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
