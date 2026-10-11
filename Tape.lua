-- The range tape: a digital-compass style ruler that slides under a gold needle.
-- Ticks every 0.1 yd (taller every 0.5, tallest on whole yards) coloured by zone, a zone strip
-- under them, a backing that fades out upwards and to the sides, and the whole-yard value on top.
local _, ns = ...

local Tape = {}
Tape.__index = Tape
ns.Tape = Tape

local MEDIA = "Interface\\AddOns\\RangeProbe\\media\\"
local FONT = "Fonts\\FRIZQT__.TTF"
local SLICES = 28          -- backing plate columns (each a vertical gradient)
local BASE_H = 40          -- design height; tick sizes scale with height / BASE_H

Tape.COLORS = {
  melee = { 0.302, 0.659, 1 },
  work = { 0.373, 0.878, 0.416 },
  dead = { 0.545, 0.565, 0.6 },
}

local function fade(x, cx)
  local f = 1 - (math.abs(x - cx) / cx) ^ 2.2
  return f > 0 and f or 0
end

function Tape.New(parent)
  local self = setmetatable({ ticks = {}, strip = {}, plate = {}, value = 0 }, Tape)
  local root = CreateFrame("Frame", "RangeProbeTape", parent)
  root:SetFrameStrata("MEDIUM")
  self.root = root

  self.area = CreateFrame("Frame", nil, root)
  self.area:SetPoint("BOTTOMLEFT")
  self.area:SetPoint("BOTTOMRIGHT")

  self.number = root:CreateFontString(nil, "OVERLAY")
  self.unit = root:CreateFontString(nil, "OVERLAY")

  -- needle: head, stretched stem and tip, all sliced from one texture
  local function needlePart(top, bottom)
    local t = self.area:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetTexture(MEDIA .. "needle")
    t:SetTexCoord(0, 1, top / 16, bottom / 16)
    return t
  end
  self.head = needlePart(0, 9.5)
  self.stem = needlePart(9.5, 11)
  self.tip = needlePart(11.5, 16)

  for i = 1, SLICES do
    local t = self.area:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(1, 1, 1, 1)
    self.plate[i] = t
  end

  -- shown while unlocked so the tape can be found and dragged
  self.box = root:CreateTexture(nil, "BACKGROUND", nil, -8)
  self.box:SetAllPoints()
  self.box:SetColorTexture(1, 0.82, 0, 0.12)
  self.hint = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  self.hint:SetPoint("TOP", root, "BOTTOM", 0, -2)
  self.hint:SetText("Drag to move. Lock it again in Options > AddOns > Range Probe.")

  self:SetUnlocked(false)
  return self
end

-- zoneAt(d) -> "melee" / "work" / "dead"
function Tape:SetZones(zoneAt)
  self.zoneAt = zoneAt
end

function Tape:SetLayout(width, height, fontSize, ppy, showStrip)
  self.width, self.height, self.fontSize, self.ppy, self.showStrip = width, height, fontSize, ppy, showStrip
  local k = height / BASE_H
  self.k = k
  self.base = height - 12 * k            -- tick baseline, from the top of the tape area
  self.root:SetSize(width, height + fontSize + 2)
  self.area:SetHeight(height)

  self.number:SetFont(FONT, fontSize, "OUTLINE")
  self.number:SetShadowOffset(1, -1)
  self.number:SetShadowColor(0, 0, 0, 0.9)
  self.unit:SetFont(FONT, math.max(8, math.floor(fontSize * 0.43 + 0.5)), "OUTLINE")
  self.unit:SetShadowOffset(1, -1)
  self.unit:SetShadowColor(0, 0, 0, 0.9)

  -- backing plate: clear at the top, darkest at the zone strip, faded out to the sides
  local plateH = self.base + 5 * k
  local sw = width / SLICES
  for i, t in ipairs(self.plate) do
    local cx = (i - 0.5) * sw
    local a = 0.6 * fade(cx, width / 2)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", self.area, "TOPLEFT", (i - 1) * sw, 0)
    t:SetSize(sw + 0.5, plateH)
    t:SetGradient("VERTICAL", CreateColor(0, 0, 0, a), CreateColor(0, 0, 0, 0))
  end

  -- needle, centred
  local nw = 16 * k
  local headH, tipH = 9.5 * k, 4.5 * k
  self.head:ClearAllPoints()
  self.head:SetPoint("TOP", self.area, "TOP", 0, 0)
  self.head:SetSize(nw, headH)
  self.tip:ClearAllPoints()
  self.tip:SetPoint("BOTTOM", self.area, "BOTTOM", 0, 0)
  self.tip:SetSize(nw, tipH)
  self.stem:ClearAllPoints()
  self.stem:SetPoint("TOP", self.head, "BOTTOM")
  self.stem:SetPoint("BOTTOM", self.tip, "TOP")
  self.stem:SetWidth(nw)

  -- enough tick textures for the visible span
  local need = math.ceil(width / ppy * 10) + 3
  for i = #self.ticks + 1, need do
    local t = self.area:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 1)
    self.ticks[i] = t
    local s = self.area:CreateTexture(nil, "ARTWORK", nil, -1)
    s:SetColorTexture(1, 1, 1, 1)
    self.strip[i] = s
  end
  self:Draw(self.value, self.label)
end

function Tape:SetUnlocked(on)
  self.unlocked = on
  self.box:SetShown(on)
  self.hint:SetShown(on)
  self.root:EnableMouse(on)
end

-- v: distance in yd (fractional, drives the tape). label: the text on top (whole yards).
function Tape:Draw(v, label)
  self.value, self.label = v, label
  if not self.width or not self.zoneAt then return end
  local W, ppy, k, base = self.width, self.ppy, self.k, self.base
  local cx = W / 2
  local half = cx / ppy
  local first = math.max(0, math.floor((v - half) * 10))
  local last = math.ceil((v + half) * 10)
  local colors, zoneAt = Tape.COLORS, self.zoneAt
  local n = 0
  for i = first, last do
    n = n + 1
    local tick, seg = self.ticks[n], self.strip[n]
    if not tick then break end
    local d = i / 10
    local x = cx + (d - v) * ppy
    local f = fade(x, cx)
    local major, halfTick = i % 10 == 0, i % 5 == 0
    local a = f * (major and 1 or halfTick and 0.85 or 0.65)
    if a > 0.01 then
      local c = colors[zoneAt(d)]
      local w = major and 2 or 1
      local h = (major and 20 or halfTick and 12 or 6) * k
      tick:ClearAllPoints()
      tick:SetPoint("BOTTOMLEFT", self.area, "TOPLEFT", x - w / 2, -base)
      tick:SetSize(w, h)
      tick:SetVertexColor(c[1], c[2], c[3], a)
      tick:Show()
    else
      tick:Hide()
    end
    if self.showStrip and f > 0.01 then
      local c = colors[zoneAt(d + 0.05)]
      seg:ClearAllPoints()
      seg:SetPoint("TOPLEFT", self.area, "TOPLEFT", x, -(base + 2 * k))
      seg:SetSize(ppy / 10 + 0.5, 3 * k)
      seg:SetVertexColor(c[1], c[2], c[3], 0.55 * f)
      seg:Show()
    else
      seg:Hide()
    end
  end
  for i = n + 1, #self.ticks do
    self.ticks[i]:Hide()
    self.strip[i]:Hide()
  end

  -- the value on top, coloured by the zone it is in; number + unit centred as one group
  local c = colors[zoneAt(v)]
  self.number:SetText(label or tostring(math.floor(v)))
  self.unit:SetText(self.unitName or "yd")
  self.number:SetTextColor(c[1], c[2], c[3])
  self.unit:SetTextColor(c[1], c[2], c[3])
  local nw, uw = self.number:GetStringWidth(), self.unit:GetStringWidth()
  local gap = 2
  self.number:ClearAllPoints()
  self.number:SetPoint("BOTTOMLEFT", self.area, "TOPLEFT", cx - (nw + gap + uw) / 2, 1)
  self.unit:ClearAllPoints()
  self.unit:SetPoint("BOTTOMLEFT", self.number, "BOTTOMRIGHT", gap, math.floor(self.fontSize * 0.08 + 0.5))
end
