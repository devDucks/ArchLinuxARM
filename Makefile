PLATFORMS?=linux/arm64
IMAGE?=archlinuxarm

.PHONY: qemu
qemu:
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

.PHONY: build-rpi-aarch64
build-rpi-aarch64:
	$(MAKE) build-aarch64 kind=rpi-aarch64 kernel=linux-rpi

.PHONY: build-generic-aarch64
build-generic-aarch64:
	$(MAKE) build-aarch64 kind=generic-aarch64 kernel=linux-aarch64

.PHONY: build-aarch64
build-aarch64:
	docker buildx build \
          --build-arg KERNEL=$(kernel) \
	  --platform $(PLATFORMS) \
	  -t $(IMAGE):$(kind) \
          -f dockerfiles/Dockerfile.aarch64 \
          --load \
	  .

.PHONY: export
export:
	docker buildx build \
          --platform $(PLATFORMS) \
          -t $(IMAGE):minimal-aarch64-export \
          -f dockerfiles/Dockerfile.base \
	  --target export \
          --load .

.PHONY: export-rpi
export-rpi:
	docker buildx build \
          --platform $(PLATFORMS) \
          -t $(IMAGE):rpi-aarch64-export \
          -f dockerfiles/Dockerfile.aarch64 \
	  --target export \
          --load .

.PHONY: create-rootfs-container
create-rootfs-container:
	docker create --platform=linux/arm64 --name take $(IMAGE):generic-aarch64 sh

.PHONY: copy-rootfs-tar
copy-rootfs-tar:
	docker cp take:/archlinuxarm-rpi-aarch64-rootfs.tar ./rootfs.tar
	docker rm -f take

.PHONY: prepare-rpi-img
prepare-rpi-image: create-rootfs-container copy-rootfs-tar
	./scripts/build_img.sh
