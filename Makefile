.PHONY: project build run open dmg clean

# Regenerate md-fire.xcodeproj from project.yml (source of truth).
project:
	xcodegen generate

# Build the app from the command line.
build: project
	xcodebuild -project md-fire.xcodeproj -scheme md-fire -configuration Debug build

# Build and launch the app.
run: build
	@APP=$$(xcodebuild -project md-fire.xcodeproj -scheme md-fire -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$$3} / FULL_PRODUCT_NAME /{n=$$3} END{print d"/"n}'); \
	echo "launching $$APP"; open "$$APP"

# Open the project in Xcode.
open: project
	open md-fire.xcodeproj

# Build a Release app and package the distributable md-fire.dmg.
dmg: project
	xcodebuild -project md-fire.xcodeproj -scheme md-fire -configuration Release \
		-derivedDataPath .build-release build
	./scripts/make-dmg.sh

clean:
	rm -rf build DerivedData md-fire.xcodeproj
