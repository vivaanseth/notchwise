# The island's design

The island follows Apple's own Dynamic Island and the dark system it sits in.
Every page draws from one set of tokens, `NotchStyle`
(`Sources/Vorssaint/UI/Notch/NotchStyle.swift`), so no two parts of the island
disagree. This note explains the choices so later pages keep to them.

## Sources

- Human Interface Guidelines, *Live Activities*: the island is pure black; text
  is medium weight or heavier and small sizes are rare; margins are even and
  corners concentric; content is grouped on inset rounded containers that never
  run to the edges; colour is bold but rare; motion lasts at most two seconds,
  replaces content with a blur and numbers with a numeric roll, and moves what
  stays to its new place rather than cutting.
- Human Interface Guidelines, *Motion*: motion has a purpose, is brief and
  precise, gets quieter the more often it happens, and can always be
  interrupted.
- WWDC23, *Animate with springs*: every motion is a spring. `smooth` has no
  swing, `snappy` a little, `bouncy` more; duration and bounce are tuned, not
  curves.
- Control Center: white glyphs on a grey fill at rest; a control takes colour
  (or white, with a black glyph) only while it is on.

## Colour

| Token | Value | Use |
| --- | --- | --- |
| `primary` | white | Text and glyphs that matter |
| `secondary` | white 60% | Supporting text, idle glyphs |
| `tertiary` | white 36% | Hints, placeholders, section names |
| `platter` | white 8% | A card on the black |
| `control` | white 12% | A button or tile at rest |
| `hover` | white 8% | The wash under the pointer |
| `selected` | white 18% | The page shown, the choice in force |
| `separator`, `track` | white 12–14% | Lines, a meter's empty part |

Colour belongs to things, never to surfaces, as in Settings and Control
Center. Each page has one colour from the system palette (`NotchModule.tint`,
the same colour its icon has in Settings) and each control one
(`NotchControlItem.tint`, its page's colour when it opens one):

- **Page grid**: each page's icon is a white glyph on a rounded square of its
  colour (`NotchIconChip`), as Settings draws its panes.
- **Top row and dock**: glyphs are white; the page shown is in its colour on a
  wash of it, as a selected tab is, and suggested pages carry a dot or icon in
  theirs. The side button that changes by itself wears its page's colour.
- **Shortcut tiles** (home and Controls): the glyph wears its control's colour
  on the grey control fill; a control that is on fills with its colour, as
  iOS 18's Control Center draws tinted controls.
- **Meaning**: red, orange and yellow also mark what is live or needs notice;
  the calendar's weekday is red as in Apple's Calendar; a song's live bars take
  its cover's colour, as the phone's island tints them.

Platters, cards, the island and its buttons stay black and grey.

Cards have no outline. Increase Contrast adds one.

## Shape

Corners step down inward so each sits inside the one around it at an even
margin: the island, then cards (`Radius.card`, 18), tiles in them
(`Radius.tile`, 12), top-row buttons (`Radius.button`, 9), and capsules for
anything a click starts (`NotchCapsuleButtonStyle`). All corners are
continuous. Cards sit `gutter` (10) apart; tiles in a card `tileGap` (6).

## Type

San Francisco throughout; medium weight and up. `display` (28 rounded
semibold) for the one figure a page is about, always with monospaced digits
and a numeric roll as it changes. `title` 15, `headline` 13 semibold, `body`
13, `callout` 12 medium, `caption` 11 medium, `label` 11 semibold for a
section's name. Nothing smaller where a page has the room.

## Motion

| Token | Spring | Use |
| --- | --- | --- |
| `hover` | smooth 0.2 s | The wash under the pointer, highlights |
| `press` | snappy 0.22 s, a touch of bounce | A control giving under a click |
| `state` | smooth 0.3 s | On and off, a symbol, a figure, a fade |
| `layout` | snappy 0.35 s | Unfolding, moving to a new place |
| `follow` | smooth 0.15 s | A reading keeping up with a key or slider |
| `scroll` | smooth 0.3 s | Scrolling to an item |
| `arrive` | smooth 0.34 s | New content settling in |

- The island's own shape keeps its springs in `NotchMotion`: growing swings a
  little and arrives, shrinking never passes the camera it hugs.
- A page change settles in (`notchArrival`): the new page comes up from a
  soft blur and 98.5% scale while the shape springs. The top row stays crisp.
- Hovering moves nothing; it only lays a wash. A press gives to 96% and
  springs back. Hovering is the island's most frequent gesture, so it gets the
  least motion.
- Symbols change with `.symbolEffect(.replace)`; figures roll with
  `.numericText()`; content swaps with `.blurReplace`.
- Reduce Motion drops scale and blur and keeps short fades.

## Pages

- **Home**: platter cards for the calendar, the camera and Now Playing; the
  shortcuts as Control Center tiles with coloured glyphs, lit in the colour
  the Controls page lights the same control. The page bar is white, the page
  shown in its colour, a dot in its colour under suggested ones.
- **Assistant**: the home's plain black at rest. VoiceOS's blue rises from the
  island's foot only while it listens, thinks or speaks. Its buttons are the
  island's capsules; the step a card asks for is the system's blue.
- **Controls**: coloured glyphs in circles on the control fill; on is white
  with a black glyph, or red, yellow or orange where the state needs notice.
- **Battery**: the island's platters, capsule buttons, green switches and the
  reading sizes above. In the menu's panel it keeps the system's controls.
