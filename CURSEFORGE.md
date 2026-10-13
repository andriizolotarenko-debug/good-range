# Good Range: store texts and icon brief

## How CurseForge search works (checked 2026-10-12 on the live site)

- Only the **project name** and the **summary** are searched. A phrase from Forever Deadzone's
  summary finds it; a phrase from its description finds nothing. The description sells the
  addon but is invisible to search.
- Every word of the query has to match, and partial matches count: "rangefinder" finds
  "SimpleRangeFinder" and "Range Finder 3000"; "range check" finds "checker".
- Ranking is by text match, not downloads: for "range", Range Lens (1.5K downloads; "Range" twice
  in its name, again in its summary) is first and RangeDisplay (4M) fifth. A word in the name
  weighs most: "Range Check" (242 downloads) beats LibRangeCheck (271K) for "range check".
- So the name carries the top searches (range, target distance, range finder), and the summary
  carries the rest (yards, range check, range display, melee, charge, hunter deadzone, flavours).

Searches covered: range, distance, target distance, range finder, rangefinder, range check,
range display, yards, melee range, charge, heal range, hunter, deadzone, dead zone (via
"deadzone" partial match), Retail, Classic TBC, Forever.

## CurseForge project name

```
Good Range - Target Distance & Range Finder
```

## Summary (222 of ~250 characters)

```
Precise distance to your target in yards: one number, not a bracket. Range finder, range check and range display coloured by your class: melee, ranged, charge, throw, heal, hunter deadzone. Retail, Classic TBC and Forever.
```

## Categories

Primary **Combat** (where RangeDisplay and Range Lens are), then **HUDs**, **Hunter**,
**Warrior**, **Druid**: class players browse their class category, and hunters (dead zone),
warriors and druids (charge) gain the most.

## Flavours

Upload every file for Retail, WoW: Forever and Anniversary (TBC Classic): the flavour filters on
the search page hide files that don't list a flavour.

## TOC

```
## Title: Good Range
## Notes: Distance to your target on a sliding range tape, coloured by what your class can do from there.
```

## Description

### Good Range

**The precise distance to your target, to the yard, coloured for your class.**

For every class and role. Good Range shows exactly how far away your target is as one clear number, like **23 yd**, and colours it by what *you* can do from there: hit in melee, charge, shoot, cast or heal.

**Why it's more precise.** Other range addons show a bracket such as "10–15 yd", because that is all the game tells them. Good Range follows how you and your target move between the game's range steps and works out the distance in between, accurate to about a yard. Outdoors it also uses your own position.

#### At a glance

- 🟢 **Green: you're in your range.** Melee for melee classes, shots for hunters, spells for casters and healers, heals on friendly players.
- 🔵 **Blue: another range you can use right now**, named on the badge: CHARGE, THROW, SHOOT, JUDGE, SHOCK or MELEE. Shown only when the ability is really ready: enough rage, the right form, off cooldown, the right weapon equipped, out of combat if it needs that.
- 🔴 **Red: dead zone.** Too close for your ranged attacks, too far for melee, like a hunter's 5–8 yards.
- ⚪ **Grey: out of range.**

#### What each class sees

| Class | Green | Blue |
|---|---|---|
| **Hunter** | RANGED 8–35 yd | MELEE 0–5 yd · red DEAD ZONE 5–8 yd |
| **Warrior** | MELEE | CHARGE 8–25 yd (Charge, Intercept) · THROW / SHOOT |
| **Rogue** | MELEE | THROW / SHOOT with a thrown weapon, bow, gun or crossbow |
| **Druid**, cat | MELEE | — |
| **Druid**, bear | MELEE | CHARGE 8–25 yd (Feral Charge) when you have the rage |
| **Druid**, caster / Moonkin | RANGED | MELEE |
| **Mage, Warlock, Priest** | RANGED (spells and wand) | MELEE |
| **Shaman**, Enhancement | MELEE | RANGED, SHOCK |
| **Shaman**, Elemental / Restoration | RANGED | MELEE |
| **Paladin**, Retribution / Protection | MELEE | JUDGE, RANGED (Exorcism, Hammer of Wrath) |
| **Paladin**, Holy | RANGED | MELEE |
| **Any class**, friendly player | HEAL, or BUFF if you have no heals | — |

The ranges come from the game for the spell ranks you know, so range talents count. Druid forms, shaman and paladin talent trees and Retail specializations are picked up on their own. Friendly NPCs never show a range.

#### Four looks

- **Tape:** a sliding ruler under a gold needle, like a digital compass.
- **Label + Number:** the number with a rounded MELEE / RANGED / CHARGE / DEAD ZONE badge next to it. The badge has its own size and can be dragged anywhere on its own.
- **Label:** just the coloured badge, no number.
- **Number:** just the coloured distance.

#### Settings

Click the minimap button or type `/goodrange` (`/gr`). The settings window is small and movable, so you see the result while you tune it.

- Tape, Label + Number, Label or Number, with live previews
- Width, height, font size, ruler scale and label size
- Font: Changa Bold (included) or one of the game's fonts
- Show in combat, out of combat, on enemies, on friendly players
- Nameplate attach: the display moves with your target over its nameplate, in any of the four looks, with its own offset; without a nameplate it stays where you put it
- Reset Defaults puts position, sizes and font back; Share with a friend copies or whispers the link
- While the window is open the display shows a sample distance and can be dragged anywhere; closing the window locks it again

#### Works on

Retail, WoW: Forever and Anniversary (TBC Classic). Light on the CPU: it does nothing without a target and only checks the range steps around the current distance.

Free, no ads, no tracking.

## Icon brief (for ChatGPT image generation)

```
Square game icon for a World of Warcraft addon called "Good Range", in the style of a WoW
ability icon: painted fantasy art, slightly worn, rich colours, soft inner shadow, framed by a
thin bevelled dark-bronze border with rounded corners.

Subject: a horizontal range tape seen straight on, like the heading strip of a digital compass.
Thin vertical tick marks in a row, a tall tick every few marks. The ticks are coloured in zones
from left to right: blue, then a short red gap, then a long glowing green stretch, then grey
fading out. A polished gold needle with a small triangular head points straight down onto the
green zone in the centre, catching a warm highlight. Behind the tape, a dark night-blue
background with a faint radial glow behind the needle and a hint of a distant target silhouette
(a small enemy shape) far in the background to suggest distance.

Composition: centred, the tape across the middle third, the needle from the top edge to below
the tape, strong silhouette that still reads at 64x64 px. No text, no letters, no numbers, no
logos, no watermark. 1024x1024, transparent or dark background outside the rounded frame.
```

Follow-up prompts if needed:

- "Same icon, simpler: fewer ticks, thicker needle, so it reads at 32x32."
- "Same icon without the frame, on a transparent background, for the minimap and the addon list."

Sizes to export: 400x400 PNG for CurseForge, 64x64 TGA `media/icon.tga` (replaces the
placeholder; the TOC's `IconTexture` and the minimap button already point at it).
