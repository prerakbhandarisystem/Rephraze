APP := build/Rephraze.app
INSTALLED := /Applications/Rephraze.app

.PHONY: all build run install uninstall cert test clean status

all: build

## Build the .app bundle into build/
build:
	@./scripts/bundle.sh

## Build, then relaunch it
run: build
	@pkill -x Rephraze 2>/dev/null || true
	@open $(APP)
	@echo "Running. Look for the wand icon in your menu bar."

## Copy to /Applications and launch from there
install: build
	@pkill -x Rephraze 2>/dev/null || true
	@rm -rf $(INSTALLED)
	@cp -R $(APP) $(INSTALLED)
	@open $(INSTALLED)
	@echo "Installed to $(INSTALLED)"

uninstall:
	@pkill -x Rephraze 2>/dev/null || true
	@rm -rf $(INSTALLED)
	@echo "Removed $(INSTALLED)"

## One-time: create the stable signing identity (see scripts/make-cert.sh)
cert:
	@./scripts/make-cert.sh

## Run unit tests.
##
## Xcode is not installed here, so XCTest does not exist. We use swift-testing,
## which ships inside Command Line Tools -- but not on any default search path,
## so the compiler and dyld both need pointing at it explicitly.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIBS := /Library/Developer/CommandLineTools/Library/Developer/usr/lib

test:
	@swift test \
		-Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
		-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS) \
		-Xlinker -rpath -Xlinker $(CLT_LIBS)

clean:
	@rm -rf .build build
	@echo "Cleaned."

## Show signing identity, permission state, and fn key setup
status:
	@echo "Signing identity:"
	@probe=$$(mktemp); cp /bin/echo $$probe; \
	if codesign --force --sign "Rephraze Dev" --timestamp=none $$probe >/dev/null 2>&1; then \
		echo "    Rephraze Dev - stable, permission survives rebuilds"; \
	else \
		echo "    none - builds are ad-hoc signed, permission resets each rebuild (run 'make cert')"; \
	fi; rm -f $$probe
	@echo
	@echo "Built app signature:"
	@codesign -dv $(APP) 2>&1 | grep -E 'Identifier|Signature=' | sed 's/^/    /' \
		|| echo "    not built yet"
	@echo
	@echo
	@echo "Running:"
	@pgrep -x Rephraze >/dev/null && echo "    yes, pid $$(pgrep -x Rephraze)" || echo "    no"
