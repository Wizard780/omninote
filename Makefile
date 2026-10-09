# SwiftPM is kept in Package.swift, but on machines with only Command Line Tools its
# manifest linker fails, so the verified path is plain swiftc.
CORE := $(wildcard Sources/OmninoteCore/*.swift)
APP  := $(wildcard Sources/omninote/*.swift)
TESTS := $(wildcard Tests/OmninoteCoreTests/*.swift)
BUILD := build
BUNDLE := dist/omninote.app

.PHONY: all test app run dmg install clean

all: $(BUILD)/omninote

$(BUILD)/libOmninoteCore.a: $(CORE)
	@mkdir -p $(BUILD)
	swiftc -O -emit-library -static -emit-module -module-name OmninoteCore -emit-module-path $(BUILD)/OmninoteCore.swiftmodule $(CORE) -o $@

$(BUILD)/omninote: $(BUILD)/libOmninoteCore.a $(APP)
	swiftc -O -parse-as-library -module-name omninote -I $(BUILD) -L $(BUILD) -lOmninoteCore -lsqlite3 -framework AppKit -framework Carbon $(APP) -o $@

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
	cp Resources/themes/*.json Resources/omninote.icns $(BUNDLE)/Contents/Resources/
	codesign --force --sign - $(BUNDLE)

run: app
	open $(BUNDLE)

dist/omninote.dmg: app
	rm -rf $(BUILD)/dmg $@
	mkdir -p $(BUILD)/dmg
	cp -R $(BUNDLE) $(BUILD)/dmg/
	ln -s /Applications $(BUILD)/dmg/Applications
	hdiutil create -quiet -volname omninote -srcfolder $(BUILD)/dmg -ov -format UDZO $@
	@echo "wrote $@"

dmg: dist/omninote.dmg

install: app
	rm -rf /Applications/omninote.app
	cp -R $(BUNDLE) /Applications/omninote.app
	@echo "installed /Applications/omninote.app"

clean:
	rm -rf $(BUILD) dist .build
