SWIFT ?= swift
CONFIG ?= release
BIN_DIR := $(shell $(SWIFT) build -c $(CONFIG) --show-bin-path 2>/dev/null)
PROBE := $(BIN_DIR)/nowsee-probe
SIGN_NAME ?= Nowsee Dev
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep "$(SIGN_NAME)" | head -1 | awk '{print $$2}' | grep . || echo -)

PROBE_APP := dist/Nowsee Probe.app
APP := dist/Nowsee.app

INSTALL_DIR ?= /Applications

.PHONY: cert app check run-app install uninstall probe run-probe probe-app run-probe-app reset-tcc clean

check:
	$(SWIFT) run -c $(CONFIG) nowsee-check

install: app
	@pkill -INT -f "Nowsee.app/Contents/MacOS/Nowsee" 2>/dev/null || true
	rm -rf "$(INSTALL_DIR)/Nowsee.app"
	ditto "$(APP)" "$(INSTALL_DIR)/Nowsee.app"
	open "$(INSTALL_DIR)/Nowsee.app"
	@echo "installed to $(INSTALL_DIR)/Nowsee.app — searchable in Raycast and Spotlight"

uninstall:
	@pkill -INT -f "Nowsee.app/Contents/MacOS/Nowsee" 2>/dev/null || true
	rm -rf "$(INSTALL_DIR)/Nowsee.app"

cert:
	./scripts/make-cert.sh "$(SIGN_NAME)"

app:
	$(SWIFT) build -c $(CONFIG) --product Nowsee
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp Sources/Nowsee/Info.plist "$(APP)/Contents/Info.plist"
	cp $(BIN_DIR)/Nowsee "$(APP)/Contents/MacOS/Nowsee"
	codesign --force --deep --sign "$(SIGN_IDENTITY)" "$(APP)"
	@codesign -dv "$(APP)" 2>&1 | grep -E 'Identifier|Signature' || true

run-app: app
	pkill -INT -f dist/Nowsee.app/Contents/MacOS/Nowsee || true
	open "$(APP)"

probe:
	$(SWIFT) build -c $(CONFIG) --product nowsee-probe
	codesign --force --sign "$(SIGN_IDENTITY)" --identifier sh.nowsee.probe $(PROBE)
	@codesign -dv $(PROBE) 2>&1 | grep -E 'Identifier|Signature' || true

run-probe: probe
	$(PROBE)

probe-app:
	$(SWIFT) build -c $(CONFIG) --product nowsee-probe
	rm -rf "$(PROBE_APP)"
	mkdir -p "$(PROBE_APP)/Contents/MacOS"
	cp Sources/nowsee-probe/Info.plist "$(PROBE_APP)/Contents/Info.plist"
	cp $(PROBE) "$(PROBE_APP)/Contents/MacOS/nowsee-probe"
	codesign --force --deep --sign "$(SIGN_IDENTITY)" "$(PROBE_APP)"
	@codesign -dv "$(PROBE_APP)" 2>&1 | grep -E 'Identifier|Signature' || true

run-probe-app: probe-app
	@rm -f "$$HOME/Library/Logs/nowsee-probe.log"
	open "$(PROBE_APP)" --args 15

reset-tcc:
	tccutil reset SystemAudioCaptureRequests sh.nowsee.probe || true
	tccutil reset SystemAudioCaptureRequests sh.nowsee.Nowsee || true

clean:
	rm -rf .build dist
