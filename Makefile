.PHONY: help release-image dev-image dev publish clean

.DEFAULT_GOAL := release-image

help: ## Show available targets
	@printf 'Usage: make [target]\n\nAvailable targets:\n'
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  %-15s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

release-image: ## Build a publishable release image (default)
	./scripts/build.sh

dev-image: ## Build a local development image
	./scripts/build-dev.sh

dev: dev-image ## Build a local development image (alias for dev-image)

publish: ## Publish the most recent release image
	./scripts/publish.sh

clean: ## Remove local release and development images
	./scripts/cleanup-images.sh
