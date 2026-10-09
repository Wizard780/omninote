# SwiftPM is kept in Package.swift, but on machines with only Command Line Tools its
# manifest linker fails, so the verified path is plain swiftc.
CORE := $(wildcard Sources/OmninoteCore/*.swift)
APP  := $(wildcard Sources/omninote/*.swift)
TESTS := $(wildcard Tests/OmninoteCoreTests/*.swift)
BUILD := build
BUNDLE := dist/omninote.app

.PHONY: all test app run clean

all: $(BUILD)/omninote

$(BUILD)/omninote: $(CORE) $(APP)
	@mkdir -p $(BUILD)
	swiftc -O -parse-as-library -module-name omninote -framework AppKit -framework Carbon $(CORE) $(APP) -o $@

$(BUILD)/tests: $(CORE) $(TESTS)
	@mkdir -p $(BUILD)
	swiftc -module-name OmninoteCoreTests $(CORE) $(TESTS) -o $@

test: $(BUILD)/tests
	$(BUILD)/tests

app: $(BUILD)/omninote
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BUILD)/omninote $(BUNDLE)/Contents/MacOS/omninote
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/themes/*.json $(BUNDLE)/Contents/Resources/
	codesign --force --sign - $(BUNDLE)

run: app
	open $(BUNDLE)

clean:
	rm -rf $(BUILD) dist .build
