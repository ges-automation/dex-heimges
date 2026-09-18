.PHONY: release-image dev-image dev publish clean

.DEFAULT_GOAL := release-image

release-image:
	./scripts/build.sh

dev-image:
	./scripts/build-dev.sh

dev: dev-image

publish:
	./scripts/publish.sh

clean:
	./scripts/cleanup-images.sh
