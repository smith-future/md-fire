.PHONY: project build run open clean

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

clean:
	rm -rf build DerivedData md-fire.xcodeproj
