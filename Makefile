# ThoughtMeter — developer entry points. No Xcode required (see CONTRIBUTING.md).

.PHONY: bootstrap generate dev test build package verify privacy-check \
        install-local uninstall-local release clean

bootstrap: ## Check development dependencies
	@scripts/bootstrap.sh

generate: ## Generate an Xcode project (optional; requires xcodegen)
	@command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not installed (brew install xcodegen). The SPM build does not need it."; exit 1; }
	xcodegen generate

dev: ## Build a debug bundle and launch it
	@scripts/dev.sh

test: ## Run all automated tests (Swift + extension)
	@scripts/test.sh

build: ## arm64 release build + assembled dist/ThoughtMeter.app (cert-signed when the identity exists, else ad-hoc)
	@scripts/build.sh release

package: build ## DMG + ZIP + extension zip + checksums + cask in dist/
	@scripts/package.sh

verify: ## Verify bundle structure, arch, signature, privacy, network
	@scripts/verify.sh

privacy-check: ## Scan sources for forbidden APIs and patterns
	@scripts/verify-privacy.sh

install-local: build ## Copy the app to /Applications and register the native host
	@rm -rf /Applications/ThoughtMeter.app
	@cp -R dist/ThoughtMeter.app /Applications/ThoughtMeter.app
	@echo "installed /Applications/ThoughtMeter.app"
	@scripts/install-native-host.sh --app /Applications/ThoughtMeter.app || true

uninstall-local: ## Remove the local development installation (keeps data)
	@scripts/uninstall-native-host.sh
	@rm -rf /Applications/ThoughtMeter.app
	@echo "removed /Applications/ThoughtMeter.app (data kept; use scripts/uninstall.sh --with-data to remove it)"

release: ## Full release pipeline: tests, build, package, verify, checklist
	@scripts/release.sh $(VERSION)

clean:
	rm -rf .build dist

help:
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'
