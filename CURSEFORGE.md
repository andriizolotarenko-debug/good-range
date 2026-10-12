# Good Range: store texts and icon brief

Texts for the CurseForge page and the TOC, plus the brief for the icon. They assume the rename
from Range Probe to Good Range (folder `GoodRange`, commands `/goodrange` and `/gr`).

## TOC

```
## Title: Good Range
## Notes: Distance to your target on a sliding range tape, coloured by what your class can do from there.
```

## CurseForge summary (one line under the name)

Know your range at a glance: distance to your target on a sliding yard tape, coloured by your class, form and what you can use right now.

## CurseForge description

### Good Range

**Know you're in range before you press the button.**

Good Range shows the distance to your target as a sliding ruler, like a digital compass, with a gold needle and the distance in whole yards on top. The colours come from your class, your form and what you can actually use right now.

#### Colours

- **Green: your range.** Melee for warriors, rogues, druids in cat or bear form, Enhancement shamans and Ret / Prot paladins. Shots for hunters. Spells and wands for casters and healers. Heals or buffs on friendly players.
- **Blue: another range you can use right now**, named on the badge: CHARGE, THROW, SHOOT, JUDGE, SHOCK, or a hunter's MELEE. It appears only when the ability is really available: enough rage, the right form, off cooldown, the right weapon equipped, out of combat if it needs that.
- **Red: dead zone.** The gap inside your ranges, such as a hunter's 5–8 yards before Auto Shot.
- **Grey: out of range.**

#### Finer than the game's steps

The game only tells addons whether something is within a fixed distance, so most range addons show brackets like "10–15". Good Range follows how you and your target move between those steps and estimates the distance to about a yard. Outdoors it also uses your own position.

#### Two looks

- **Tape:** the sliding ruler with the needle.
- **Label:** the distance with a rounded MELEE / RANGED / CHARGE / DEAD ZONE badge, fixed in place so nothing jumps.

#### Settings

Type `/goodrange` (or `/gr`). The window is small and movable, so the tape stays in sight while you tune it.

- Tape or label, with live previews
- Width, height, font size and scale
- Font: Changa Bold (included) or one of the game's fonts
- Show in combat, out of combat, on enemies, on friendly players
- Unlock to drag it anywhere; closing the window locks it again

Friendly NPCs never show a range. Friendly players show one only if one of your heals or buffs can target them.

#### Works on

Retail, WoW: Forever and Anniversary (TBC Classic). On Forever and Anniversary the class zones use Classic abilities and read their ranges from the game, so range talents count. On Retail the role comes from your specialization.

Light on the CPU: it does nothing without a target and checks only the range steps around the current distance.

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

Sizes to export: 400x400 PNG for CurseForge, 64x64 TGA (`media/icon.tga`) for the TOC
(`## IconTexture: Interface\AddOns\GoodRange\media\icon`).
