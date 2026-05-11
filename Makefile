SHELL := /bin/bash

.PHONY: build check clean format lint package run setup-signing setup-xcode test

build:
	swift build

test:
	swift test

run:
	./Scripts/run.sh

package:
	./Scripts/package_app.sh

setup-signing:
	./Scripts/setup_local_signing.sh

setup-xcode:
	./Scripts/setup_xcode_run.sh

format:
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat .; \
	else \
		echo "swiftformat not installed (brew install swiftformat)"; exit 1; \
	fi

lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint --quiet; \
	else \
		echo "swiftlint not installed (brew install swiftlint)"; exit 1; \
	fi

check: build test

clean:
	rm -rf .build ZODSol.app
