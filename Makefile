APP     := WLR
BUNDLE  := $(APP).app
BUILD   := .build
SOURCES := $(wildcard Sources/*.swift)
ARCH    := $(shell uname -m)
TARGET  := $(ARCH)-apple-macos13.0
FLAGS   := -O -target $(TARGET) -framework AppKit -framework CoreGraphics \
           -framework Carbon

.PHONY: all bundle install run restore selftest clean

all: bundle

$(BUILD)/$(APP): $(SOURCES)
	@mkdir -p $(BUILD)
	swiftc $(FLAGS) $(SOURCES) -o $@

$(BUILD)/wlr-restore: Tools/restore.swift
	@mkdir -p $(BUILD)
	swiftc -O -target $(TARGET) -framework CoreGraphics Tools/restore.swift -o $@

bundle: $(BUILD)/$(APP) $(BUILD)/wlr-restore
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@cp $(BUILD)/$(APP) $(BUNDLE)/Contents/MacOS/$(APP)
	@cp $(BUILD)/wlr-restore $(BUNDLE)/Contents/MacOS/wlr-restore
	@codesign --force --sign - $(BUNDLE)
	@echo "built $(BUNDLE)"

install: bundle
	@rm -rf /Applications/$(BUNDLE)
	@cp -R $(BUNDLE) /Applications/
	@echo "installed /Applications/$(BUNDLE)"

run: bundle
	@pkill -x $(APP) 2>/dev/null || true
	@open $(BUNDLE)
	@echo "launched — look for the moon icon in the menu bar"

restore: $(BUILD)/wlr-restore
	@$(BUILD)/wlr-restore

$(BUILD)/wlr-selftest: Tools/selftest.swift
	@mkdir -p $(BUILD)
	swiftc -O -target $(TARGET) -framework CoreGraphics Tools/selftest.swift -o $@

# Drives the running app and reads the LUT back. Screen goes red for a few seconds.
selftest: $(BUILD)/wlr-selftest
	@$(BUILD)/wlr-selftest

clean:
	@rm -rf $(BUILD) $(BUNDLE)
