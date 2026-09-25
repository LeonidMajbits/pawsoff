SHELL := /bin/bash
.DEFAULT_GOAL := build
.PHONY: build run clean bundle test verify check-native

check-native:
	@test "$$(uname -s)" = Darwin || { echo "Native PawsOff requires macOS 13+ and Xcode command-line tools. Use 'make test' for portable policy tests." >&2; exit 2; }
	@xcrun --find swift >/dev/null

build: check-native
	xcrun swift build -c release --product PawsOff

bundle: build
	./Scripts/bundle.sh

run: bundle
	open -g "$(CURDIR)/dist/PawsOff.app"

test:
	swift test
	python3 Scripts/audit_source.py

verify: check-native
	./Scripts/verify-macos.sh

clean:
	@if [ "$$(uname -s)" = Darwin ] && pgrep -x PawsOff >/dev/null; then echo 'Quit PawsOff before cleaning its build.' >&2; exit 2; fi
	rm -rf -- .build dist


.PHONY: probes
probes: check-native
	@mkdir -p dist/probes
	xcrun swiftc -swift-version 5 Tools/FocusProbe.swift -framework AppKit -o dist/probes/focus-probe
	xcrun swiftc -swift-version 5 Tools/InputProbe.swift -framework AppKit -o dist/probes/input-probe
	xcrun swiftc -swift-version 5 -parse-as-library Tools/ScreenCaptureProbe.swift -framework AppKit -framework ScreenCaptureKit -framework CoreImage -framework CoreMedia -framework CoreVideo -o dist/probes/capture-probe
