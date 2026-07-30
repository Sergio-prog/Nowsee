SWIFT ?= swift
CONFIG ?= release
BIN_DIR := $(shell $(SWIFT) build -c $(CONFIG) --show-bin-path 2>/dev/null)
PROBE := $(BIN_DIR)/nowsee-probe
SIGN_IDENTITY ?= -

PROBE_APP := dist/Nowsee Probe.app
APP := dist/Nowsee.app

.PHONY: app run-app probe run-probe probe-app run-probe-app reset-tcc clean

app:
	$(SWIFT) build -c $(CONFIG) --product Nowsee
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp Sources/Nowsee/Info.plist "$(APP)/Contents/Info.plist"
	cp $(BIN_DIR)/Nowsee "$(APP)/Contents/MacOS/Nowsee"
	codesign --force --deep --sign $(SIGN_IDENTITY) "$(APP)"
	@codesign -dv "$(APP)" 2>&1 | grep -E 'Identifier|Signature' || true

run-app: app
	pkill -INT -f dist/Nowsee.app/Contents/MacOS/Nowsee || true
	open "$(APP)"

probe:
	$(SWIFT) build -c $(CONFIG) --product nowsee-probe
	codesign --force --sign $(SIGN_IDENTITY) --identifier sh.nowsee.probe $(PROBE)
	@codesign -dv $(PROBE) 2>&1 | grep -E 'Identifier|Signature' || true

run-probe: probe
	$(PROBE)

probe-app:
	$(SWIFT) build -c $(CONFIG) --product nowsee-probe
	rm -rf "$(PROBE_APP)"
	mkdir -p "$(PROBE_APP)/Contents/MacOS"
	cp Sources/nowsee-probe/Info.plist "$(PROBE_APP)/Contents/Info.plist"
	cp $(PROBE) "$(PROBE_APP)/Contents/MacOS/nowsee-probe"
	codesign --force --deep --sign $(SIGN_IDENTITY) "$(PROBE_APP)"
	@codesign -dv "$(PROBE_APP)" 2>&1 | grep -E 'Identifier|Signature' || true

run-probe-app: probe-app
	@rm -f "$$HOME/Library/Logs/nowsee-probe.log"
	open "$(PROBE_APP)" --args 15

reset-tcc:
	tccutil reset SystemAudioCaptureRequests sh.nowsee.probe || true
	tccutil reset SystemAudioCaptureRequests sh.nowsee.Nowsee || true

clean:
	rm -rf .build dist
