# TrazaBox Makefile
# Automate build and deployment tasks

.PHONY: help build clean deploy upload version bump-patch bump-minor bump-major run-dev

# Flutter command (handles snap installation)
FLUTTER := $(shell which flutter 2>/dev/null || echo "snap run flutter")

# Default target
help:
	@echo "TrazaBox Build & Deploy Commands"
	@echo "================================"
	@echo ""
	@echo "Building:"
	@echo "  make build          - Build release APK"
	@echo "  make build-split    - Build split APKs per ABI (smaller)"
	@echo "  make clean          - Clean build artifacts"
	@echo ""
	@echo "Versioning:"
	@echo "  make version        - Show current version"
	@echo "  make bump           - Bump build number"
	@echo "  make bump-patch     - Bump patch version (1.0.0 -> 1.0.1)"
	@echo "  make bump-minor     - Bump minor version (1.0.0 -> 1.1.0)"
	@echo "  make bump-major     - Bump major version (1.0.0 -> 2.0.0)"
	@echo ""
	@echo "Deployment:"
	@echo "  make upload         - Upload existing APK to Supabase"
	@echo "  make deploy         - Bump version, build, and upload"
	@echo "  make deploy-patch   - Deploy with patch version bump"
	@echo "  make deploy-minor   - Deploy with minor version bump"
	@echo "  make deploy-major   - Deploy with major version bump"
	@echo ""
	@echo "Development:"
	@echo "  make run-dev        - Run app in debug mode"
	@echo "  make deps           - Install dependencies"
	@echo "  make doctor         - Run flutter doctor"
	@echo ""
	@echo "Options:"
	@echo "  NOTES=\"message\"     - Add release notes to deploy/upload"
	@echo "  make deploy NOTES=\"Bug fixes\""
	@echo ""

# Build commands
build:
	$(FLUTTER) build apk --release

build-split:
	$(FLUTTER) build apk --split-per-abi --release

clean:
	$(FLUTTER) clean
	rm -rf build/

# Version commands
version:
	python3 scripts/deploy.py version

bump:
	python3 scripts/deploy.py bump --part build

bump-patch:
	python3 scripts/deploy.py bump --part patch

bump-minor:
	python3 scripts/deploy.py bump --part minor

bump-major:
	python3 scripts/deploy.py bump --part major

# Deploy commands
upload:
	python3 scripts/deploy.py upload $(if $(NOTES),--notes "$(NOTES)")

deploy:
	python3 scripts/deploy.py deploy --part build $(if $(NOTES),--notes "$(NOTES)")

deploy-patch:
	python3 scripts/deploy.py deploy --part patch $(if $(NOTES),--notes "$(NOTES)")

deploy-minor:
	python3 scripts/deploy.py deploy --part minor $(if $(NOTES),--notes "$(NOTES)")

deploy-major:
	python3 scripts/deploy.py deploy --part major $(if $(NOTES),--notes "$(NOTES)")

# Development commands
run-dev:
	$(FLUTTER) run

deps:
	$(FLUTTER) pub get

doctor:
	$(FLUTTER) doctor -v
