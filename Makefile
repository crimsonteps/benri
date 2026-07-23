.PHONY: build test app release run clean

build:
	swift build

test:
	swift run BenriChecks

app:
	./Scripts/package-app.sh

release:
	./Scripts/create-release.sh

run: app
	open dist/Benri.app

clean:
	swift package clean
	rm -rf dist
