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

## One-time: stop macOS asking for your password on every build.
##
## macOS needs TWO grants before codesign may use a signing key:
##   1. the ACL          -- set by `security import -T /usr/bin/codesign`
##   2. the partition list -- a separate, newer mechanism, set here
## Without (2), codesign shows a password dialog on every single build.
##
## You will be asked for your login password ONCE, in the terminal.
trust-key:
	@echo "codesign needs one-time permission to use your signing key."
	@echo "Type your Mac login password below. This happens once, ever."
	@echo
	@security set-key-partition-list \
		-S apple-tool:,apple:,codesign: \
		-s $(HOME)/Library/Keychains/login.keychain-db >/dev/null 2>&1 \
		&& echo "Done. No more password prompts." \
		|| echo "Did not apply. Next time codesign asks, click 'Always Allow'."
	@echo
	@printf "Verifying... "
	@probe=$$(mktemp); cp /bin/echo $$probe; \
	start=$$(date +%s); \
	codesign --force --sign "Rephraze Dev" --timestamp=none $$probe >/dev/null 2>&1; \
	elapsed=$$(( $$(date +%s) - $$start )); \
	rm -f $$probe; \
	if [ $$elapsed -le 1 ]; then echo "instant - fixed."; \
	else echo "still took $${elapsed}s - a prompt is still appearing."; fi

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
