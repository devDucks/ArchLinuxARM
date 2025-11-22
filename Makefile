PLATFORMS?=linux/arm64
IMAGE?=archlinuxarm

.PHONY: binfmt
binfmt:
	docker run --privileged --rm tonistiigi/binfmt --install arm64

# --- Builds ---
.PHONY: build-minimal
build-minimal:
	docker buildx build \
	  --platform $(PLATFORMS) \
	  -t $(IMAGE):minimal-aarch64 \
          -f dockerfiles/Dockerfile.base \
          --target archarm \
          --load \
	  .

.PHONY: build-aarch64
build-aarch64: binfmt
	docker buildx build \
	  --platform $(PLATFORMS) \
	  -t $(IMAGE):generic-aarch64 \
          -f dockerfiles/Dockerfile.aarch64 \
	  --target builder \
          --load \
	  .

.PHONY: build-aarch64-rootfs
build-aarch64-rootfs: binfmt
	docker buildx build \
	  --platform $(PLATFORMS) \
	  -t $(IMAGE):generic-aarch64-rootfs \
          -f dockerfiles/Dockerfile.aarch64 \
	  --target export \
          --load \
	  .

.PHONY: build-astroarch
build-astroarch: binfmt
	docker buildx build \
	  --platform $(PLATFORMS) \
	  -t astroarch:latest \
          -f dockerfiles/Dockerfile.astroarch \
	  --target builder \
          --load \
	  .

.PHONY: build-astroarch-rootfs
build-astroarch-rootfs: binfmt
	docker buildx build \
	  --platform $(PLATFORMS) \
	  -t astroarch-rootfs:latest \
          -f dockerfiles/Dockerfile.astroarch \
	  --target astroarch-rootfs \
          --load \
	  .

.PHONY: create-rootfs-container
create-rootfs-container:
	docker create --platform=$(PLATFORMS) --name take astroarch-rootfs:latest sh

.PHONY: copy-rootfs-tar
copy-rootfs-tar:
	docker cp take:/astroarch-rootfs.tar ./rootfs.tar
	docker rm -f take

.PHONY: prepare-rpi-img
prepare-rpi-img: build-astroarch-rootfs create-rootfs-container copy-rootfs-tar
	./scripts/build_img.sh
