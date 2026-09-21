.PHONY: help image image-dev image-push clean

.DEFAULT_GOAL := image

IMAGE_MODE ?= versioned

help: ## Show available targets
	@printf 'Usage: make [target]\n\nAvailable targets:\n'
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  %-15s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

image: ## Build the container image locally (default; IMAGE_MODE=versioned|dev)
	@case "$(IMAGE_MODE)" in \
		versioned) exec sh ./scripts/image.sh ;; \
		dev) exec sh ./scripts/image.sh --dev ;; \
		*) printf 'Error: unsupported IMAGE_MODE: %s\nExpected versioned or dev.\n' "$(IMAGE_MODE)" >&2; exit 2 ;; \
	esac

image-dev: IMAGE_MODE := dev
image-dev: image ## Build a local development image

image-push: ## Push the most recent versioned image to GHCR (external publication)
	sh ./scripts/image-push.sh

clean: ## Remove local versioned and development images
	sh ./scripts/cleanup-images.sh
