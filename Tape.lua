-- The range tape: a digital-compass style ruler that slides under a gold needle.
-- Ticks every 0.1 yd (taller every 0.5, tallest on whole yards) coloured by zone, a zone strip
-- under them, a backing that fades out upwards and to the sides, and the whole-yard value on top.
--
-- Cheap to run: the ticks sit on one ruler frame that is moved as a whole each frame; they are
-- only restyled when the tape passes a 0.1 yd step, and the side fade is a mask texture, so the
-- GPU does it. Nothing is redrawn while the value stands still.
local _, ns = ...

local Tape = {}
Tape.__index = Tape
ns.Tape = Tape

local MEDIA = "Interface\\AddOns\\RangeProbe\\media\\"
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"

-- Fonts to choose from (Options > Font): Changa ships with the addon (OFL), the rest are built in.
Tape.FONTS = {
  { MEDIA .. "Changa-Bold.ttf", "Changa Bold" },
  { "Fonts\\skurri.ttf", "Skurri (combat numbers)" },
  { "Fonts\\ARIALN.TTF", "Arial Narrow" },
  { "Fonts\\2002B.ttf", "2002 Bold" },
  { "Fonts\\FRIZQT__.TTF", "Friz Quadrata" },
  { "Fonts\\NIM_____.ttf", "Nimrod" },
  { "Fonts\\MORPHEUS.TTF", "Morpheus" },
}
local SLICES = 28          -- backing plate columns (each a vertical gradient)
local BASE_H = 40          -- design height; tick sizes scale with height / BASE_H

Tape.LABELS = { melee = "Melee", work = "Ranged", dead = "Dead Zone" }

Tape.COLORS = {
  melee = { 0.302, 0.659, 1 },
  work = { 0.373, 0.878, 0.416 },
  dead = { 0.545, 0.565, 0.6 },
}

local function fade(x, cx)
  local f = 1 - (math.abs(x - cx) / cx) ^ 2.2
  return f > 0 and f or 0
end

local function setFont(fs, font, size)
  if not fs:SetFont(font, size, "OUTLINE") then fs:SetFont(FALLBACK_FONT, size, "OUTLINE") end
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.9)
end

function Tape.New(parent)
  local self = setmetatable({ ticks = {}, strip = {}, plate = {} }, Tape)
  local root = CreateFrame("Frame", "RangeProbeTape", parent)
  root:SetFrameStrata("MEDIUM")
  self.root = root

  self.area = CreateFrame("Frame", nil, root)
  self.area:SetPoint("BOTTOMLEFT")
  self.area:SetPoint("BOTTOMRIGHT")
  self.area:SetClipsChildren(true)

  self.ruler = CreateFrame("Frame", nil, self.area)
  self.ruler:SetSize(1, 1)

  self.mask = self.ruler:CreateMaskTexture()
  self.mask:SetTexture(MEDIA .. "fade_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  self.mask:SetAllPoints(self.area)

  self.number = root:CreateFontString(nil, "OVERLAY")
  self.unit = root:CreateFontString(nil, "OVERLAY")

  -- badge for the no-tape mode: the zone name in dark text on the zone colour
  self.badge = CreateFrame("Frame", nil, root)
  self.badgeBg = self.badge:CreateTexture(nil, "BACKGROUND")
  self.badgeBg:SetAllPoints()
  self.badgeBg:SetColorTexture(1, 1, 1, 1)
  self.badgeText = self.badge:CreateFontString(nil, "OVERLAY")
  self.badgeText:SetPoint("CENTER", 0, 0)
  self.badgeText:SetTextColor(0.06, 0.06, 0.07)

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
  self.hint:SetText("Drag to move. Closing the Range Probe window locks it.")

  self:SetUnlocked(false)
  return self
end

-- zoneAt(d) -> "melee" / "work" / "dead"
function Tape:SetZones(zoneAt)
  self.zoneAt = zoneAt
  self.first = nil   -- restyle on the next draw
end

-- showTape false: no ruler, the number gets a Melee / Ranged / Dead Zone badge instead.
function Tape:SetLayout(width, height, fontSize, ppy, showStrip, font, showTape)
  self.width, self.height, self.fontSize, self.ppy, self.showStrip = width, height, fontSize, ppy, showStrip
  self.showTape = showTape ~= false
  local k = height / BASE_H
  self.k = k
  self.base = math.floor(height - 12 * k + 0.5)   -- tick baseline, from the top of the tape area
  -- digits leave the font's descender space empty; pull the number down over it
  self.pull = math.floor(fontSize * 0.14 + 0.5)
  self.area:SetHeight(height)
  self.area:SetShown(self.showTape)
  self.badge:SetShown(not self.showTape)

  font = font or FALLBACK_FONT
  setFont(self.number, font, fontSize)
  setFont(self.unit, font, math.max(8, math.floor(fontSize * 0.45 + 0.5)))
  self.unit:SetText("yd")   -- only once a font is set: text on a font-less string errors
  local badgeSize = math.max(8, math.floor(fontSize * 0.42 + 0.5))
  if not self.badgeText:SetFont(font, badgeSize, "") then self.badgeText:SetFont(FALLBACK_FONT, badgeSize, "") end
  self.badgeSize = badgeSize

  -- the number is centred on its own digits; "yd" (and the badge) hang off its right side
  self.number:ClearAllPoints()
  if self.showTape then
    self.root:SetSize(width, height + fontSize + 2 - self.pull)
    self.number:SetPoint("BOTTOM", self.area, "TOP", 0, 1 - self.pull)
  else
    self.root:SetSize(math.max(width, fontSize * 4), fontSize + 4)
    self.number:SetPoint("BOTTOM", self.root, "BOTTOM", 0, 2 - self.pull)
  end
  self.unit:ClearAllPoints()
  self.unit:SetPoint("BOTTOMLEFT", self.number, "BOTTOMRIGHT", 2, math.floor(fontSize * 0.08 + 0.5))
  self.badge:ClearAllPoints()
  self.badge:SetPoint("LEFT", self.unit, "RIGHT", math.floor(fontSize * 0.2 + 0.5), 0)

  -- backing plate: clear at the top, darkest at the zone strip, faded out to the sides
  local plateH = self.base + 5 * k
  local sw = width / SLICES
  for i, t in ipairs(self.plate) do
    local a = 0.6 * fade((i - 0.5) * sw, width / 2)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", self.area, "TOPLEFT", (i - 1) * sw, 0)
    t:SetSize(sw + 0.5, plateH)
    ns.API.VerticalAlpha(t, a, 0)
  end

  -- needle, centred
  local nw = 16 * k
  self.head:ClearAllPoints()
  self.head:SetPoint("TOP", self.area, "TOP", 0, 0)
  self.head:SetSize(nw, 9.5 * k)
  self.tip:ClearAllPoints()
  self.tip:SetPoint("BOTTOM", self.area, "BOTTOM", 0, 0)
  self.tip:SetSize(nw, 4.5 * k)
  self.stem:ClearAllPoints()
  self.stem:SetPoint("TOP", self.head, "BOTTOM")
  self.stem:SetPoint("BOTTOM", self.tip, "TOP")
  self.stem:SetWidth(nw)

  -- one tick per 0.1 yd across the visible span, laid out on the ruler once
  local step = ppy / 10
  local need = math.ceil(width / step) + 4
  self.count = need
  for i = 1, need do
    local t = self.ticks[i]
    if not t then
      t = self.ruler:CreateTexture(nil, "ARTWORK")
      t:SetColorTexture(1, 1, 1, 1)
      t:AddMaskTexture(self.mask)
      self.ticks[i] = t
      local s = self.ruler:CreateTexture(nil, "ARTWORK", nil, -1)
      s:SetColorTexture(1, 1, 1, 1)
      s:AddMaskTexture(self.mask)
      self.strip[i] = s
    end
    local x = (i - 1) * step
    t:ClearAllPoints()
    t:SetPoint("BOTTOM", self.ruler, "TOPLEFT", x, -self.base)
    local s = self.strip[i]
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", self.ruler, "TOPLEFT", x, -(self.base + 2 * k))
    s:SetSize(step + 0.5, math.max(2, 3 * k))
  end
  for i = need + 1, #self.ticks do
    self.ticks[i]:Hide()
    self.strip[i]:Hide()
  end
  self.first, self.drawn, self.text, self.zone = nil, nil, nil, nil
  if self.value then self:Draw(self.value, self.label) end
end

function Tape:SetUnlocked(on)
  self.unlocked = on
  self.box:SetShown(on)
  self.hint:SetShown(on)
  self.root:EnableMouse(on)
end

-- Colours and sizes for the ticks from 0.1-yd index `first` on.
function Tape:Restyle(first)
  self.first = first
  local colors, zoneAt, k = Tape.COLORS, self.zoneAt, self.k
  for n = 1, self.count do
    local i = first + n - 1
    local tick, seg = self.ticks[n], self.strip[n]
    if i < 0 then
      tick:Hide()
      seg:Hide()
    else
      local d = i / 10
      local major, halfTick = i % 10 == 0, i % 5 == 0
      local c = colors[zoneAt(d)]
      tick:SetSize(major and 3 or 2, (major and 20 or halfTick and 12 or 6) * k)
      tick:SetVertexColor(c[1], c[2], c[3], major and 1 or halfTick and 0.9 or 0.75)
      tick:Show()
      if self.showStrip then
        local sc = colors[zoneAt(d + 0.05)]
        seg:SetVertexColor(sc[1], sc[2], sc[3], 0.6)
        seg:Show()
      else
        seg:Hide()
      end
    end
  end
end

-- v: distance (fractional, drives the tape). label: the text on top (whole units).
function Tape:Draw(v, label)
  self.value, self.label = v, label
  if not self.width or not self.zoneAt then return end
  if v == self.drawn and label == self.text then return end
  self.drawn = v

  if self.showTape then
    local cx, ppy = self.width / 2, self.ppy
    local first = math.floor((v - cx / ppy) * 10) - 1
    if first ~= self.first then self:Restyle(first) end
    -- tick n sits at ruler x (n-1) * step and stands for (first + n - 1) / 10
    self.ruler:ClearAllPoints()
    self.ruler:SetPoint("TOPLEFT", self.area, "TOPLEFT", cx + (first / 10 - v) * ppy, 0)
  end

  local zone = self.zoneAt(v)
  label = label or tostring(math.floor(v))
  if label ~= self.text or zone ~= self.zone then
    self.text, self.zone = label, zone
    local c = Tape.COLORS[zone]
    self.number:SetText(label)
    self.number:SetTextColor(c[1], c[2], c[3])
    self.unit:SetTextColor(c[1], c[2], c[3])
    if not self.showTape then
      self.badgeText:SetText(Tape.LABELS[zone])
      self.badgeBg:SetColorTexture(c[1], c[2], c[3], 0.95)
      local pad = math.floor(self.badgeSize * 0.45 + 0.5)
      self.badge:SetSize(self.badgeText:GetStringWidth() + pad * 2, self.badgeSize + pad)
    end
  end
end
