QMLLINT := /usr/lib/qt6/bin/qmllint
PLUGIN_ID := huacnlee.openrgb
PLUGIN_LINK := $(HOME)/.config/omarchy/plugins/$(PLUGIN_ID)

.PHONY: test qml-check validate install uninstall apply

test:
	bash tests/apply-test.sh
	bash tests/manifest-test.sh

# Needs the Omarchy shell's Quickshell modules on the import path.
# The onExited exitStatus warning is a known qmllint gap (first-party
# services trip it too); everything else must be clean.
qml-check:
	$(QMLLINT) -I /usr/share/omarchy/shell --signal-handler-parameters disable Service.qml

validate: test qml-check
	omarchy plugin validate .
	git diff --check

# Run the colour sync once by hand, outside the shell.
apply:
	bin/omarchy-openrgb-apply

# Symlinks this checkout into ~/.config/omarchy/plugins so edits are read
# live. Development only — users install with `omarchy plugin add`.
install:
	mkdir -p $(dir $(PLUGIN_LINK))
	ln -sfn $(CURDIR) $(PLUGIN_LINK)
	omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
	omarchy plugin enable $(PLUGIN_ID)

uninstall:
	-omarchy plugin disable $(PLUGIN_ID)
	rm -f $(PLUGIN_LINK)
	omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
