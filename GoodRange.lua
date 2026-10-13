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
}

local db
local est = ns.Estimator.new()
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
      -- A spell with a minimum range says "false" up close too, so it can't bound the bracket.
      if max > 0 and min == 0 then table.insert(group(max).spells, id) end
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
    if not g.harmItem and not g.friendItem and not g.interact and #g.spells == 0 then
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

-- true / false / nil (unknown) for one range step.
local function check(g, unit, hostile, restricted)
  local item = hostile and g.harmItem or g.friendItem
  if item and not restricted then
    local v = API.IsItemInRange(item, unit)
    if issecret(v) then
      secrets.item = secrets.item + 1
    else
      local inRange = v == true or v == 1
      g.last = inRange and "item" or "item-"
      return inRange
    end
  end
  if g.interact and not restricted then
    local v = CheckInteractDistance(unit, g.interact)
    if not issecret(v) then
      g.last = v and "interact" or "interact-"
      return v and true or false
    end
  end
  for _, id in ipairs(g.spells) do
    local v = API.IsSpellInRange(id, unit)
    if issecret(v) then
      secrets.spell = secrets.spell + 1
    elseif v ~= nil then
      g.last = (v and "spell " or "spell- ") .. id
      return v
    end
  end
  g.last = nil
  return nil
end

-- lo: the largest step reported out (below hi), hi: the smallest step reported in.
local function scan(unit, hostile, restricted, from, to)
  local hi, hiI
  for i = from, to do
    local g = groups[i]
    local r = check(g, unit, hostile, restricted)
    g.result = r
    if r == true and not hi then hi, hiI = g.range, i end
  end
  local lo, loI = 0, nil
  for i = from, to do
    local g = groups[i]
    if g.result == false and (not hi or g.range < hi) and g.range > lo then lo, loI = g.range, i end
  end
  return lo, hi, loI, hiI
end

-- Checking every step is the expensive part. Each tick only the two steps bounding the last
-- bracket (its edges) are checked, so a crossing is timed to the frame. The steps around them are
-- scanned as soon as an edge changes and every WINDOW_EVERY s; all steps every FULL_EVERY s, on a
-- new target, and whenever the answer could lie outside that window. No scan comes sooner than
-- SCAN_MIN s after the last one, so steps that give no answer can't make it scan every frame.
local WINDOW_EVERY, FULL_EVERY, SCAN_MIN = 0.2, 0.5, 0.05
local nextWindow, nextFull, lastScan, loIdx, hiIdx = 0, 0, -1, nil, nil
local lastLo, lastHi = 0, nil

function ns.ForgetBracket()
  nextWindow, nextFull, lastScan, loIdx, hiIdx = 0, 0, -1, nil, nil
end

-- the steps around the last bracket, or all of them
local function rescan(unit, hostile, restricted, now)
  local n = #groups
  local lo, hi, loI, hiI
  if now < nextFull and (loIdx or hiIdx) then
    local from = math.max(1, (loIdx or 1) - 1)
    local to = math.min(n, (hiIdx or n) + 1)
    lo, hi, loI, hiI = scan(unit, hostile, restricted, from, to)
    local outside = (not hi and to < n) or (hiI == from and from > 1) or (not loI and from > 1)
    if not outside then
      loIdx, hiIdx = loI, hiI
      return lo, hi
    end
  end
  lo, hi, loI, hiI = scan(unit, hostile, restricted, 1, n)
  loIdx, hiIdx = loI, hiI
  nextFull = now + FULL_EVERY
  return lo, hi
end

local function measure(unit, hostile, now)
  local restricted = InCombatLockdown() and not hostile
  if (loIdx or hiIdx) and now < nextWindow
      and (not loIdx or check(groups[loIdx], unit, hostile, restricted) == false)
      and (not hiIdx or check(groups[hiIdx], unit, hostile, restricted) == true) then
    return lastLo, lastHi   -- both edges as they were
  end
  if now - lastScan < SCAN_MIN then return lastLo, lastHi end
  lastScan, nextWindow = now, now + WINDOW_EVERY
  lastLo, lastHi = rescan(unit, hostile, restricted, now)
  return lastLo, lastHi
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

-- Rebuilds the zones from what you can use right now (form, rage / mana, cooldowns, weapon,
-- combat); true if they changed.
local function refreshZones()
  local ctx = {
    class = playerClass, hostile = hostileTarget, known = spellbook.known, generic = spellbook.generic,
    getInfo = API.GetSpellInfo, usable = API.IsUsable, ready = API.IsReady,
    form = playerClass == "DRUID" and API.Form() or nil,
    mainTree = (playerClass == "SHAMAN" or playerClass == "PALADIN") and API.MainTree() or nil,
    primaryRole = RETAIL and API.SpecRole() or nil,
  }
  local new, diag = ns.Zones.build(ctx)
  ns.diag = { class = playerClass, form = ctx.form, mainTree = ctx.mainTree, spells = diag }
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
root:SetScript("OnDragStart", function(self) if not plate then self:StartMoving() end end)
root:SetScript("OnDragStop", function(self)
  if plate then return end
  self:StopMovingOrSizing()
  local point, _, rel, x, y = self:GetPoint()
  db.pos = { point, rel, x, y }
end)
root:Hide()

-- the label's badge drags on its own; once dragged it stays where it was put, wherever the number goes
local badge = tape.badge
badge:SetMovable(true)
badge:SetClampedToScreen(true)
badge:RegisterForDrag("LeftButton")
badge:SetScript("OnDragStart", function(self) if not plate then self:StartMoving() end end)
badge:SetScript("OnDragStop", function(self)
  if plate then return end
  self:StopMovingOrSizing()
  local point, _, rel, x, y = self:GetPoint()
  db.badgePos = { point, rel, x, y }
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

-- Over the target's nameplate when that option is on and the target has one; otherwise (nameplates
-- off, the target too far or off screen) where it was put on the screen.
local function place()
  plate = db.nameplate and C_NamePlate and C_NamePlate.GetNamePlateForUnit
    and C_NamePlate.GetNamePlateForUnit("target") or nil
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
  if plate then tape.hint:SetText("Over the target's nameplate: move it with the nameplate offset sliders.") end
end

-- nameplates come and go as the target walks in and out of view: place again once they settle
local placePending
local function placeSoon()
  if placePending then return end
  placePending = true
  C_Timer.After(0, function() placePending = false; place() end)
end

tape:SetZones(zoneAt)
function ns.OnZonesChanged()
  refreshZones()
  tape:SetZones(zoneAt)
end

function ns.ApplyLayout()
  if not db then return end
  tape:SetLayout(db.width, db.height, db.fontSize, db.ppy, db.font, db.display, db.badgeScale / 100)
  place()
  ns.RefreshShown()
end

-- Tick: estimation at 20 Hz on a hidden driver frame -----------------------------------------

local goal, goalLabel        -- what the tape slides towards (display units) and its label
local goalRate, goalLo, goalHi, sinceTick = 0, 0, nil, 0   -- how goal moves on between ticks
local noData = false         -- no range check answered (the game hides them, e.g. secret values)
local shown                  -- what the tape shows now
local acc, clock = 0, 0
local ZONE_EVERY = 0.25    -- s between checks of what you can use (rage, form, cooldowns ...)
local zoneClock = 0
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + elapsed
  if acc < TICK then return end
  local dt = acc
  acc = 0
  clock = clock + dt
  local unit = "target"
  if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then return end
  local hostile = UnitCanAttack("player", unit)
  if issecret(hostile) then hostile = true end
  zoneClock = zoneClock + dt
  if hostile ~= hostileTarget or zoneClock >= ZONE_EVERY then
    hostileTarget = hostile
    zoneClock = 0
    if refreshZones() then tape:SetZones(zoneAt) end
  end

  local lo, hi = measure(unit, hostile, clock)
  local ts = speedOf(unit)
  local ps = speedOf("player")
  if ps == nil and IsPlayerMoving then
    -- the game hides speeds in dungeons: moving or not is enough to start and stop the estimate
    local m = IsPlayerMoving()
    if not issecret(m) then ps = m and Estimator.RUN or 0 end
  end
  -- combined speed; nil (unknown) unless both are known, or you move and the target's is hidden
  -- (counted as standing then, as before). Standing with the target's hidden is unknown: the
  -- estimate then moves only once a crossing shows the target does.
  local sp = ps and ts and ps + ts or ps and ps > 0.05 and ps or nil
  local px, py = playerPos()
  -- An unknown target speed counts as standing; the next crossing corrects a wrong guess.
  local was = goal
  local crossed = est:update(clock, dt, lo, hi, sp, px, py, not ts or ts < 0.1)
  local b = est:valueB(lo, hi)

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

-- Can one of your heals or buffs go on this unit? (A spell that can't target it, like Mend Pet
-- on a player, gives no range answer at all.) Checked once per target.
local canHelpTarget
local function canHelp(unit)
  if canHelpTarget == nil then
    canHelpTarget = false
    for _, id in ipairs(spellbook.helpIds or {}) do
      local v = API.IsSpellInRange(id, unit)
      if not issecret(v) and v ~= nil then
        canHelpTarget = true
        break
      end
    end
  end
  return canHelpTarget
end

-- Shown for a living target, if the options allow it in this state (combat, target kind).
-- Never for friendly NPCs; for friendly players only if you can heal or buff them.
function ns.RefreshShown()
  local has = UnitExists("target") and not UnitIsDeadOrGhost("target")
  if has and db then
    local fighting = UnitAffectingCombat("player")
    local hostile = UnitCanAttack("player", "target")
    if issecret(hostile) then hostile = true end
    local player = UnitIsPlayer("target")
    if issecret(player) then player = true end
    if fighting and not db.inCombat or not fighting and not db.outOfCombat
        or hostile and not db.enemy or not hostile and not db.friendly
        or not hostile and (not player or not canHelp("target")) then
      has = false
    end
  end
  driver:SetShown(has)
  root:SetShown(has or (db and db.unlocked))
end

-- Commands ----------------------------------------------------------------------------------

local function printStats()
  local s = est.stats
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
    est:resetStats()
    say("stats cleared")
  elseif msg == "list" then
    printList()
  elseif msg == "" or msg == "config" or msg == "options" then
    ns.OpenOptions()
  else
    say("/goodrange (or /gr) opens the options.  /gr stats | reset | list")
  end
end

function ns.ResetPosition()
  db.pos, db.badgePos = nil, nil
  db.plateX, db.plateY = ns.DEFAULTS.plateX, ns.DEFAULTS.plateY
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
                    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
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
    ns.db = db
    db.unlocked = false   -- the tape is only unlocked while the settings window is open
    build()
    ns.CreateOptions()
    ns.InitMinimap(db)
    ns.ApplyLayout()
  elseif not db then
    return
  elseif event == "PLAYER_TARGET_CHANGED" then
    est:reset()
    goal, shown, noData, goalRate = nil, nil, false, 0
    canHelpTarget = nil
    ns.ForgetBracket()
    if UnitExists("target") then
      local hostile = UnitCanAttack("player", "target")
      hostileTarget = issecret(hostile) or hostile
      refreshZones()
      tape:SetZones(zoneAt)
    end
    if db.nameplate then place() end
    ns.RefreshShown()
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
