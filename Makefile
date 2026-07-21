.PHONY: build test app run clean

build:
	swift build

test:
	swift run QuickVaultChecks

app:
	./Scripts/package-app.sh

run: app
	open dist/benri.app

clean:
	swift package clean
	rm -rf dist
