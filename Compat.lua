-- One face for the spell and item APIs across clients: Retail and WoW: Forever have C_Spell /
-- C_SpellBook, the Classic clients (Anniversary) may only have the old global functions.
local _, ns = ...

local API = {}
ns.API = API

local OldGetSpellInfo = GetSpellInfo

-- { name, minRange, maxRange } or nil
function API.GetSpellInfo(id)
  if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(id) end
  local name, _, _, _, minRange, maxRange = OldGetSpellInfo(id)
  if not name then return nil end
  return { name = name, minRange = minRange, maxRange = maxRange }
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
