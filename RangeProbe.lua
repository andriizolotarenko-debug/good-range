-- Range Probe: distance to the target from range checks, shown on a sliding range tape or as a
-- number with a zone badge. Colours come from your class zones: blue melee, green shoot / cast /
-- heal, red dead zone, grey out of range.
local _, ns = ...

local issecret = issecretvalue or function() return false end
local API = ns.API
local TICK = 0.05
local MELEE = ns.Zones.MELEE

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
  width = 130, height = 31, fontSize = 32, ppy = 20, display = "tape",
  font = "Interface\\AddOns\\RangeProbe\\media\\Changa-Bold.ttf",
  inCombat = true, outOfCombat = true, friendly = true, enemy = true,
  unlocked = false,
}

local db
local est = ns.Estimator.new()
local groups = {}        -- ascending by range: { range, harmItem, friendItem, interact, spells }
local zones = { harm = {}, help = {} }   -- work intervals { {a, b}, ... } per target kind
local secrets = { spell = 0, item = 0, speed = 0 }

local function say(msg) print("|cff66ccffRange Probe|r " .. msg) end

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

  local harmWork, helpWork, known = {}, {}, {}
  for _, id in ipairs(API.Spellbook()) do
    local info = API.GetSpellInfo(id)
    if info then
      known[info.name] = id
      local min, max = info.minRange or 0, info.maxRange or 0
      -- A spell with a minimum range says "false" up close too, so it can't bound the bracket.
      if max > 0 and min == 0 then table.insert(group(max).spells, id) end
      -- Fallback zones for classes / clients the list in Zones.lua does not cover.
      local harmful, helpful = API.IsSpellHarmful(id), API.IsSpellHelpful(id)
      if harmful and max > MELEE then
        harmWork[#harmWork + 1] = { min, max }
      elseif helpful and max > 0 then
        helpWork[#helpWork + 1] = { min, max }
      end
    end
  end
  -- Zones: your class's key abilities at the ranges the game reports for you.
  local _, class = UnitClass("player")
  local list = ns.Zones.CLASS[class] or {}
  zones.harm = ns.Zones.fromList(list.harm, known, API.GetSpellInfo) or ns.Zones.merge(harmWork)
  zones.help = ns.Zones.fromList(list.help, known, API.GetSpellInfo) or ns.Zones.merge(helpWork)

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

-- Checking every step is the expensive part, so between full scans only the steps around the
-- last bracket are checked. A full scan runs every FULL_EVERY s, on a new target, and whenever
-- the answer could lie outside that window.
local FULL_EVERY = 0.5
local nextFull, loIdx, hiIdx = 0, nil, nil

function ns.ForgetBracket()
  nextFull, loIdx, hiIdx = 0, nil, nil
end

local function measure(unit, hostile, now)
  local restricted = InCombatLockdown() and not hostile
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

-- d in yd. Melee always wins up close.
local function zoneAt(d)
  return ns.Zones.at(d, hostileTarget and zones.harm or zones.help)
end

-- UI ----------------------------------------------------------------------------------------

local tape = ns.Tape.New(UIParent)
local root = tape.root
root:SetMovable(true)
root:SetClampedToScreen(true)
root:RegisterForDrag("LeftButton")
root:SetScript("OnDragStart", function(self) self:StartMoving() end)
root:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, rel, x, y = self:GetPoint()
  db.pos = { point, rel, x, y }
end)
root:Hide()

local function place()
  root:ClearAllPoints()
  if db.pos then
    root:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
  else
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 110)   -- roughly above the character
  end
end

tape:SetZones(zoneAt)
function ns.OnZonesChanged() tape:SetZones(zoneAt) end

function ns.ApplyLayout()
  if not db then return end
  tape:SetLayout(db.width, db.height, db.fontSize, db.ppy, db.font, db.display)
  tape:SetUnlocked(db.unlocked)
  ns.RefreshShown()
end

-- Tick: estimation at 20 Hz on a hidden driver frame -----------------------------------------

local goal, goalLabel        -- what the tape slides towards (display units) and its label
local shown                  -- what the tape shows now
local acc, clock = 0, 0
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
  if hostile ~= hostileTarget then
    hostileTarget = hostile
    tape:SetZones(zoneAt)
  end

  local lo, hi = measure(unit, hostile, clock)
  local ts = speedOf(unit)
  local sp = (speedOf("player") or 0) + (ts or 0)
  local px, py = playerPos()
  -- An unknown target speed counts as standing; the next crossing corrects a wrong guess.
  est:update(clock, dt, lo, hi, sp, px, py, not ts or ts < 0.1)
  local b = est:valueB(lo, hi)

  if b then
    goal = b
    goalLabel = tostring(math.floor(goal))
  else
    goal = lo
    goalLabel = math.floor(goal) .. "+"
  end

end)

-- Drawing: every frame, the tape glides towards the latest estimate.
root:SetScript("OnUpdate", function(_, elapsed)
  if not goal then
    if not db.unlocked then return end
    goal, goalLabel = 21.4, "21"   -- sample while unlocked
  end
  if shown == goal then return end
  shown = shown and shown + (goal - shown) * math.min(1, elapsed * 14) or goal
  if math.abs(goal - shown) < 0.002 then shown = goal end
  tape:Draw(shown, goalLabel ~= tostring(math.floor(goal)) and goalLabel or tostring(math.floor(shown)))
end)

-- Shown for a living target, if the options allow it in this state (combat, target kind).
function ns.RefreshShown()
  local has = UnitExists("target") and not UnitIsDeadOrGhost("target")
  if has and db then
    local fighting = UnitAffectingCombat("player")
    local hostile = UnitCanAttack("player", "target")
    if issecret(hostile) then hostile = true end
    if fighting and not db.inCombat or not fighting and not db.outOfCombat
        or hostile and not db.enemy or not hostile and not db.friendly then
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

local function zoneText(z)
  local parts = { "melee 0-" .. MELEE }
  for _, r in ipairs(z) do parts[#parts + 1] = ("work %g-%g"):format(r[1], r[2]) end
  return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function printList()
  say(("%d range steps. Secret results so far: spell %d, item %d, speed %d. Own position: %s.")
    :format(#groups, secrets.spell, secrets.item, secrets.speed, playerPos() and "yes" or "hidden"))
  say("zones on enemies: " .. zoneText(zones.harm) .. "; on friends: " .. zoneText(zones.help))
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

SLASH_RANGEPROBE1 = "/rp"
SlashCmdList.RANGEPROBE = function(msg)
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
    say("/rp opens the options.  /rp stats | reset | list")
  end
end

function ns.ResetPosition()
  db.pos = nil
  place()
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
for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
  pcall(events.RegisterEvent, events, e)   -- not every client has every event
end
events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    RangeProbeDB = RangeProbeDB or {}
    db = RangeProbeDB
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
    ns.db = db
    db.unlocked = false   -- the tape is only unlocked while the settings window is open
    place()
    build()
    ns.CreateOptions()
    ns.ApplyLayout()
  elseif not db then
    return
  elseif event == "PLAYER_TARGET_CHANGED" then
    est:reset()
    goal, shown = nil, nil
    ns.ForgetBracket()
    if UnitExists("target") then
      local hostile = UnitCanAttack("player", "target")
      hostileTarget = issecret(hostile) or hostile
      tape:SetZones(zoneAt)
    end
    ns.RefreshShown()
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    ns.RefreshShown()
  else
    rebuildSoon()
  end
end)

-- A target that dies stays targeted; hide the tape then.
C_Timer.NewTicker(0.5, function() if db then ns.RefreshShown() end end)
