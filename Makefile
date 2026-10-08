CONFIGURATION ?= Release
BUILD_DIR ?= $(CURDIR)/build
XCODE_FLAGS ?= CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=

.PHONY: build build-macos build-ios build-ios-device build-mcp build-ui-tests test format format-check docs-dev docs-check test-ui-cloudflare test-ui-godaddy test-ui-ionos test-ui-route53

build: build-macos build-ios

build-macos:
	xcodebuild -quiet -project DNSDeck.xcodeproj -scheme "DNSDeck macOS" -configuration $(CONFIGURATION) -destination 'generic/platform=macOS' -derivedDataPath '$(BUILD_DIR)/macOS' $(XCODE_FLAGS) build

build-ios:
	xcodebuild -quiet -project DNSDeck.xcodeproj -scheme "DNSDeck iOS" -configuration $(CONFIGURATION) -destination 'generic/platform=iOS Simulator' -derivedDataPath '$(BUILD_DIR)/iOS' $(XCODE_FLAGS) build

build-ios-device:
	xcodebuild -quiet -project DNSDeck.xcodeproj -scheme "DNSDeck iOS" -configuration $(CONFIGURATION) -destination 'generic/platform=iOS' -derivedDataPath '$(BUILD_DIR)/iOS-device' $(XCODE_FLAGS) build

build-mcp:
	swift build -c release --product DNSDeckMCP

build-ui-tests:
	xcodebuild -quiet -project DNSDeck.xcodeproj -scheme "DNSDeck macOS" -destination 'platform=macOS' -derivedDataPath '$(BUILD_DIR)/UITests' $(XCODE_FLAGS) build-for-testing

test:
	mkdir -p '$(BUILD_DIR)/profiles'
	LLVM_PROFILE_FILE='$(BUILD_DIR)/profiles/%p.profraw' swift test --package-path packages/apple-foundations
	LLVM_PROFILE_FILE='$(BUILD_DIR)/profiles/%p.profraw' swift test --package-path packages/apple-design-system

format:
	swiftformat DNSDeck DNSDeckMCP DNSDeckUITests Package.swift --config .swiftformat

format-check:
	swiftformat DNSDeck DNSDeckMCP DNSDeckUITests Package.swift --lint --config .swiftformat

docs-dev:
	npm run docs:dev

docs-check:
	npm run docs:check

test-ui-cloudflare:
	./scripts/run-provider-ui-test.sh CloudflareProviderUITests CLOUDFLARE

test-ui-godaddy:
	./scripts/run-provider-ui-test.sh GoDaddyProviderUITests GODADDY

test-ui-ionos:
	./scripts/run-provider-ui-test.sh IONOSProviderUITests IONOS

test-ui-route53:
	./scripts/run-provider-ui-test.sh Route53ProviderUITests ROUTE53
