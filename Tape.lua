-- The range display, in one of two looks:
--   tape   a digital-compass style ruler sliding under a gold needle: ticks every 0.1 yd (taller
--          every 0.5, tallest on whole yards) coloured by zone, on a backing that is darkest at
--          the ruler's bottom edge and fades out upwards and to the sides
--   label  the distance with a rounded MELEE / RANGED / DEAD ZONE / OUT OF RANGE badge on its left
-- Either way the whole-yard value is centred on its digits, with "yd" hanging off its right.
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
local SLICES = 28          -- backing plate columns (each a vertical gradient)
local BASE_H = 40          -- design height; tick sizes scale with height / BASE_H

-- Fonts to choose from: Changa ships with the addon (OFL), the rest are built in.
Tape.FONTS = {
  { MEDIA .. "Changa-Bold.ttf", "Changa Bold" },
  { "Fonts\\skurri.ttf", "Skurri (combat numbers)" },
  { "Fonts\\ARIALN.TTF", "Arial Narrow" },
  { "Fonts\\2002B.ttf", "2002 Bold" },
  { "Fonts\\FRIZQT__.TTF", "Friz Quadrata" },
  { "Fonts\\NIM_____.ttf", "Nimrod" },
  { "Fonts\\MORPHEUS.TTF", "Morpheus" },
}

-- Where the digits are, as parts of the font size S, for a string placed by its centre: digit
-- height D * S, digit middle R * S above the string's centre. Placing by font size and centre
-- works on every client (the line height a client reports differs between Retail and Classic).
-- Changa's values were measured on screen in game; the rest are a rough guess.
local DIGIT = { [MEDIA .. "Changa-Bold.ttf"] = { D = 0.725, R = 0.13 } }
local DEFAULT_DIGIT = { D = 0.72, R = 0.1 }

Tape.LABELS = { melee = "MELEE", work = "RANGED", dead = "DEAD ZONE", far = "OUT OF RANGE" }

Tape.COLORS = {
  melee = { 0.302, 0.659, 1 },
  work = { 0.373, 0.878, 0.416 },
  dead = { 0.95, 0.33, 0.31 },
  far = { 0.545, 0.565, 0.6 },
}

local function fade(x, cx)
  local f = 1 - (math.abs(x - cx) / cx) ^ 2.2
  return f > 0 and f or 0
end

local function setFont(fs, font, size, flags)
  if not fs:SetFont(font, size, flags) then fs:SetFont(FALLBACK_FONT, size, flags) end
end

-- name: global frame name (nil for previews). A display on UIParent gets its own strata;
-- one inside another frame (the settings previews) draws with that frame.
function Tape.New(parent, name)
  local self = setmetatable({ ticks = {}, plate = {} }, Tape)
  local root = CreateFrame("Frame", name, parent)
  if parent == UIParent then root:SetFrameStrata("MEDIUM") end
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

  -- badge: a rounded rectangle from three slices of one texture, with the zone name in capitals
  self.badge = CreateFrame("Frame", nil, root)
  local function slice(left, right)
    local t = self.badge:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(MEDIA .. "badge")
    t:SetTexCoord(left, right, 0, 1)
    return t
  end
  self.capL, self.mid, self.capR = slice(0, 0.25), slice(0.25, 0.75), slice(0.75, 1)
  self.capL:SetPoint("TOPLEFT")
  self.capL:SetPoint("BOTTOMLEFT")
  self.capR:SetPoint("TOPRIGHT")
  self.capR:SetPoint("BOTTOMRIGHT")
  self.mid:SetPoint("TOPLEFT", self.capL, "TOPRIGHT")
  self.mid:SetPoint("BOTTOMRIGHT", self.capR, "BOTTOMLEFT")
  self.badgeText = self.badge:CreateFontString(nil, "OVERLAY")
  self.badgeText:SetPoint("CENTER", 0, 0)

  -- needle: head, stretched stem and tip, all sliced from one texture, on its own frame above
  -- the ruler (a child frame draws over its parent's textures whatever their layer)
  self.needle = CreateFrame("Frame", nil, self.area)
  self.needle:SetAllPoints(self.area)
  self.needle:SetFrameLevel(self.ruler:GetFrameLevel() + 5)
  local function needlePart(top, bottom)
    local t = self.needle:CreateTexture(nil, "OVERLAY", nil, 7)
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

  -- shown while unlocked so the display can be found and dragged
  self.box = root:CreateTexture(nil, "BACKGROUND", nil, -8)
  self.box:SetAllPoints()
  self.box:SetColorTexture(1, 0.82, 0, 0.12)
  self.hint = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  self.hint:SetPoint("TOP", root, "BOTTOM", 0, -2)
  self.hint:SetText("Drag to move. Closing the Range Probe window locks it.")

  self:SetUnlocked(false)
  return self
end

-- zoneAt(d) -> "melee" / "work" / "dead" / "far"
function Tape:SetZones(zoneAt)
  self.zoneAt = zoneAt
  self.first, self.zone = nil, nil   -- restyle on the next draw
  if self.value then self:Draw(self.value, self.label) end
end

-- style: "tape" or "label"
function Tape:SetLayout(width, height, fontSize, ppy, font, style)
  self.width, self.height, self.fontSize, self.ppy = width, height, fontSize, ppy
  self.showTape = style ~= "label"
  local k = height / BASE_H
  self.k = k
  self.base = math.floor(height - 12 * k + 0.5)   -- tick baseline, from the top of the tape area
  self.area:SetHeight(height)
  self.area:SetShown(self.showTape)
  self.badge:SetShown(not self.showTape)

  font = font or FALLBACK_FONT
  setFont(self.number, font, fontSize, "OUTLINE")
  setFont(self.unit, font, math.max(8, math.floor(fontSize * 0.45 + 0.5)), "OUTLINE")   -- "yd"
  for _, fs in ipairs({ self.number, self.unit }) do
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
  end
  self.unit:SetText("yd")   -- only once a font is set: text on a font-less string errors

  local m = DIGIT[font] or DEFAULT_DIGIT
  local digitH = math.max(6, math.floor(fontSize * m.D + 0.5))
  local unitSize = math.max(8, math.floor(fontSize * 0.45 + 0.5))   -- same as the "yd" font above

  -- badge: as tall as the digits; one width for every label (the longest), so nothing shifts
  self.badge:SetHeight(digitH)
  self.capL:SetWidth(digitH / 2)
  self.capR:SetWidth(digitH / 2)
  setFont(self.badgeText, font, math.max(7, math.floor(digitH * 0.5 + 0.5)), "")
  self.badgeText:SetTextColor(0.06, 0.06, 0.07)
  local longest = 0
  for _, text in pairs(Tape.LABELS) do
    self.badgeText:SetText(text)
    longest = math.max(longest, self.badgeText:GetStringWidth() or 0)
  end
  local badgeW = math.floor(longest + digitH * 0.9 + 0.5)
  self.badge:SetWidth(badgeW)

  self.number:ClearAllPoints()
  self.unit:ClearAllPoints()
  self.badge:ClearAllPoints()
  -- the digits' middle line: 3 px above the tape, or the middle of the label row
  if self.showTape then
    -- tape: the number is centred on its own digits over the needle; "yd" hangs off its right
    self.number:SetJustifyH("CENTER")
    self.root:SetSize(width, height + digitH + 4)
    self.number:SetPoint("CENTER", self.area, "TOP", 0, 3 + digitH / 2 - m.R * fontSize)
  else
    -- label: [ badge ] [ number, right-aligned in a two-digit slot ] yd -- all fixed in place
    local gap = math.floor(fontSize * 0.25 + 0.5)
    self.number:SetText("88")
    local slot = self.number:GetStringWidth() or fontSize
    local unitW = self.unit:GetStringWidth() or fontSize * 0.6
    self.number:SetJustifyH("RIGHT")
    self.root:SetSize(badgeW + gap + slot + 2 + unitW, digitH + 4)
    self.badge:SetPoint("LEFT", self.root, "LEFT", 0, 0)
    -- the digits' middle on the row's middle, level with the badge
    self.number:SetPoint("RIGHT", self.root, "LEFT", badgeW + gap + slot, -m.R * fontSize)
  end
  -- "yd" stands on the digits' baseline
  self.unit:SetPoint("LEFT", self.number, "RIGHT", 2, (m.R - m.D / 2) * (fontSize - unitSize))

  -- backing plate: darkest at the ruler's bottom edge, clear at the top and to the sides
  local sw = width / SLICES
  for i, t in ipairs(self.plate) do
    local a = 0.6 * fade((i - 0.5) * sw, width / 2)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", self.area, "TOPLEFT", (i - 1) * sw, 0)
    t:SetSize(sw + 0.5, self.base)
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
    end
    t:ClearAllPoints()
    t:SetPoint("BOTTOM", self.ruler, "TOPLEFT", (i - 1) * step, -self.base)
  end
  for i = need + 1, #self.ticks do self.ticks[i]:Hide() end

  self.first, self.drawn, self.text, self.zone = nil, nil, nil, nil
  self.number:SetText("")
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
    local tick = self.ticks[n]
    if i < 0 then
      tick:Hide()
    else
      local major, halfTick = i % 10 == 0, i % 5 == 0
      local c = colors[zoneAt(i / 10)]
      tick:SetSize(major and 3 or 2, (major and 20 or halfTick and 12 or 6) * k)
      tick:SetVertexColor(c[1], c[2], c[3], major and 1 or halfTick and 0.9 or 0.75)
      tick:Show()
    end
  end
end

-- v: distance in yd (fractional, drives the tape). label: the text on top (whole yards).
function Tape:Draw(v, label)
  self.value, self.label = v, label
  if not self.width or not self.zoneAt then return end
  if v == self.drawn and label == self.text and self.zone then return end
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
      for _, t in ipairs({ self.capL, self.mid, self.capR }) do t:SetVertexColor(c[1], c[2], c[3], 0.95) end
    end
  end
end
