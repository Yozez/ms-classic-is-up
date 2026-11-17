APP := build/MS Classic Is Up.app
INSTALL_DIR := $(HOME)/Applications

.PHONY: build test app run screenshots install uninstall clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

# Runs the bundled app in the foreground (Ctrl-C to quit). Pass MSC_NOW=... to simulate a time.
run: app
	"$(APP)/Contents/MacOS/MSClassicTray"

# Renders the README screenshots and leaf icons offscreen from live data.
screenshots: build
	"$$(swift build --show-bin-path)/MSClassicTray" --snapshot docs

install: app
	mkdir -p "$(INSTALL_DIR)"
	-pkill -x MSClassicTray
	rm -rf "$(INSTALL_DIR)/MS Classic Is Up.app"
	cp -R "$(APP)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/MS Classic Is Up.app"

uninstall:
	-pkill -x MSClassicTray
	rm -rf "$(INSTALL_DIR)/MS Classic Is Up.app"

clean:
	rm -rf .build build
