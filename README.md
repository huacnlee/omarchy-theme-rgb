# omarchy-theme-rgb

**Your theme, on every light.**

<img width="300" alt="image" src="https://github.com/user-attachments/assets/0d95afdb-88c1-4f50-b203-5df6c7fd0f65" />

<img width="1000" alt="IMG_0398" src="https://github.com/user-attachments/assets/632697a8-ed76-48be-bd6e-ea6fd1dab970" />

Lights every device [OpenRGB](https://openrgb.org) manages in the colours of
the current [Omarchy](https://omarchy.org) theme. Switch themes and your
keyboard, mouse, RAM, fans and strips follow; log in and they already match.
A bar panel picks how many theme colours, how they lie on a keyboard, and how
bright.

Omarchy retints ASUS ROG and Framework keyboards itself. This plugin does the
same for everything OpenRGB can see, along the lines of
[omacom/omarchy#12199](https://github.com/omacom/omarchy/pull/12199), packaged
as a shell plugin you can add and remove.

## Install

```bash
omarchy-pkg-add openrgb      # if you do not have it yet
omarchy plugin add https://github.com/huacnlee/omarchy-theme-rgb.git --enable
```

The plugin runs as a service inside `omarchy-shell` and puts a palette glyph
in the bar. It syncs once when the shell starts and again every time
`omarchy theme set` finishes or you change a setting.

Remove it with `omarchy plugin remove huacnlee.theme_rgb`. That also stops
the headless OpenRGB server the plugin keeps; the `openrgb` package stays
installed until you remove it yourself.

Supports both the OpenRGB 1.0 device listing and the 1.1 detailed listing.

Dependencies: the `openrgb` package (the panel offers to install it), plus
`jq` and ImageMagick's `magick`, which Omarchy ships. Nothing else.

## The panel

Click the palette glyph (or `omarchy-shell huacnlee.theme_rgb toggle`).

- **Theme colours** — *How many*: `1`, `3`, `5` or `8` (the default). *1* is
  the accent alone. *3*, *5* and *8* are the first that many of the theme's
  own colours, in an order the script works out per theme (below). Missing
  colours are derived from the theme using HSLA. The colours are drawn as
  numbered swatches; colour 1 is the accent. Every device below refers to
  these numbers.
- **Where each colour goes** — every device, from OpenRGB and from Home
  Assistant, with the colours it shows and a dropdown that picks them: *All
  N colours* (laid out by the pattern below), one *Colour n*, or *Left as it
  is* / *Not changed*. Out of the box the desk (keyboard, mouse, mousemat,
  headset, gamepad) shows all colours, the rest of the computer (RAM,
  motherboard, case, strips, monitor) colour 1, and Home Assistant lights
  nothing until you give one a colour. A number past the palette wraps
  around: colour 5 of three is colour 2.
  A device that stopped OpenRGB's detection is listed as skipped, with *Try
  again* (see below).
- **Pattern for all colours** — where several colours go on a device set to
  all colours. The pattern under the pointer is described in words below the
  buttons, then drawn on your keyboard. *Omarchy* is the default. *Flow* lays bands along each
  device's LEDs (top to bottom on most keyboards). On keyboards, *Rows* and
  *Columns* place the bands by where each key actually sits, and *Zones*
  colours the function keys, main block, modifiers, navigation cluster,
  numpad and logo in turn; on other devices *Zones* colours each OpenRGB zone
  (a mouse's logo, wheel and strip, say) in turn.
  Four key-accent layouts keep clear emphasis groups. All layouts use every
  selected colour when there are enough controllable LEDs. Additional colours
  subdivide the largest base regions spatially before splitting accent groups;
  on small boards, emphasis groups may need to share or split colours.

  | Layout | Emphasis groups |
  | --- | --- |
  | Gaming | WASD + arrows; Space + left Shift/Ctrl; 1/Q; 2/E; 3/R; 4/F/G/Enter/Backspace; 5/T/I/B/C/Tab; Esc stays in base |
  | Frame | Outer rows and side keys of the main typing block |
  | LazyVim | HJKL; Space leader + Esc |
  | Omarchy | Exclusive Super; Ctrl/Shift/Alt; 0–9/arrows/Tab; punctuation; Esc/Fn; Delete/Backspace; Enter/Space |

  Gaming dims its base to 35% RGB and derives vivid accents with HSL
  saturation 80–95% and lightness 48–62%, preserving the theme hues. This
  precedes the normal brightness slider and applies only to multicolour Gaming.
  Gaming expands multicolour palettes to at least 8 colours, retaining
  selected hues and filling missing slots from the theme/HSLA palette.
  This gives 1–5 five distinct colours, all different from Esc. The shared
  FPS/action-RPG scheme covers movement, weapon/skill slots, actions and panels
  for CS, POE and Diablo-style use. It is a visual grouping, not a claim that
  every game binds the same action to each key. Keys grouped in one slot share
  its colour to keep the palette at 8. Single-colour
  mode remains solid. Other layouts retain the requested palette size.

  The first colour is the initial base; emphasis groups use the remaining
  colours, reordered for theme coverage and contrast. Extra colours extend the base. With two colours,
  emphasis groups share one colour. Unmapped keyboard keys start in the base;
  non-key LEDs and other devices start in Flow placement. LazyVim and Omarchy
  are static memory aids, not application detection or a live keybinding parser.
  User remaps may differ. All layouts are static.

  Old WASD settings migrate to Gaming, Vim to LazyVim, and F1–F12/Arrows to
  Zones. Frame retains the configuration value `outline`.
  Native theme colours are assigned to the largest regions; HSLA-completed
  colours are reserved for the smallest emphasis regions. Contrast optimization
  only swaps colours within the same origin class, so it cannot move a derived
  hue into a large native region. Extra derived bands use minimal key groups.
  Gaming’s saturation treatment
  keeps native hue identity and its large base stays in the theme hue.
  Rows span only present rows; Frame follows the present typing block edges.
  On boards without F1–F12, Escape joins the number row. Columns span the actual
  detected width. Absent keys never reserve palette slots. Selected colours
  are reordered per keyboard using Oklab colour distance across neighbouring
  groups, prioritizing Super’s neighbours. The base colour remains unchanged.
  Super has an exclusive colour in multicolour Omarchy, including two-colour
  mode (other emphasis groups then use the base). Matching colours within a
  deliberate group are retained; exact vendor geometry and limited palettes
  constrain the achievable separation.
- **Brightness** — 10–100 %. Scales the colour values themselves, so it
  works the same in every OpenRGB mode. Home Assistant lights keep their own
  brightness: they are sent the colour only.
- **Preview** — the shared device palette strip, followed by a keyboard
  schematic computed by the same placement function as the hardware.
  After discovery this shows only the first connected keyboard’s detected keys.
  Key-name positions are inferred from the standard map, not a vendor matrix;
  unknown/vendor-specific keys may not be drawn. Each keyboard is coloured
  independently from its own detected LEDs. Before discovery an ANSI reference
  is shown.

**A device that never answers.** OpenRGB probes devices one after another
and waits on each without a timeout, so one that does not answer (a
SteelSeries Rival 710 does this now and then) stops detection there, and
every device after it is never found. The plugin runs its OpenRGB server
with `-vv`, whose log names each detector before it runs. When detection
has gone quiet inside one for ten seconds, that detector is switched off in
OpenRGB's own settings (`Detectors` in `~/.config/OpenRGB/OpenRGB.json`, the
same switch as OpenRGB's *Supported Devices* page), the server is started
again, and the rest of the devices light. *Try again* switches the detector
back on and restarts the server; if the device still does not answer it is
skipped again.

**Home Assistant lights.** Every Home Assistant light that can show a
colour (colour modes hs, xy, rgb, rgbw or rgbww) is listed. A light shows one
colour, so it is given one number. Theme RGB never turns a light on: a light
that is off is skipped, and coloured within about 20 seconds of being turned
on (the shell asks Home Assistant which lights are on every 20 s while any
light has a colour). It talks to Home Assistant's REST API
(`GET /api/states`, `POST /api/services/light/turn_on` with `rgb_color`).
The address is `home_assistant.url` in the settings file, else the one the
[Home Assistant bar plugin](https://github.com/konradk/hass) is
set up with. The long-lived access token comes from the keyring: Theme RGB's
own entry,

```bash
secret-tool store --label="Theme RGB Home Assistant" \
  service theme-rgb-hass origin https://ha.example.com:443
```

else the Home Assistant plugin's entry for the same address. What the last
sync told Home Assistant is in `~/.local/state/omarchy/theme-rgb/last-hass.log`.

**Menu** — the `󰇘` button in the header lists *Sync now* and *GitHub*.

**Without OpenRGB** the panel shows a welcome page instead of the settings,
with an *Install OpenRGB* button: it opens a floating terminal running
`omarchy-pkg-add openrgb`, and the panel switches to the settings by itself
once the package is in place.

### How the colours are chosen

The candidates are the accent plus `red`, `orange`, `yellow`, `green`, `cyan`,
`blue`, `magenta` and `brown` from the theme's `colors.toml` — never
background or foreground, which would light as dark or colourless bands.
When a theme provides an ANSI palette, the coloured slots `color1`–`color6`
and their bright variants `color9`–`color14` supplement any semantic
candidates; background/foreground slots `color0`, `color7`, `color8` and
`color15` stay excluded.
Greys (saturation under 15 %) and very dark or very light tones (lightness
outside 15–90 %) are dropped.

The accent comes first: it is the theme's colour for borders, the prompt and
selections. The rest are ordered by the **current wallpaper** — the biggest
thing a theme shows. The wallpaper is reduced to twelve colour clusters
(from a 160 px thumbnail, a tenth of a second) and each theme colour scores
by how much of the wallpaper sits within 60° of its hue, so a purple city
puts magenta before yellow and a jade forest puts cyan and green before
red. A wallpaper with no colour to speak of leaves the order to vividness:
the colours the theme made saturated and mid-light are its character.

A near-duplicate of a colour already taken (hue within 12°, saturation and
lightness within 25 points) is skipped — most themes make the accent one of
the named colours, and it lights once. *3*, *5* and *8* take the first that
many — on the desk. The keyboard, mouse, mousemat, headset and gamepad get
the bands; everything else (the screen's backlight, strips, RAM,
motherboard, case) is ambient light and shows the accent alone: one colour
reads as the theme from across the room, five bands on a monitor's backlight
do not. If the theme has fewer usable colours than requested, HSLA-derived
colours fill the remaining slots. Outside Gaming, existing selected colours retain their exact
hex values. Derived colours choose the widest remaining hue gap, with saturation
clamped to 45–75% and lightness to 40–65%. A grey-only theme keeps its accent
and uses a muted blue starting hue (210°) for the added colours. Alpha is 1
because OpenRGB LEDs take opaque RGB. Single mode never synthesizes colours. Custom mode keeps its selected colours;
Gaming completes a multicolour custom selection to 8 as described above. Changing the wallpaper re-syncs within a few
seconds. Outside Gaming’s explicit emphasis treatment, original theme colours keep their exact hex values; all colours are scaled by the
brightness setting — no gamma, no mixing toward white.

Colours sit in bands or key groups with hard edges between them,
never blended. Keyboard: `←`/`→` move within a row (on the brightness row
they step by 10), `↑`/`↓` between rows, `Enter` picks, `1`–`4` pick how many
colours, `r` syncs now, `m` opens the menu, `Esc` closes. The devices'
dropdowns are for the pointer.

Settings live in `~/.config/omarchy/theme-rgb.json`; the file is watched, so
editing it by hand applies too:

```json
{
  "mode": "palette",
  "colors": 8,
  "brightness": 100,
  "layout": "omarchy",
  "assign": {
    "openrgb:HyperX Fury RGB": 2,
    "openrgb:Razer Basilisk V3": "off",
    "hass:light.desk_lamp": 1
  },
  "home_assistant": { "url": "https://ha.example.com" }
}
```

`assign` is what the panel's dropdowns write: per device (`openrgb:` and the
name OpenRGB gives it, or `hass:` and a light's entity id) `"all"`, a colour
number, or `"off"`. A device not listed gets the default above.

`mode` is `single` or `palette`, `colors` 3, 5 or 8, `brightness` 10–100 and
`layout` one of `flow`, `rows`, `columns`, `zones`, `gaming`,
`outline`, `lazyvim`, `omarchy`. For the curious, the
script also honours `"single": "<variable>"` (which theme variable *1*
lights) and `"mode": "custom"` with `"custom": ["blue", "magenta"]` — neither
of which the panel exposes.

Set `"all_devices": true` in the settings file to apply the selected
palette and layout to the cooler, GPU and case fans as well as desk
peripherals. It defaults to `false`, preserving accent-only ambient lighting.
The panel preserves this setting when saving changes. Devices with fewer
LEDs than palette colours display a sampled subset. Flow arranges fixed
colour bands; it does not animate them. Single-colour mode still sets every
device to the selected theme colour.

## Speed

Without an OpenRGB SDK server, every `openrgb` command re-probes all your
hardware, which takes seconds per call. The service therefore keeps a headless
`openrgb --server --noautoconnect` running for the life of the shell and holds
the first sync until the server answers on port 6742 (up to 20 s); a sync
then takes about a second. If you already run a server, the plugin's own
fails to bind and yours is used.

What `openrgb` said on the last sync is in
`~/.local/state/omarchy/theme-rgb/last-apply.log`. A sync that fails is
retried once after a few seconds; if it fails again the panel says so.

## Without the shell plugin

`bin/omarchy-theme-rgb-apply` is plain bash with no dependency on the shell.
It reads the same settings file. To use it as a theme hook instead:

```bash
omarchy hook install theme-set bin/omarchy-theme-rgb-apply
```

`omarchy-theme-rgb-apply stops` prints the colours it would light and
`omarchy-theme-rgb-apply variables` the theme's variables, without touching
OpenRGB.

## Development

```bash
make test        # bash tests with a mocked openrgb, plus the manifest contract
make qml-check   # qmllint against the Omarchy shell imports
make validate    # tests + lint + `omarchy plugin validate .`
make install     # symlink this checkout into ~/.config/omarchy/plugins and enable it
make apply       # run one sync by hand
```

The shell reloads the panel when its files change, but keeps a running
service instance; after editing `Service.qml` run `omarchy restart shell`.

## License

MIT
