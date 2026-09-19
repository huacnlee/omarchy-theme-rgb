QMLLINT := /usr/lib/qt6/bin/qmllint
PLUGIN_ID := huacnlee.theme_rgb
PLUGIN_LINK := $(HOME)/.config/omarchy/plugins/$(PLUGIN_ID)

.PHONY: test qml-check validate install uninstall apply

test:
	bash tests/apply-test.sh
	bash tests/manifest-test.sh

# Needs the Omarchy shell's Quickshell modules on the import path. Quickshell
# serves the shell directory as the `qs` module, so lint through a scratch root
# holding a `qs` symlink. The onExited exitStatus warning is a known qmllint
# gap (first-party services trip it too); dynamic lookups through `bar.shell`
# and `Style.font.*` are typed as plain QObjects and also warn.
QMLROOT := $(or $(TMPDIR),/tmp)/omarchy-theme-rgb-qmlroot
qml-check:
	mkdir -p $(QMLROOT) && ln -sfn /usr/share/omarchy/shell $(QMLROOT)/qs
	$(QMLLINT) -I $(QMLROOT) -I /usr/share/omarchy/shell --signal-handler-parameters disable Service.qml Panel.qml App.qml components/PanelMenu.qml

validate: test qml-check
	omarchy plugin validate .
	git diff --check

# Run the colour sync once by hand, outside the shell.
apply:
	bin/omarchy-theme-rgb-apply

# Symlinks this checkout into ~/.config/omarchy/plugins so edits are read
# live. Development only — users install with `omarchy plugin add`.
install:
	mkdir -p $(dir $(PLUGIN_LINK))
	ln -sfn $(CURDIR) $(PLUGIN_LINK)
	omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
	@for i in $$(seq 1 40); do \
	  omarchy plugin list --json 2>/dev/null | jq -e 'any(.[]; .id == "$(PLUGIN_ID)")' >/dev/null && break; \
	  sleep 0.1; \
	done
	omarchy plugin enable $(PLUGIN_ID) --section right

uninstall:
	-omarchy plugin disable $(PLUGIN_ID)
	rm -f $(PLUGIN_LINK)
	omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
