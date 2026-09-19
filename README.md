# omarchy-openrgb

Keeps every device [OpenRGB](https://openrgb.org) manages in the colour of the
current [Omarchy](https://omarchy.org) theme. Switch themes and your keyboard,
mouse, RAM, fans and strips follow; log in and they already match.

Omarchy retints ASUS ROG and Framework keyboards itself. This plugin does the
same for everything OpenRGB can see, along the lines of
[omacom/omarchy#12199](https://github.com/omacom/omarchy/pull/12199), packaged
as a shell plugin you can add and remove.

## Install

```bash
sudo pacman -S openrgb      # if you do not have it yet
omarchy plugin add https://github.com/huacnlee/omarchy-openrgb.git --enable
```

That is all. The plugin runs as a service inside `omarchy-shell`: it syncs once
when the shell starts and again every time `omarchy theme set` finishes.

Remove it with `omarchy plugin remove huacnlee.openrgb`.

## What colour it picks

1. `keyboard.rgb` from the theme, when the theme ships one — the same file
   Omarchy uses for its built-in keyboard support.
2. Otherwise `accent` from the theme's `colors.toml`, which every theme has.

The colour is mixed 40% toward white before it reaches the LEDs (raw accents
look dim on hardware) and applied at full brightness. Devices that offer a
`Gradient` mode get that mode; everything else gets `static`.

Nothing is configurable yet; the constants sit at the top of
`bin/omarchy-openrgb-apply`.

## Speed

Without an OpenRGB server running, each `openrgb` command re-probes all your
hardware, so a sync takes two probes (roughly 15 s on a desktop with a handful
of devices). It runs in the background and never delays the theme switch. If
you want it near-instant, keep the OpenRGB SDK server up — the CLI connects to
it automatically:

```bash
openrgb --server --startminimized &   # or `openrgb --autostart-enable "--server --startminimized"`
```

## Without the shell plugin

`bin/omarchy-openrgb-apply` is plain bash with no dependency on the shell. To
use it as a theme hook instead:

```bash
omarchy hook install theme-set bin/omarchy-openrgb-apply
```

## Development

```bash
make test        # bash tests with a mocked openrgb
make qml-check   # qmllint against the Omarchy shell imports
make validate    # tests + lint + `omarchy plugin validate .`
make install     # symlink this checkout into ~/.config/omarchy/plugins and enable it
make apply       # run one sync by hand
```

## License

MIT
