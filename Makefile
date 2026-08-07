.PHONY: build test lint format clean release

build:
	xcodebuild -scheme Notepad -configuration Debug

test:
	xcodebuild test -scheme Notepad -destination 'platform=macOS'

lint:
	swiftlint lint

format:
	swiftformat --config .swiftformat .

clean:
	xcodebuild clean -scheme Notepad
	rm -rf build/

release:
	./Scripts/release.sh
