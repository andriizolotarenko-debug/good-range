-- Good Range: distance to the target from range checks, shown on a sliding range tape or as a
-- number with a zone badge. Colours come from your class zones: blue melee, green shoot / cast /
-- heal, red dead zone, grey out of range.
local _, ns = ...

local issecret = issecretvalue or function() return false end
local API = ns.API
-- ~30 ticks a second: each checks only the two steps around the distance (see measure), so a
-- crossing is timed to a tick; the display carries the estimate on between ticks.
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
  inCombat = true, outOfCombat = true, friendly = true, enemy = true,
  unlocked = false, nameplate = false, plateX = 0, plateY = 2,
  focus = false, focusScale = 100,
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

-- true / false / nil (unknown) for one range step, and what gave the answer (for /gr list).
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
        return false, "min " .. m[1]
      elseif v == false and within(g, m[2], unit, restricted) then
        return true, "min- " .. m[1]
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
      return v, (v and "spell " or "spell- ") .. id
    end
  end
  return nil
end

-- A tracker follows one unit (the target, the focus): its last bracket, when its steps were last
-- scanned, and its distance estimate.
local function newTracker(unit)
  return { unit = unit, est = Estimator.new(), res = {}, lastLo = 0 }
end
local T, F = newTracker("target"), newTracker("focus")

-- lo: the largest step reported out (below hi), hi: the smallest step reported in.
local function scan(tr, hostile, restricted, from, to)
  local hi, hiI
  local res = tr.res
  for i = from, to do
    local g = groups[i]
    local r, why = check(g, tr.unit, hostile, restricted)
    res[i] = r
    if tr == T then g.result, g.last = r, why end   -- what /gr list shows
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

-- tr: the tracker to forget, or nil for both (the steps changed)
function ns.ForgetBracket(tr)
  for _, t in ipairs(tr and { tr } or { T, F }) do
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
  tr.nextFull = now + FULL_EVERY
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
  tr.lastScan, tr.nextWindow = now, now + WINDOW_EVERY
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

local _, playerClass = UnitClass("player")
local RETAIL = interface >= 100000

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
-- against an enemy or a friend (unit: whose heal / buff reach to check).
local function zonesFor(hostile, unit)
  local ctx = {
    class = playerClass, hostile = hostile, known = spellbook.known, generic = spellbook.generic,
    getInfo = API.GetSpellInfo, usable = API.IsUsable, ready = API.IsReady,
    form = playerClass == "DRUID" and API.Form() or nil,
    mainTree = (playerClass == "SHAMAN" or playerClass == "PALADIN") and API.MainTree() or nil,
    primaryRole = RETAIL and API.SpecRole() or nil,
  }
  if not hostile and not canHelp(unit) then return FRIEND_ONLY, {}, ctx end
  local new, diag = ns.Zones.build(ctx)
  if hostile and db then new = ns.Zones.custom(new, db.zones) end
  return new, diag, ctx
end

-- Rebuilds the target's zones; true if they changed.
local function refreshZones()
  local new, diag, ctx = zonesFor(hostileTarget, "target")
  ns.diag = { class = playerClass, form = ctx.form, mainTree = ctx.mainTree, spells = diag }
  local parts = {}
  for _, sp in ipairs(new) do parts[#parts + 1] = table.concat(sp, ",") end
  if new.noGap then parts[#parts + 1] = "no gap" end
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
local targetOn, focusOn = false, false   -- which units are followed (see RefreshShown)
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
  ns.Tape.SetColors(db.colors)
  tape:SetLayout(db.width, db.height, db.fontSize, db.ppy, db.font, db.display, db.badgeScale / 100)
  focusLabel:SetLayout(db.focusScale / 100, ns.DEFAULTS.font)
  ns.RefreshShown()
  place()
  placeFocus()
end

-- Tick: estimation at 20 Hz on a hidden driver frame -----------------------------------------

local goal, goalLabel        -- what the tape slides towards (display units) and its label
local goalRate, goalLo, goalHi, sinceTick = 0, 0, nil, 0   -- how goal moves on between ticks
local noData = false         -- no range check answered (the game hides them, e.g. secret values)
local shown                  -- what the tape shows now
local acc, clock = 0, 0
local ZONE_EVERY = 0.25    -- s between checks of what you can use (rage, form, cooldowns ...)
local zoneClock = 0
local focusSpans, focusHostile, focusZoneClock = {}, nil, 0

-- One tick of a tracker: its bracket, then its estimate. ps: your speed, px / py: your position.
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

-- The focus: its own zones (it can be a friend while the target is an enemy) and the label.
local function followFocus(dt, ps, px, py)
  if not UnitExists("focus") or UnitIsDeadOrGhost("focus") then return end
  local hostile = UnitCanAttack("player", "focus")
  if issecret(hostile) then hostile = true end
  focusZoneClock = focusZoneClock + dt
  if hostile ~= focusHostile or focusZoneClock >= ZONE_EVERY then
    focusHostile, focusZoneClock = hostile, 0
    focusSpans = zonesFor(hostile, "focus")
  end
  local lo, hi, b = follow(F, hostile, dt, ps, px, py)
  if not hi and lo == 0 then
    focusLabel:SetNoData()
    return
  end
  local d = b or lo
  -- whole yards, "+" past the last step that answered, never wider than "99+"
  local text = d >= 99 and "99+" or b and tostring(math.floor(b)) or math.floor(lo) .. "+"
  focusLabel:Set(text, (ns.Zones.at(d, focusSpans)))
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + elapsed
  if acc < TICK then return end
  local dt = acc
  acc = 0
  clock = clock + dt
  local ps = speedOf("player")
  if ps == nil and IsPlayerMoving then
    -- the game hides speeds in dungeons: moving or not is enough to start and stop the estimate
    local m = IsPlayerMoving()
    if not issecret(m) then ps = m and Estimator.RUN or 0 end
  end
  local px, py = playerPos()
  if focusOn then followFocus(dt, ps, px, py) end

  local unit = "target"
  if not targetOn or not UnitExists(unit) or UnitIsDeadOrGhost(unit) then return end
  local hostile = UnitCanAttack("player", unit)
  if issecret(hostile) then hostile = true end
  zoneClock = zoneClock + dt
  if hostile ~= hostileTarget or zoneClock >= ZONE_EVERY then
    hostileTarget = hostile
    zoneClock = 0
    if refreshZones() then tape:SetZones(zoneAt) end
  end

  local was = goal
  local lo, hi, b, crossed = follow(T, hostile, dt, ps, px, py)

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

-- Followed if living and the options allow it in this state (combat, unit kind).
-- Never friendly NPCs; friendly players in grey unless you can heal or buff them (see zonesFor).
local function wanted(unit)
  local has = UnitExists(unit) and not UnitIsDeadOrGhost(unit)
  if has and db then
    local fighting = UnitAffectingCombat("player")
    local hostile = UnitCanAttack("player", unit)
    if issecret(hostile) then hostile = true end
    local player = UnitIsPlayer(unit)
    if issecret(player) then player = true end
    if fighting and not db.inCombat or not fighting and not db.outOfCombat
        or hostile and not db.enemy or not hostile and not db.friendly
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
  -- a unit shown or hidden now (combat, a heal learned ...) may gain or lose its nameplate spot
  if db and db.nameplate and (was ~= targetOn or wasFocus ~= focusOn) then placeSoon() end
  driver:SetShown(targetOn or focusOn)
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
    print(("  %3d yd  %s  %s  %s"):format(g.range, r, table.concat(parts, ", "), g.last or ""))
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

-- Settings > Zones: on Auto every zone comes from your spells, as before
local ZONES = {
  primary = { auto = true, from = 0, to = 30 },
  secondary = { auto = true, from = 0, to = 5 },
  dead = { show = true, auto = true, from = 5, to = 8 },
}
local function zoneSettings(z)
  z = z or {}
  for kind, d in pairs(ZONES) do
    z[kind] = z[kind] or {}
    for k, v in pairs(d) do
      if z[kind][k] == nil then z[kind][k] = v end
    end
  end
  return z
end

-- Reset Defaults: where the display is (screen, badge, nameplate offsets), its sizes, font,
-- colours and zones
local RESET = { "width", "height", "fontSize", "ppy", "badgeScale", "font", "plateX", "plateY", "focusScale" }
function ns.ResetDefaults()
  db.pos, db.badgePos, db.focusPos = nil, nil, nil
  db.colors = {}
  for _, z in pairs(db.zones) do wipe(z) end   -- in place: the settings window holds them
  zoneSettings(db.zones)
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
-- talents and gear can change spell ranges: rebuild the zones then
for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED",
                    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_FOCUS_CHANGED" }) do
  pcall(events.RegisterEvent, events, e)   -- not every client has every event
end
events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
events:SetScript("OnEvent", function(_, event)
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
    for k, v in pairs(ns.DEFAULTS) do
      if db[k] == nil then db[k] = v end
    end
    db.ppy = math.min(40, math.max(10, db.ppy))   -- the ruler scale runs 10-40 now (was 15-100)
    db.colors = db.colors or {}   -- zone colours you picked, { kind = { r, g, b } }
    db.zones = zoneSettings(db.zones)
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
    F.est:reset()
    helpable.focus, focusHostile = nil, nil
    ns.ForgetBracket(F)
    focusLabel:Clear()
    ns.RefreshShown()
    if db.nameplate then placeFocus() end
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    ns.RefreshShown()
  elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
    if db.nameplate then placeSoon() end
  else
    rebuildSoon()
  end
end)

-- A target that dies stays targeted; hide the tape then.
C_Timer.NewTicker(0.5, function() if db then ns.RefreshShown() end end)
