# omarchy-theme-rgb

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

- **Colours** — `Single`, `3`, `5` or `Custom`.
  - *Single* lights one theme variable on every device.
  - *3 / 5* light the chosen variable plus the theme colours nearest to it
    on the hue wheel (within 90°), so a blue theme gets blues, cyans and purples — never a
    rainbow. Greys and near-duplicate hues are skipped, so a theme may offer
    fewer than asked.
  - *Custom* lights exactly the variables you pick, in the order you pick them.
- **Theme colour** — swatches of the current theme's `accent red orange yellow
  green cyan blue magenta brown foreground`, as `colors.toml` defines them.
- **Brightness** — 10–100 %. Applied to the colour values themselves, so it
  works the same in every OpenRGB mode.
- **Preview** — the exact colours the LEDs get, as bands.
- **Devices** — what OpenRGB found on the last sync, with LED counts.

Several colours are laid out as contiguous bands across a device's LEDs, with
hard edges between them. Keyboard: `←`/`→` move within a row, `↑`/`↓` between
rows, `Enter` picks, `1`–`4` pick a colours mode, `r` syncs now, `Esc` closes.

Settings live in `~/.config/omarchy/theme-rgb.json`; the file is watched, so
editing it by hand applies too:

```json
{
  "mode": "palette",
  "single": "accent",
  "anchor": "accent",
  "colors": 5,
  "custom": [],
  "brightness": 100
}
```

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
