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

.PHONY: export
export:
	docker buildx build \
          --platform $(PLATFORMS) \
          -t $(IMAGE):minimal-aarch64-export \
          -f dockerfiles/Dockerfile.base.aarch64 \
	  --target export \
          --load .

.PHONY: create-rootfs-container
create-rootfs-container:
	docker create --platform=linux/arm64 --name take $(IMAGE):minimal-aarch64-export sh

.PHONY: copy-rootfs-tar
copy-rootfs-tar:
	docker cp take:/archlinuxarm-aarch64-rootfs.tar ./rootfs.tar
	docker rm -f take

.PHONY: prepare-rpi-img
prepare-rpi-image: export create-rootfs-container copy-rootfs-tar
	./scripts/build_img.sh
