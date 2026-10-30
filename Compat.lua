-- One face for the spell and item APIs across clients: Retail and WoW: Forever have C_Spell /
-- C_SpellBook, the Classic clients (Anniversary) may only have the old global functions.
local _, ns = ...

local API = {}
ns.API = API

local OldGetSpellInfo = GetSpellInfo

-- Spell info by ID, kept until the spells change (API.ForgetSpells): looking it up makes a new
-- table each time, and range checks on the Classic clients look up the name on every check.
local infoCache = {}

function API.ForgetSpells()
  wipe(infoCache)
end

-- { name, minRange, maxRange } or nil
function API.GetSpellInfo(id)
  local info = infoCache[id]
  if info ~= nil then return info or nil end
  if C_Spell and C_Spell.GetSpellInfo then
    info = C_Spell.GetSpellInfo(id)
  else
    local name, _, _, _, minRange, maxRange = OldGetSpellInfo(id)
    info = name and { name = name, minRange = minRange, maxRange = maxRange }
  end
  infoCache[id] = info or false
  return info or nil
end

local function spellName(id)
  local info = API.GetSpellInfo(id)
  return info and info.name
end

-- true / false / nil (no answer)
function API.IsSpellInRange(id, unit)
  if C_Spell and C_Spell.IsSpellInRange then return C_Spell.IsSpellInRange(id, unit) end
  local name = spellName(id)
  local r = name and IsSpellInRange(name, unit)
  if r == 1 or r == true then return true end
  if r == 0 or r == false then return false end
  return nil
end

function API.IsSpellHarmful(id)
  if C_Spell and C_Spell.IsSpellHarmful then return C_Spell.IsSpellHarmful(id) end
  local name = spellName(id)
  return name and IsHarmfulSpell(name) and true or false
end

function API.IsSpellHelpful(id)
  if C_Spell and C_Spell.IsSpellHelpful then return C_Spell.IsSpellHelpful(id) end
  local name = spellName(id)
  return name and IsHelpfulSpell(name) and true or false
end

-- Raw answer; the caller treats anything but true / 1 as "out" (LibRangeCheck does the same).
function API.IsItemInRange(item, unit)
  if C_Item and C_Item.IsItemInRange then return C_Item.IsItemInRange(item, unit) end
  return IsItemInRange(item, unit)
end

-- Spell IDs of the active, non-passive spells in your spellbook.
function API.Spellbook()
  local out = {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      if info and not info.shouldHide then
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
          if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive
              and not item.isOffSpec and item.spellID then
            out[#out + 1] = item.spellID
          end
        end
      end
    end
    if #out > 0 or not GetNumSpellTabs then return out end
  end
  local book = BOOKTYPE_SPELL or "spell"
  for tab = 1, GetNumSpellTabs() do
    local _, _, offset, count = GetSpellTabInfo(tab)
    for i = offset + 1, offset + count do
      local kind, id = GetSpellBookItemInfo(i, book)
      if kind == "SPELL" and id and not IsPassiveSpell(i, book) then out[#out + 1] = id end
    end
  end
  return out
end

-- CreateFrame with the first template this client knows.
function API.CreateFrameFrom(kind, name, parent, templates)
  for _, t in ipairs(templates) do
    local ok, f = pcall(CreateFrame, kind, name, parent, t)
    if ok and f then return f, t end
  end
  return CreateFrame(kind, name, parent)
end

-- Vertical alpha gradient (new colour-object form, or the old one on older clients).
function API.VerticalAlpha(tex, bottom, top)
  local ok = CreateColor and pcall(tex.SetGradient, tex, "VERTICAL",
    CreateColor(0, 0, 0, bottom), CreateColor(0, 0, 0, top))
  if not ok and tex.SetGradientAlpha then
    tex:SetGradientAlpha("VERTICAL", 0, 0, 0, bottom, 0, 0, 0, top)
  end
end

local issecret = issecretvalue or function() return false end

-- Can you use the spell right now? -> usable, short of power (rage / mana / energy)
function API.IsUsable(id)
  local ok, noPower
  if C_Spell and C_Spell.IsSpellUsable then
    ok, noPower = C_Spell.IsSpellUsable(id)
  elseif IsUsableSpell then
    ok, noPower = IsUsableSpell(id)
  else
    return true, false
  end
  if issecret(ok) or issecret(noPower) then return true, false end
  return ok and true or false, noPower and true or false
end

-- Off cooldown (the global cooldown does not count)?
function API.IsReady(id)
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local c = C_Spell.GetSpellCooldown(id)
    if c then start, duration = c.startTime, c.duration end
  elseif GetSpellCooldown then
    start, duration = GetSpellCooldown(id)
  end
  if not start or issecret(start) or issecret(duration) then return true end
  if start == 0 or duration <= 1.5 then return true end
  return start + duration - GetTime() <= 0.2
end

-- Druid form: "cat", "bear", "moonkin", "travel", "aquatic", "flight", "tree" or nil (caster).
local FORMS = { [1] = "cat", [2] = "tree", [3] = "travel", [4] = "aquatic", [5] = "bear", [8] = "bear",
  [27] = "flight", [29] = "flight", [31] = "moonkin" }
function API.Form()
  local id = GetShapeshiftFormID and GetShapeshiftFormID()
  return id and FORMS[id] or nil
end

-- The talent tree with the most points (Classic clients), or nil.
function API.MainTree()
  if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
  local best, bestPoints = nil, 0
  for i = 1, GetNumTalentTabs() do
    -- newer clients: id, name, description, icon, pointsSpent ...; older: name, icon, pointsSpent ...
    local _, _, a, _, b = GetTalentTabInfo(i)
    local points = type(b) == "number" and b or type(a) == "number" and a or 0
    if points > bestPoints then best, bestPoints = i, points end
  end
  return best
end

-- Retail: "melee" or "ranged" from your specialization, or nil for any other spec (the
-- starting specs of new characters, specs added later): then your class decides.
local SPEC_ROLE = {}
for _, id in ipairs({ 71, 72, 73, 259, 260, 261, 250, 251, 252, 66, 70, 268, 269, 577, 581,
  103, 104, 263, 255 }) do SPEC_ROLE[id] = "melee" end
for _, id in ipairs({ 62, 63, 64, 65, 102, 105, 253, 254, 256, 257, 258, 262, 264, 265, 266,
  267, 270, 1467, 1468, 1473, 1480 }) do SPEC_ROLE[id] = "ranged" end
-- Your specialization's ID, or nil.
function API.SpecID()
  if not (GetSpecialization and GetSpecializationInfo) then return nil end
  local index = GetSpecialization()
  local id = index and not issecret(index) and GetSpecializationInfo(index)
  if not id or issecret(id) then return nil end
  return id
end

function API.SpecRole()
  local id = API.SpecID()
  return id and SPEC_ROLE[id]
end
