-- Good Range: distance to the target from range checks, shown on a sliding range tape or as a
-- number with a zone badge. Colours come from your class zones: blue melee, green shoot / cast /
-- heal, red dead zone, grey out of range.
local _, ns = ...

local issecret = issecretvalue or function() return false end
local API = ns.API
-- ~30 ticks a second (10 while nobody moves, see IDLE_TICK): each checks only the two steps
-- around the distance (see measure), so a crossing is timed to a tick; the display carries the
-- estimate on between ticks.
local TICK = 0.03
local MELEE = ns.Zones.MELEE
local Estimator = ns.Estimator
-- Some spells reach "anywhere" (50000 yd); as a range step they would put a far target in a
-- 100-50000 yd bracket and show its middle. No attack or heal reaches past the longest item step.
local MAX_STEP = 100

-- Range items: Classic Era and WoW: Forever (interface 1xxxx) prefer the Era list, the rest the
-- modern one; each falls back on the other, and only items the client knows are used.
local interface = select(4, GetBuildInfo())
local CLASSIC_RULES = interface < 20000
local RETAIL = interface >= 100000
local _, playerClass = UnitClass("player")

local function itemLists(a, b)
  local out = {}
  for _, list in ipairs({ a, b }) do
    for range, ids in pairs(list) do
      out[range] = out[range] or {}
      for _, id in ipairs(ids) do table.insert(out[range], id) end
    end
  end
  return out
end

ns.DEFAULTS = {
  width = 130, height = 31, fontSize = 32, ppy = 20, display = "tape", badgeScale = 100,
  font = "Interface\\AddOns\\GoodRange\\media\\Changa-Bold.ttf",
  inCombat = true, outOfCombat = true, friendly = true, enemyPlayers = true, enemyNPCs = true,
  mouseover = false, mouseoverScale = 100,
  unlocked = false, nameplate = false, plateX = 0, plateY = 2,
  focus = false, focusScale = 100, showUnit = true,
}
-- The focus came with TBC; a client without it gets no focus option.
ns.HAS_FOCUS = FocusFrame ~= nil or interface >= 20000

local db
local groups = {}        -- ascending by range: { range, harmItem, friendItem, interact, spells }
local spellbook = { known = {}, generic = { harm = {}, help = {} } }   -- filled by build()
local spans, spanKey = {}, ""   -- the zones for the current target (see Zones.build)
local secrets = { spell = 0, item = 0, speed = 0 }

local function say(msg) print("|cff66ccffGood Range|r " .. msg) end

-- Checkers --------------------------------------------------------------------------------

local function group(range)
  for _, g in ipairs(groups) do
    if g.range == range then return g end
  end
  local g = { range = range, spells = {} }
  groups[#groups + 1] = g
  return g
end

local function itemReady(id)
  local getInfo = C_Item.GetItemInfo or GetItemInfo
  return C_Item.IsItemDataCachedByID(id) and getInfo(id) ~= nil
end

local function pickItem(ids)
  for _, id in ipairs(ids) do
    if itemReady(id) then return id end
    C_Item.RequestLoadItemDataByID(id)
  end
end

local INTERACT = { [3] = 8, [4] = 28 }
local INTERACT_RACE = { Tauren = { [3] = 6, [4] = 25 }, Scourge = { [3] = 7, [4] = 27 } }

local function build()
  wipe(groups)
  API.ForgetSpells()
  local harmItems = CLASSIC_RULES and itemLists(ns.ERA_HARM_ITEMS, ns.HARM_ITEMS)
    or itemLists(ns.HARM_ITEMS, ns.ERA_HARM_ITEMS)
  local friendItems = CLASSIC_RULES and itemLists(ns.ERA_FRIEND_ITEMS, ns.FRIEND_ITEMS)
    or itemLists(ns.FRIEND_ITEMS, ns.ERA_FRIEND_ITEMS)
  for range, ids in pairs(harmItems) do group(range).harmItem = pickItem(ids) end
  for range, ids in pairs(friendItems) do group(range).friendItem = pickItem(ids) end
  local _, race = UnitRace("player")
  for index, range in pairs(INTERACT_RACE[race] or INTERACT) do group(range).interact = index end

  local harmWork, helpWork, known, helpIds = {}, {}, {}, {}
  for _, id in ipairs(API.Spellbook()) do
    local info = API.GetSpellInfo(id)
    if info then
      known[info.name] = id
      local min, max = info.minRange or 0, info.maxRange or 0
      if max > MAX_STEP then max = 0 end
      -- A spell with a minimum range says "false" up close too, so it can't bound the bracket by
      -- its reach; its minimum is a step of its own (a hunter's dead zone ends where Auto Shot
      -- says it can fire, see check).
      if max > 0 and min == 0 then table.insert(group(max).spells, id) end
      if max > min and min > MELEE then
        local g = group(min)
        g.minSpells = g.minSpells or {}
        table.insert(g.minSpells, { id, max })
      end
      -- Fallback zones for classes / clients the list in Zones.lua does not cover.
      local harmful, helpful = API.IsSpellHarmful(id), API.IsSpellHelpful(id)
      if harmful and max > MELEE then
        harmWork[#harmWork + 1] = { min, max }
      elseif helpful and max > 0 then
        helpWork[#helpWork + 1] = { min, max }
        helpIds[#helpIds + 1] = id
      end
    end
  end
  spellbook.known = known
  spellbook.generic = { harm = ns.Zones.merge(harmWork), help = ns.Zones.merge(helpWork) }
  spellbook.helpIds = helpIds
  -- talents and spec change only with the spells (a rebuild); the form is read each time
  spellbook.mainTree = (playerClass == "SHAMAN" or playerClass == "PALADIN") and API.MainTree() or nil
  spellbook.role = RETAIL and API.SpecRole() or nil
  -- a new spec has its own zones (see ns.UseZones)
  if db and ns.UseZones() then
    ns.ApplyLayout()
    if ns.RefreshOptions then ns.RefreshOptions() end
  end

  for i = #groups, 1, -1 do
    local g = groups[i]
    if not g.harmItem and not g.friendItem and not g.interact and #g.spells == 0 and not g.minSpells then
      table.remove(groups, i)
    end
  end
  table.sort(groups, function(a, b) return a.range < b.range end)
  if ns.ForgetBracket then ns.ForgetBracket() end
  if ns.OnZonesChanged then ns.OnZonesChanged() end
end

local rebuildPending
local function rebuildSoon()
  if rebuildPending then return end
  rebuildPending = true
  C_Timer.After(1, function() rebuildPending = false; build() end)
end

-- true / false / nil (unknown) for one range step, and what gave the answer and its ID (for /gr
-- list; no strings are built here, it runs many times a second).
local check

-- Is an enemy within max yd by any step above g? (Out of a min-range spell's range can be either
-- side of it.)
local function within(g, max, unit, restricted)
  for _, o in ipairs(groups) do
    if o.range > g.range and o.range <= max and check(o, unit, true, restricted) == true then return true end
  end
  return false
end

function check(g, unit, hostile, restricted)
  -- a min-range spell answers first at its minimum, so the dead zone ends exactly where it
  -- can fire: in range = past the minimum; out of range = inside it, if a step up to its reach
  -- says the enemy is that close
  if hostile and g.minSpells then
    for _, m in ipairs(g.minSpells) do
      local v = API.IsSpellInRange(m[1], unit)
      if issecret(v) then
        secrets.spell = secrets.spell + 1
      elseif v == true then
        return false, "min", m[1]
      elseif v == false and within(g, m[2], unit, restricted) then
        return true, "min-", m[1]
      end
    end
  end
  local item = hostile and g.harmItem or g.friendItem
  if item and not restricted then
    local v = API.IsItemInRange(item, unit)
    if issecret(v) then
      secrets.item = secrets.item + 1
    else
      local inRange = v == true or v == 1
      return inRange, inRange and "item" or "item-"
    end
  end
  if g.interact and not restricted then
    local v = CheckInteractDistance(unit, g.interact)
    if not issecret(v) then
      return v and true or false, v and "interact" or "interact-"
    end
  end
  for _, id in ipairs(g.spells) do
    local v = API.IsSpellInRange(id, unit)
    if issecret(v) then
      secrets.spell = secrets.spell + 1
    elseif v ~= nil then
      return v, v and "spell" or "spell-", id
    end
  end
  return nil
end

-- A tracker follows one unit (the target, the focus): its last bracket, when its steps were last
-- scanned, and its distance estimate.
local function newTracker(unit)
  return { unit = unit, est = Estimator.new(), res = {}, lastLo = 0 }
end
local T, F, M = newTracker("target"), newTracker("focus"), newTracker("mouseover")
local ticking = { T, F, M }

-- lo: the largest step reported out (below hi), hi: the smallest step reported in.
local function scan(tr, hostile, restricted, from, to)
  local hi, hiI
  local res = tr.res
  for i = from, to do
    local g = groups[i]
    local r, why, id = check(g, tr.unit, hostile, restricted)
    res[i] = r
    if tr == T then g.result, g.last, g.lastId = r, why, id end   -- what /gr list shows
    if r == true and not hi then hi, hiI = g.range, i end
  end
  local lo, loI = 0, nil
  for i = from, to do
    local g = groups[i]
    if res[i] == false and (not hi or g.range < hi) and g.range > lo then lo, loI = g.range, i end
  end
  return lo, hi, loI, hiI
end

-- Checking every step is the expensive part. Each tick only the two steps bounding the last
-- bracket (its edges) are checked, so a crossing is timed to the frame. The steps around them are
-- scanned as soon as an edge changes and every WINDOW_EVERY s; all steps every FULL_EVERY s, on a
-- new target, and whenever the answer could lie outside that window. No scan comes sooner than
-- SCAN_MIN s after the last one, so steps that give no answer can't make it scan every frame.
local WINDOW_EVERY, FULL_EVERY, SCAN_MIN = 0.2, 0.5, 0.05
-- While you and every unit followed stand still (see the driver), no step can be crossed: the
-- range is checked every IDLE_TICK s then, and the steps around it scanned IDLE_SLOW times as
-- rarely.
local IDLE_TICK, IDLE_SLOW = 0.1, 4
local idle = false

-- tr: the tracker to forget, or nil for both (the steps changed)
function ns.ForgetBracket(tr)
  for _, t in ipairs(tr and { tr } or ticking) do
    t.nextWindow, t.nextFull, t.lastScan, t.loIdx, t.hiIdx = 0, 0, -1, nil, nil
  end
end
ns.ForgetBracket()

-- the steps around the last bracket, or all of them
local function rescan(tr, hostile, restricted, now)
  local n = #groups
  local lo, hi, loI, hiI
  if now < tr.nextFull and (tr.loIdx or tr.hiIdx) then
    local from = math.max(1, (tr.loIdx or 1) - 1)
    local to = math.min(n, (tr.hiIdx or n) + 1)
    lo, hi, loI, hiI = scan(tr, hostile, restricted, from, to)
    local outside = (not hi and to < n) or (hiI == from and from > 1) or (not loI and from > 1)
    if not outside then
      tr.loIdx, tr.hiIdx = loI, hiI
      return lo, hi
    end
  end
  lo, hi, loI, hiI = scan(tr, hostile, restricted, 1, n)
  tr.loIdx, tr.hiIdx = loI, hiI
  tr.nextFull = now + FULL_EVERY * (idle and IDLE_SLOW or 1)
  return lo, hi
end

local function measure(tr, hostile, now)
  local restricted = InCombatLockdown() and not hostile
  local loIdx, hiIdx = tr.loIdx, tr.hiIdx
  if (loIdx or hiIdx) and now < tr.nextWindow
      and (not loIdx or check(groups[loIdx], tr.unit, hostile, restricted) == false)
      and (not hiIdx or check(groups[hiIdx], tr.unit, hostile, restricted) == true) then
    return tr.lastLo, tr.lastHi   -- both edges as they were
  end
  if now - tr.lastScan < SCAN_MIN then return tr.lastLo, tr.lastHi end
  tr.lastScan, tr.nextWindow = now, now + WINDOW_EVERY * (idle and IDLE_SLOW or 1)
  tr.lastLo, tr.lastHi = rescan(tr, hostile, restricted, now)
  return tr.lastLo, tr.lastHi
end

local function speedOf(unit)
  local v = GetUnitSpeed(unit)
  if v == nil then return nil end
  if issecret(v) then
    secrets.speed = secrets.speed + 1
    return nil
  end
  return v
end

-- Used when the game gives it (open world); in dungeons it is hidden and B works from rates.
local function playerPos()
  local y, x = UnitPosition("player")
  if not y or issecret(y) or issecret(x) then return nil end
  return x, y
end

-- Zones -------------------------------------------------------------------------------------

local hostileTarget = true


-- Can one of your heals or buffs go on this unit? (A spell that can't target it, like Mend Pet
-- on a player, gives no range answer at all.) Checked once per target / focus.
local helpable = {}
local function canHelp(unit)
  if helpable[unit] == nil then
    helpable[unit] = false
    for _, id in ipairs(spellbook.helpIds or {}) do
      local v = API.IsSpellInRange(id, unit)
      if not issecret(v) and v ~= nil then
        helpable[unit] = true
        break
      end
    end
  end
  return helpable[unit]
end

-- A friendly player none of your heals or buffs can reach: the distance in grey all the way
-- (green and blue mean you can act from there).
local FRIEND_ONLY = { { 0, math.huge, "far", "FRIENDLY" } }

-- The zones from what you can use right now (form, rage / mana, cooldowns, weapon, combat)
-- against an enemy or a friend (unit: whose heal / buff reach to check; nil: any you can help).
-- auto: as Auto gives them, without the ranges set in Settings > Zones
local ctx = { class = playerClass, getInfo = API.GetSpellInfo, usable = API.IsUsable, ready = API.IsReady }
local function zonesFor(hostile, unit, auto)
  ctx.hostile, ctx.known, ctx.generic = hostile, spellbook.known, spellbook.generic
  ctx.form = playerClass == "DRUID" and API.Form() or nil
  ctx.mainTree, ctx.primaryRole = spellbook.mainTree, spellbook.role
  if not hostile and unit and not canHelp(unit) then return FRIEND_ONLY, {}, ctx end
  local new, diag = ns.Zones.build(ctx)
  local own = db and not auto and not db.zones.auto and db.zones[hostile and "list" or "friendly"]
  if own then new = ns.Zones.fromList(own) end
  return new, diag, ctx
end

-- What Auto gives right now (your class, spec, spells and talents, form) on enemies, or on
-- friendly targets you can heal or buff, as the zones in a row (see Zones.partition)
function ns.AutoZones(friendly)
  return ns.Zones.partition((zonesFor(not friendly, nil, true)), friendly)
end

-- Rebuilds the target's zones; true if they changed.
local function refreshZones()
  local new, diag, c = zonesFor(hostileTarget, "target")
  ns.diag = { class = playerClass, form = c.form, mainTree = c.mainTree, spells = diag }
  local parts = {}
  for _, sp in ipairs(new) do parts[#parts + 1] = table.concat(sp, ",") end
  local key = table.concat(parts, ";")
  if key == spanKey then return false end
  spans, spanKey = new, key
  return true
end

-- d in yd -> kind, badge text
local function zoneAt(d)
  return ns.Zones.at(d, spans)
end

-- UI ----------------------------------------------------------------------------------------

local tape = ns.Tape.New(UIParent, "GoodRangeTape")
local root = tape.root
root:SetMovable(true)
root:SetClampedToScreen(true)
root:RegisterForDrag("LeftButton")
local plate   -- the target's nameplate the display hangs over, if any (see place)
local focusPlate   -- the focus's nameplate the focus label hangs over, if any (see placeFocus)
local targetOn, focusOn, mouseOn = false, false, false   -- which units are followed (see RefreshShown)
-- After hanging on a nameplate, the game can hand the frame back no longer movable (Retail 12.x):
-- make it movable again before each drag, and never let a refusal raise an error.
local function drag(self)
  if not self:IsMovable() then pcall(self.SetMovable, self, true) end
  pcall(self.StartMoving, self)
end
local function startMoving(self)
  if not plate then drag(self) end
end
root:SetScript("OnDragStart", startMoving)
root:SetScript("OnDragStop", function(self)
  if plate then return end
  self:StopMovingOrSizing()
  local point, _, rel, x, y = self:GetPoint()
  if x and not issecret(x) and not issecret(y) then db.pos = { point, rel, x, y } end
end)
root:Hide()

-- the label's badge drags on its own; once dragged it stays where it was put, wherever the number goes
local badge = tape.badge
badge:SetMovable(true)
badge:SetClampedToScreen(true)
badge:RegisterForDrag("LeftButton")
badge:SetScript("OnDragStart", startMoving)
badge:SetScript("OnDragStop", function(self)
  if plate then return end
  self:StopMovingOrSizing()
  local point, _, rel, x, y = self:GetPoint()
  if x and not issecret(x) and not issecret(y) then db.badgePos = { point, rel, x, y } end
end)

-- The nameplate frame is taller than what it draws: stand on its health bar, or on the name when
-- that sits above the bar. Nameplate addons (Plater) draw their own frame; it is used when shown.
local function plateAnchor(p)
  local uf = p.unitFrame and p.unitFrame:IsShown() and p.unitFrame or p.UnitFrame
  local bar = uf and uf.healthBar
  if not bar then return p end
  local name = uf.name
  if name and name:IsShown() then
    local bottom, top = name:GetBottom(), bar:GetTop()
    if bottom and top and not issecret(bottom) and not issecret(top) and bottom >= top - 1 then return name end
  end
  return bar
end

local function plateOf(unit)
  return db.nameplate and C_NamePlate and C_NamePlate.GetNamePlateForUnit
    and C_NamePlate.GetNamePlateForUnit(unit) or nil
end

-- Over the target's nameplate when that option is on and the target has one; otherwise (nameplates
-- off, the target too far or off screen) where it was put on the screen. A target the display
-- is not shown for (see RefreshShown) gets no plate either, so the settings' sample stays put.
local function place()
  plate = targetOn and plateOf("target") or nil
  local label = db.display == "label" and tape.badgeGap
  root:ClearAllPoints()
  if plate then
    -- the label's badge hangs off the number's left: centre the pair, not the number
    local shift = label and (tape.badgeW + tape.badgeGap) / 2 or 0
    local ok, anchor = pcall(plateAnchor, plate)
    root:SetPoint("BOTTOM", ok and anchor or plate, "TOP", db.plateX + shift, db.plateY)
  elseif db.pos then
    root:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
  else
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 110)   -- roughly above the character
  end
  -- a dragged badge stays where it was put, except over a nameplate: there it goes with the number
  if label then
    badge:ClearAllPoints()
    if db.badgePos and not plate then
      badge:SetPoint(db.badgePos[1], UIParent, db.badgePos[2], db.badgePos[3], db.badgePos[4])
    else
      badge:SetPoint("RIGHT", root, "LEFT", -tape.badgeGap, 0)
    end
  end
  tape:SetUnlocked(db.unlocked)
  if plate then
    tape.hint:SetText("Over the target's nameplate: move it with the nameplate offset sliders.")
  elseif db.unlocked and UnitExists("target") and not targetOn then
    tape.hint:SetText("Not shown for this target: friendly NPCs and the Show settings skip it.")
  end
end

-- The focus label: one look whatever the display, dragged on its own while the settings are open.
local focusLabel = ns.Tape.Focus.New(UIParent, "GoodRangeFocus")
local focusRoot = focusLabel.root
focusRoot:SetMovable(true)
focusRoot:SetClampedToScreen(true)
focusRoot:RegisterForDrag("LeftButton")
focusRoot:SetScript("OnDragStart", function(self)
  if not focusPlate then drag(self) end
end)
focusRoot:SetScript("OnDragStop", function(self)
  if focusPlate then return end
  self:StopMovingOrSizing()
  local point, _, rel, x, y = self:GetPoint()
  if x and not issecret(x) and not issecret(y) then db.focusPos = { point, rel, x, y } end
end)
focusRoot:Hide()

-- The mouseover label: the focus label's look, beside the cursor while a unit is under it (not
-- your target, which the display shows already).
local mouseLabel = ns.Tape.Focus.New(UIParent, "GoodRangeMouseover")
local mouseRoot = mouseLabel.root
mouseRoot:SetFrameStrata("TOOLTIP")
mouseRoot:Hide()
local cursorX, cursorY
mouseRoot:SetScript("OnUpdate", function(self)
  if not UnitExists("mouseover") then
    ns.RefreshShown()
    return
  end
  local x, y = GetCursorPosition()
  if x == cursorX and y == cursorY then return end
  cursorX, cursorY = x, y
  local scale = UIParent:GetEffectiveScale()
  self:ClearAllPoints()
  -- above and right of the pointer's tip, clear of the arrow
  self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale + 4)
end)
mouseRoot:SetScript("OnShow", function() cursorX = nil end)

-- Over the focus's nameplate with the same offsets as the display (just above the display when
-- the focus is the target too); otherwise where it was put on the screen.
local function placeFocus()
  focusPlate = focusOn and plateOf("focus") or nil
  focusRoot:ClearAllPoints()
  if focusPlate and focusPlate == plate then
    focusRoot:SetPoint("BOTTOM", root, "TOP", 0, 2)
  elseif focusPlate then
    local ok, anchor = pcall(plateAnchor, focusPlate)
    focusRoot:SetPoint("BOTTOM", ok and anchor or focusPlate, "TOP", db.plateX, db.plateY)
  elseif db.focusPos then
    focusRoot:SetPoint(db.focusPos[1], UIParent, db.focusPos[2], db.focusPos[3], db.focusPos[4])
  else
    focusRoot:SetPoint("CENTER", UIParent, "CENTER", 0, 66)   -- just under the display
  end
  focusLabel:SetUnlocked(db.unlocked)
end

-- nameplates come and go as the target walks in and out of view: place again once they settle
local placePending
local function placeSoon()
  if placePending then return end
  placePending = true
  C_Timer.After(0, function() placePending = false; place(); placeFocus() end)
end

tape:SetZones(zoneAt)
function ns.OnZonesChanged()
  refreshZones()
  tape:SetZones(zoneAt)
end

function ns.ApplyLayout()
  if not db then return end
  ns.Tape.SetColors(not db.zones.auto and db.colors or nil)   -- on Auto, the default colours
  tape:SetLayout(db.width, db.height, db.fontSize, db.ppy, db.font, db.display, db.badgeScale / 100, db.showUnit)
  focusLabel:SetLayout(db.focusScale / 100, ns.DEFAULTS.font)
  mouseLabel:SetLayout(db.mouseoverScale / 100, ns.DEFAULTS.font)
  ns.RefreshShown()
  place()
  placeFocus()
end

-- Tick: estimation at ~30 Hz (10 Hz standing still) on a hidden driver frame -------------------

local goal, goalLabel        -- what the tape slides towards (display units) and its label
local goalRate, goalLo, goalHi, sinceTick = 0, 0, nil, 0   -- how goal moves on between ticks
local noData = false         -- no range check answered (the game hides them, e.g. secret values)
local shown                  -- what the tape shows now
local acc, clock = 0, 0
-- What you can use (rage, form, cooldowns ...) is checked again when the game says it changed
-- (zoneGen counts those events), at most every ZONE_EVERY s, and every ZONE_IDLE s in any case.
local ZONE_EVERY, ZONE_IDLE = 0.25, 2
local zoneGen = 0
local zoneClock, zoneSeen = 0, -1
-- the small labels (focus, mouseover): each with its tracker and its own zones (the unit can be a
-- friend while the target is an enemy); show: shown on its first value (the mouseover label)
local function newLabel(tr, label, show)
  return { tr = tr, label = label, show = show, spans = {}, clock = 0, seen = -1 }
end
local focusL, mouseL = newLabel(F, focusLabel), newLabel(M, mouseLabel, true)
local function forgetLabel(L)
  L.tr.est:reset()
  helpable[L.tr.unit], L.hostile = nil, nil
  ns.ForgetBracket(L.tr)
  L.label:Clear()
end

-- One tick of a tracker: its bracket, then its estimate. dt: the time moved since the last tick,
-- ps: your speed, px / py: your position.
local function follow(tr, hostile, dt, ps, px, py)
  local lo, hi = measure(tr, hostile, clock)
  local ts = speedOf(tr.unit)
  -- combined speed; nil (unknown) unless both are known, or you move and the unit's is hidden
  -- (counted as standing then, as before). Standing with the unit's hidden is unknown: the
  -- estimate then moves only once a crossing shows the unit does.
  local sp = ps and ts and ps + ts or ps and ps > 0.05 and ps or nil
  -- An unknown unit speed counts as standing; the next crossing corrects a wrong guess.
  local crossed = tr.est:update(clock, dt, lo, hi, sp, px, py, not ts or ts < 0.1, ps)
  -- inside a min-range spell's minimum (the dead zone): just under its edge at most, where the
  -- zones already turn green
  local g = hi and tr.hiIdx and groups[tr.hiIdx]
  if g and g.minSpells and g.range == hi then hi = hi - 0.05 end
  return lo, hi, tr.est:valueB(lo, hi), crossed
end

-- One tick of a small label: its zones now and then, its distance (the estimate; the middle of
-- the bracket until a crossing). dt: since the last tick, moveDt: moved since then (see the driver)
local function followLabel(L, dt, moveDt, ps, px, py)
  local unit = L.tr.unit
  if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then return end
  local hostile = UnitCanAttack("player", unit)
  if issecret(hostile) then hostile = true end
  L.clock = L.clock + dt
  if hostile ~= L.hostile or L.clock >= ZONE_EVERY and (L.seen ~= zoneGen or L.clock >= ZONE_IDLE) then
    L.hostile, L.clock, L.seen = hostile, 0, zoneGen
    L.spans = zonesFor(hostile, unit)
  end
  local lo, hi, b = follow(L.tr, hostile, moveDt, ps, px, py)
  if not hi and lo == 0 then
    L.label:SetNoData()
  else
    local d = b or lo
    -- whole yards, "+" past the last step that answered, never wider than "99+"
    local text = d >= 99 and "99+" or b and tostring(math.floor(b)) or math.floor(lo) .. "+"
    L.label:Set(text, (ns.Zones.at(d, L.spans)))
  end
  if L.show then L.label.root:Show() end
end

-- Standing still (see IDLE_TICK), a speed check each frame wakes the ticks as soon as one moves.
-- A hidden or unknown speed counts as moving.
local function standing(unit)
  local v = GetUnitSpeed(unit)
  return v ~= nil and not issecret(v) and v == 0
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + elapsed
  if acc < TICK then return end
  local wasIdle = idle
  idle = standing("player") and (not targetOn or standing("target")) and (not focusOn or standing("focus"))
    and (not mouseOn or standing("mouseover"))
  if wasIdle and idle and acc < IDLE_TICK then return end
  local dt = acc
  acc = 0
  clock = clock + dt
  -- woken by a move: it began since the last speed check, not over the whole idle wait
  local moveDt = wasIdle and not idle and math.min(dt, TICK) or dt
  if wasIdle and not idle then
    -- scan on the usual schedule again
    for _, tr in ipairs(ticking) do
      tr.nextWindow = math.min(tr.nextWindow, clock + WINDOW_EVERY)
      tr.nextFull = math.min(tr.nextFull, clock + FULL_EVERY)
    end
  end
  local ps = speedOf("player")
  if ps == nil and IsPlayerMoving then
    -- the game hides speeds in dungeons: moving or not is enough to start and stop the estimate
    local m = IsPlayerMoving()
    if not issecret(m) then ps = m and Estimator.RUN or 0 end
  end
  local px, py = playerPos()
  if focusOn then followLabel(focusL, dt, moveDt, ps, px, py) end
  if mouseOn then followLabel(mouseL, dt, moveDt, ps, px, py) end

  local unit = "target"
  if not targetOn or not UnitExists(unit) or UnitIsDeadOrGhost(unit) then return end
  local hostile = UnitCanAttack("player", unit)
  if issecret(hostile) then hostile = true end
  zoneClock = zoneClock + dt
  if hostile ~= hostileTarget or zoneClock >= ZONE_EVERY and (zoneSeen ~= zoneGen or zoneClock >= ZONE_IDLE) then
    hostileTarget = hostile
    zoneClock, zoneSeen = 0, zoneGen
    if refreshZones() then tape:SetZones(zoneAt) end
  end

  local was = goal
  local lo, hi, b, crossed = follow(T, hostile, moveDt, ps, px, py)

  -- nothing said in or out: "0+" would look like a reading, so say there is no data
  noData = not hi and lo == 0
  if noData then
    shown = nil
  elseif b then
    goal = b
    goalLabel = tostring(math.floor(goal))
  else
    goal = lo
    goalLabel = math.floor(goal) .. "+"
  end
  -- two digits at most, so the number never gets wider: 99 yd and beyond read "99+"
  if not noData and goal >= 99 then goalLabel = "99+" end
  -- how fast the estimate moves now, so the display can carry it on until the next tick (not
  -- across a crossing, where it jumps)
  goalRate = b and was and b == goal and not crossed and (goal - was) / dt or 0
  goalLo, goalHi, sinceTick = lo, hi, 0
end)

-- Drawing: every frame, the tape glides towards the latest estimate.
root:SetScript("OnUpdate", function(_, elapsed)
  if noData ~= (tape.noData or false) then tape:SetNoData(noData) end
  if noData then return end
  if not goal then
    if not db.unlocked then return end
    goal, goalLabel = 21.4, "21"   -- sample while unlocked
  end
  local aim = goal
  if goalRate ~= 0 then
    sinceTick = sinceTick + elapsed
    aim = math.max(goalLo, goal + goalRate * math.min(sinceTick, 2 * TICK))
    if goalHi and aim > goalHi then aim = goalHi end
  end
  if shown == aim then return end
  shown = shown and shown + (aim - shown) * math.min(1, elapsed * 14) or aim
  if math.abs(aim - shown) < 0.002 then shown = aim end
  tape:Draw(shown, goalLabel ~= tostring(math.floor(goal)) and goalLabel or tostring(math.floor(shown)))
end)

-- unit is other (secret: no)
local function same(unit, other)
  local v = UnitIsUnit(unit, other)
  return not issecret(v) and v and true or false
end

-- Followed if living and the options allow it in this state (combat, unit kind: enemy players,
-- enemy NPCs including critters, friendly players). Never friendly NPCs; friendly players in grey
-- unless you can heal or buff them (see zonesFor).
local function wanted(unit)
  local has = UnitExists(unit) and not UnitIsDeadOrGhost(unit)
  if has and db then
    local fighting = UnitAffectingCombat("player")
    local hostile = UnitCanAttack("player", unit)
    if issecret(hostile) then hostile = true end
    local player = UnitIsPlayer(unit)
    if issecret(player) then player = true end
    if fighting and not db.inCombat or not fighting and not db.outOfCombat
        or hostile and player and not db.enemyPlayers or hostile and not player and not db.enemyNPCs
        or not hostile and not db.friendly
        or not hostile and not player then
      has = false
    end
  end
  return has
end

function ns.RefreshShown()
  local was, wasFocus = targetOn, focusOn
  targetOn = wanted("target")
  focusOn = ns.HAS_FOCUS and db and db.focus and wanted("focus") or false
  local wasMouse = mouseOn
  mouseOn = db and db.mouseover and not same("mouseover", "target") and not same("mouseover", "player")
    and wanted("mouseover") or false
  if not mouseOn then mouseRoot:Hide() elseif not wasMouse then forgetLabel(mouseL) end
  -- a unit shown or hidden now (combat, a heal learned ...) may gain or lose its nameplate spot
  if db and db.nameplate and (was ~= targetOn or wasFocus ~= focusOn) then placeSoon() end
  driver:SetShown(targetOn or focusOn or mouseOn)
  root:SetShown(targetOn or (db and db.unlocked))
  -- while the settings are open the label shows (a sample without a focus) so it can be moved
  focusRoot:SetShown(focusOn or (ns.HAS_FOCUS and db and db.focus and db.unlocked) or false)
end

-- Commands ----------------------------------------------------------------------------------

local function printStats()
  local s = T.est.stats
  if s.n == 0 then
    say("no measured crossings yet. Run at a target until its bracket changes twice.")
    return
  end
  say(("%d crossings. Mean error: middle of bracket %.2f, A %.2f, B %.2f yd. Worst: A %.1f, B %.1f.")
    :format(s.n, s.midn > 0 and s.mid / s.midn or 0, s.a / s.n, s.b / s.n, s.amax, s.bmax))
end

local function printList()
  refreshZones()
  say(("%d range steps. Secret results so far: spell %d, item %d, speed %d. Own position: %s.")
    :format(#groups, secrets.spell, secrets.item, secrets.speed, playerPos() and "yes" or "hidden"))
  local zoneParts = {}
  for _, sp in ipairs(spans) do
    zoneParts[#zoneParts + 1] = ("%s %g-%g (%s)"):format(sp[4], sp[1], sp[2], sp[3])
  end
  local d = ns.diag or {}
  local count = 0
  for _ in pairs(spellbook.known) do count = count + 1 end
  say(("%s%s%s, %d spells in the spellbook, %s target. Zones: %s"):format(d.class or "?",
    d.form and (" in " .. d.form .. " form") or "", d.mainTree and (", talent tree " .. d.mainTree) or "",
    count, hostileTarget and "enemy" or "friendly", #zoneParts > 0 and table.concat(zoneParts, ", ") or "none"))
  local keys = {}
  for _, k in ipairs(d.spells or {}) do
    keys[#keys + 1] = ("%s %g-%g%s%s"):format(k[1], k[3], k[4], k[5] and "" or " (default)",
      k[6] == false and " (not usable now)" or "")
  end
  say("Class spells: " .. (#keys > 0 and table.concat(keys, ", ") or "none found"))
  for _, g in ipairs(groups) do
    local parts = {}
    if g.harmItem then parts[#parts + 1] = "harm item " .. g.harmItem end
    if g.friendItem then parts[#parts + 1] = "friend item " .. g.friendItem end
    if g.interact then parts[#parts + 1] = "interact " .. g.interact end
    if #g.spells > 0 then parts[#parts + 1] = #g.spells .. " spells" end
    local r = g.result == true and "|cff4dff59in|r" or g.result == false and "|cffff4433out|r" or "-"
    local why = g.last and (g.lastId and g.last .. " " .. g.lastId or g.last) or ""
    print(("  %3d yd  %s  %s  %s"):format(g.range, r, table.concat(parts, ", "), why))
  end
end

SLASH_GOODRANGE1 = "/goodrange"
SLASH_GOODRANGE2 = "/gr"
SlashCmdList.GOODRANGE = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "stats" then
    printStats()
  elseif msg == "reset" then
    T.est:resetStats()
    say("stats cleared")
  elseif msg == "list" then
    printList()
  elseif msg == "" or msg == "config" or msg == "options" then
    ns.OpenOptions()
  else
    say("/goodrange (or /gr) opens the options.  /gr stats | reset | list")
  end
end

-- Settings > Zones: on Auto the zones and their colours come from your class and spells, as
-- before; off, your own zones in a row (list, see Zones.partition) and colours
local function zoneSettings(z)
  if type(z) ~= "table" or z.auto == nil or (not z.auto and type(z.list) ~= "table") then
    return { auto = true }   -- also a test build's settings, one per zone
  end
  return z
end

-- Your own zones are your class's (on Retail, your spec's): db.zonesBy[key], with db.zones the
-- current one (not saved itself, see PLAYER_LOGOUT). nil on Retail until the game knows your spec.
local function zoneKey()
  if not RETAIL then return playerClass end
  local spec = API.SpecID()
  return spec and playerClass .. "-" .. spec
end
-- Points db.zones at your class's or spec's zones; true if that changed.
function ns.UseZones()
  local key = zoneKey()
  local was = db.zones
  if key then
    -- the zones v0.8 kept for every character go to the first class (or spec) to log in
    if db.zonesBy[key] == nil and db.zonesOld then db.zonesBy[key], db.zonesOld = db.zonesOld, nil end
    db.zonesBy[key] = zoneSettings(db.zonesBy[key])
    db.zones = db.zonesBy[key]
  elseif not db.zones then
    db.zones = zoneSettings()   -- Auto until the spec is known, not saved
  end
  return was ~= db.zones
end

-- Reset Defaults: where the display is (screen, badge, nameplate offsets), its sizes, font,
-- colours and zones
local RESET = { "width", "height", "fontSize", "ppy", "badgeScale", "font", "plateX", "plateY", "focusScale" }
function ns.ResetDefaults()
  db.pos, db.badgePos, db.focusPos = nil, nil, nil
  db.colors = {}
  local key = zoneKey()
  if key then db.zonesBy[key] = nil end
  db.zones, db.zonesOld = nil, nil
  ns.UseZones()
  for _, k in ipairs(RESET) do db[k] = ns.DEFAULTS[k] end
  ns.OnZonesChanged()
  ns.ApplyLayout()
end

-- Events ------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
-- talents and gear can change spell ranges: rebuild the zones then (and once the world is in,
-- when the talents are surely known)
for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED",
                    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_FOCUS_CHANGED",
                    "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN",
                    "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "UPDATE_MOUSEOVER_UNIT",
                    "PLAYER_LOGOUT" }) do
  pcall(events.RegisterEvent, events, e)   -- not every client has every event
end
-- what you can use may have changed: the zones are checked again on the next tick (see zoneGen)
local USABLE = { SPELL_UPDATE_USABLE = true, ACTIONBAR_UPDATE_USABLE = true, SPELL_UPDATE_COOLDOWN = true,
  UPDATE_SHAPESHIFT_FORM = true, PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true }
events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
events:SetScript("OnEvent", function(_, event)
  if USABLE[event] then
    zoneGen = zoneGen + 1
    if event ~= "PLAYER_REGEN_DISABLED" and event ~= "PLAYER_REGEN_ENABLED" then return end
  end
  if event == "PLAYER_LOGIN" then
    GoodRangeDB = GoodRangeDB or {}
    db = GoodRangeDB
    if (db.layoutVersion or 1) < 2 then
      -- v2: 20% smaller tape, placed above the character
      db.width, db.height, db.fontSize, db.ppy, db.pos = nil, nil, nil, nil, nil
      db.layoutVersion = 2
    end
    if db.layoutVersion < 3 then
      db.font = nil   -- v3: Changa Bold by default
      db.layoutVersion = 3
    end
    if db.layoutVersion < 5 then
      -- v5: one display switch; the zone strip and the testing switches are gone
      if db.tape == false then db.display = "label" end
      db.tape, db.strip, db.details, db.log = nil, nil, nil, nil
    end
    if db.layoutVersion < 4 then
      -- v4: Andrii's sizes as the defaults; metres and the position switch are gone
      db.width, db.height, db.fontSize, db.ppy = nil, nil, nil, nil
      db.meters, db.noPos = nil, nil
    end
    db.layoutVersion = 5
    if db.enemy ~= nil then
      -- v0.8: one switch for every enemy, now players and NPCs apart
      db.enemyPlayers, db.enemyNPCs, db.enemy = db.enemy, db.enemy, nil
    end
    for k, v in pairs(ns.DEFAULTS) do
      if db[k] == nil then db[k] = v end
    end
    db.ppy = math.min(40, math.max(10, db.ppy))   -- the ruler scale runs 10-40 now (was 15-100)
    db.colors = db.colors or {}   -- zone colours you picked, { kind = { r, g, b } }
    if not db.zonesBy then db.zonesBy, db.zonesOld = {}, db.zones end   -- v0.8: one set for all
    db.zones = nil
    ns.UseZones()
    db.maxRange = nil   -- an unreleased test build's setting, now the zones' To
    ns.db = db
    db.unlocked = false   -- the tape is only unlocked while the settings window is open
    build()
    ns.CreateOptions()
    ns.InitMinimap(db)
    ns.ApplyLayout()
  elseif not db then
    return
  elseif event == "PLAYER_TARGET_CHANGED" then
    T.est:reset()
    goal, shown, noData, goalRate = nil, nil, false, 0
    helpable.target = nil
    ns.ForgetBracket(T)
    if UnitExists("target") then
      local hostile = UnitCanAttack("player", "target")
      hostileTarget = issecret(hostile) or hostile
      refreshZones()
      tape:SetZones(zoneAt)
    end
    ns.RefreshShown()
    if db.nameplate or db.unlocked then place(); placeFocus() end
  elseif event == "PLAYER_FOCUS_CHANGED" then
    forgetLabel(focusL)
    ns.RefreshShown()
    if db.nameplate then placeFocus() end
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    ns.RefreshShown()
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    -- a new unit under the mouse: start over
    if mouseOn then
      mouseRoot:Hide()
      forgetLabel(mouseL)
    end
    ns.RefreshShown()
  elseif event == "PLAYER_LOGOUT" then
    db.zones = nil   -- only the current class's entry in zonesBy, which is saved
  elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
    if db.nameplate then placeSoon() end
  else
    rebuildSoon()
  end
end)

-- A target that dies stays targeted; hide the tape then.
C_Timer.NewTicker(0.5, function() if db then ns.RefreshShown() end end)
