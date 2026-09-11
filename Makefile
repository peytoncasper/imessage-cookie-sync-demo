.DEFAULT_GOAL := help
.PHONY: help setup doctor generate check test-swift test-python test-backend build-simulator clean

help:
	@echo 'make setup           Install backend dependencies and generate the Xcode project'
	@echo 'make doctor          Check local prerequisites and configuration'
	@echo 'make check           Run native, Python, and backend checks (no live services)'
	@echo 'make build-simulator Build the standalone iMessage app without signing'
	@echo 'make generate        Regenerate Xcode files after editing project.yml'
	@echo 'make clean           Remove generated local build output'

setup:
	@bash Scripts/setup.sh

doctor:
	@python3 Scripts/doctor.py

generate:
	xcodegen generate

check: test-swift test-python test-backend

test-swift:
	@bash Scripts/test-swift.sh

test-python:
	python3 -m unittest discover -s Tests -p 'test_*.py'

test-backend:
	npm --prefix vercel-cookie-loader test
	npm --prefix vercel-cookie-loader run build

build-simulator: generate
	xcodebuild -project CookieClipDemo.xcodeproj -scheme HNMessages -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/Simulator CODE_SIGNING_ALLOWED=NO build

clean:
	rm -rf build/
