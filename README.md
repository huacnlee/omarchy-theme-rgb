# omarchy-theme-rgb

**Your theme, on every light.**

Lights every device [OpenRGB](https://openrgb.org) manages in the colours of
the current [Omarchy](https://omarchy.org) theme. Switch themes and your
keyboard, mouse, RAM, fans and strips follow; log in and they already match.
A bar panel picks which theme colours, how many, and how bright.

Omarchy retints ASUS ROG and Framework keyboards itself. This plugin does the
same for everything OpenRGB can see, along the lines of
[omacom/omarchy#12199](https://github.com/omacom/omarchy/pull/12199), packaged
as a shell plugin you can add and remove.

## Install

```bash
sudo pacman -S openrgb      # if you do not have it yet
omarchy plugin add https://github.com/huacnlee/omarchy-theme-rgb.git --enable
```

The plugin runs as a service inside `omarchy-shell` and puts a palette glyph
in the bar. It syncs once when the shell starts and again every time
`omarchy theme set` finishes or you change a setting.

Remove it with `omarchy plugin remove huacnlee.theme_rgb`.

## The panel

Click the palette glyph (or `omarchy-shell huacnlee.theme_rgb toggle`).

- **Colours** — `1`, `3`, `5` (the default) or `8`. *1* is the accent on
  every device. *3* is the accent and two of the theme's named colours.
  *5* and *8* are the theme's named colours only, in an order that
  suits what each device is for: on the desk (keyboard, mouse, headset, pad)
  `blue, yellow, red, green, magenta, cyan…`; around it (screen, strips,
  RAM, motherboard, case) `blue, magenta, cyan, red, green, yellow…`.
  Background and foreground never join in — near black and near white make
  dark or colourless bands. Colours the theme lacks, and repeated ones, are
  skipped. There is nothing to pick by hand: Omarchy is chef's choice.
- **Layout** — where several colours go. *Flow* lays bands along each
  device's LEDs (top to bottom on most keyboards). On keyboards, *Rows* and
  *Columns* place the bands by where each key actually sits, and *Zones*
  colours the function keys, main block, modifiers, navigation cluster,
  numpad and logo in turn; on other devices *Zones* colours each OpenRGB zone
  (a mouse's logo, wheel and strip, say) in turn.
- **Brightness** — 10–100 %. Scales the colour values themselves, so it
  works the same in every OpenRGB mode; it is the only change made to what
  the theme says.
- **Preview** — the exact colours the LEDs get, as bands; one strip per device class when they differ.
- **Devices** — what OpenRGB found on the last sync, with LED counts.

**Menu** — the `󰇘` button in the header lists *Sync now* and *GitHub*.

**Without OpenRGB** the panel shows a welcome page instead of the settings,
with an *Install OpenRGB* button: it opens a floating terminal running
`omarchy-pkg-add openrgb`, and the panel switches to the settings by itself
once the package is in place.

Several colours always sit in contiguous bands with hard edges between them,
never blended. Keyboard: `←`/`→` move within a row, `↑`/`↓` between
rows, `Enter` picks, `1`–`4` pick a colours mode, `r` syncs now, `m` opens the
menu, `Esc` closes.

Settings live in `~/.config/omarchy/theme-rgb.json`; the file is watched, so
editing it by hand applies too:

```json
{
  "mode": "palette",
  "colors": 5,
  "brightness": 100,
  "layout": "flow"
}
```

For the curious, the script also honours `"single": "<variable>"`,
`"mode": "custom"` with `"custom": ["blue", "magenta"]`, and
`"roles": { "desk": [...], "ambient": [...] }` to reorder the tiers — none
of which the panel exposes.

## Speed

Without an OpenRGB SDK server, every `openrgb` command re-probes all your
hardware, which takes seconds per call. The service therefore keeps a headless
`openrgb --server --noautoconnect` running for the life of the shell, and a
sync takes about a second. If you already run a server, the plugin's own
fails to bind and yours is used.

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
