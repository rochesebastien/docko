APP_NAME    := Docko
CONFIG      := release
BUILD_DIR   := .build/$(CONFIG)
DIST_DIR    := dist
APP_BUNDLE  := $(DIST_DIR)/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
ICON_SRC    := Resources/AppIcon.icns

.PHONY: all build bundle run install clean icon

all: bundle

build:
	swift build -c $(CONFIG)

bundle: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -f "$(ICON_SRC)" ]; then cp "$(ICON_SRC)" "$(CONTENTS)/Resources/AppIcon.icns"; fi
	echo "APPL????" > "$(CONTENTS)/PkgInfo"
	codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "→ $(APP_BUNDLE)"

run: bundle
	-killall $(APP_NAME) 2>/dev/null; while pgrep -x $(APP_NAME) >/dev/null; do sleep 0.2; done
	open "$(APP_BUNDLE)"

install: bundle
	-killall $(APP_NAME) 2>/dev/null; while pgrep -x $(APP_NAME) >/dev/null; do sleep 0.2; done
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_BUNDLE)" /Applications/
	open "/Applications/$(APP_NAME).app"
	@echo "→ /Applications/$(APP_NAME).app (lancé)"

# Génère Resources/AppIcon.icns depuis Resources/AppIcon.png (1024x1024).
icon:
	@test -f Resources/AppIcon.png || (echo "Resources/AppIcon.png manquant (1024x1024)"; exit 1)
	rm -rf "$(DIST_DIR)/AppIcon.iconset"
	mkdir -p "$(DIST_DIR)/AppIcon.iconset"
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size Resources/AppIcon.png --out "$(DIST_DIR)/AppIcon.iconset/icon_$${size}x$${size}.png" >/dev/null; \
		sips -z $$((size*2)) $$((size*2)) Resources/AppIcon.png --out "$(DIST_DIR)/AppIcon.iconset/icon_$${size}x$${size}@2x.png" >/dev/null; \
	done
	iconutil -c icns "$(DIST_DIR)/AppIcon.iconset" -o "$(ICON_SRC)"
	@echo "→ $(ICON_SRC)"

clean:
	rm -rf .build "$(DIST_DIR)"
