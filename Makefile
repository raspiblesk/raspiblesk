SHELL = /bin/bash
GITHUB_ACTOR = $(shell git remote -v | grep origin | head -1 | cut -d/ -f4)
GITHUB_HEAD_REF = $(shell git rev-parse --abbrev-ref HEAD)
# set to local glcoin source until published: make arm64-rpi-lean-image GLCOIN_SOURCE=/home/ricpor/hacking/glcoin
GLCOIN_SOURCE ?=
GLCOIN_SOURCE_ARG = $(if $(GLCOIN_SOURCE),--glcoin_source_path $(GLCOIN_SOURCE),)

amd64-lean-desktop-uefi-image:
	# Run the build script
	cd ci/amd64 && \
	sudo bash packer.build.amd64-debian.sh \
	  --pack lean \
	  --github_user $(GITHUB_ACTOR) \
	  --branch $(GITHUB_HEAD_REF) \
	  --preseed_file preseed.cfg \
	  --boot uefi \
	  --desktop gnome \
	  $(GLCOIN_SOURCE_ARG)

	# Compute the checksum of the qemu image
	cd ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu && \
	sha256sum raspiblesk-amd64-debian-lean.qcow2 > raspiblesk-amd64-debian-lean.qcow2.sha256

	# Compress the image
	cd ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu && \
	gzip -v9 raspiblesk-amd64-debian-lean.qcow2

	# Compute the checksum of the compressed image
	cd ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu && \
	sha256sum raspiblesk-amd64-debian-lean.qcow2.gz > raspiblesk-amd64-debian-lean.qcow2.gz.sha256

	# List the generated files
	ls -lah ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu/raspiblesk-amd64-debian-lean.qcow2.*

amd64-lean-desktop-uefi-img:
	# Run the build script
	cd ci/amd64 && \
	sudo bash packer.build.amd64-debian.sh \
	  --pack lean \
	  --github_user $(GITHUB_ACTOR) \
	  --branch $(GITHUB_HEAD_REF) \
	  --preseed_file preseed.cfg \
	  --boot uefi \
	  --desktop gnome \
	  --image_type raw \
	  $(GLCOIN_SOURCE_ARG)

	# Compute the checksum of the qemu image
	cd ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu && \
	sha256sum raspiblesk-amd64-debian-lean.img > raspiblesk-amd64-debian-lean.img.sha256

	# Compress the image
	cd ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu && \
	gzip -v9 raspiblesk-amd64-debian-lean.img

	# Compute the checksum of the compressed image
	cd ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu && \
	sha256sum raspiblesk-amd64-debian-lean.img.gz > raspiblesk-amd64-debian-lean.img.gz.sha256

	# List the generated files
	ls -lah ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu/raspiblesk-amd64-debian-lean.img.*

amd64-lean-server-legacyboot-image:
	# Run the build script
	cd ci/amd64 && \
	sudo bash packer.build.amd64-debian.sh \
	  --pack lean \
	  --github_user $(GITHUB_ACTOR) \
	  --branch $(GITHUB_HEAD_REF) \
	  --preseed_file preseed.cfg \
	  --boot bios-256k.bin \
	  --desktop none \
	  $(GLCOIN_SOURCE_ARG)

	# Compute the checksum of the qemu image
	cd ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu && \
	sha256sum raspiblesk-amd64-debian-lean.qcow2 > raspiblesk-amd64-debian-lean.qcow2.sha256

	# Compress the image
	cd ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu && \
	gzip -v9 raspiblesk-amd64-debian-lean.qcow2

	# Compute the checksum of the compressed image
	cd ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu && \
	sha256sum raspiblesk-amd64-debian-lean.qcow2.gz > raspiblesk-amd64-debian-lean.qcow2.gz.sha256

	# List the generated files
	ls -lah ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu/raspiblesk-amd64-debian-lean.qcow2.*

amd64-fatpack-desktop-uefi-image:
	# Run the build script
	cd ci/amd64 && \
	sudo bash packer.build.amd64-debian.sh \
	  --pack fatpack \
	  --github_user $(GITHUB_ACTOR) \
	  --branch $(GITHUB_HEAD_REF) \
	  --preseed_file preseed.cfg \
	  --boot uefi \
	  --desktop gnome \
	  $(GLCOIN_SOURCE_ARG)

	# Compute the checksum of the qemu image
	cd ci/amd64/builds/raspiblesk-amd64-debian-fatpack-qemu && \
	sha256sum raspiblesk-amd64-debian-fatpack.qcow2 > raspiblesk-amd64-debian-fatpack.qcow2.sha256

	# Compress the image
	cd ci/amd64/builds/raspiblesk-amd64-debian-fatpack-qemu && \
	gzip -v9 raspiblesk-amd64-debian-fatpack.qcow2

	# Compute the checksum of the compressed image
	cd ci/amd64/builds/raspiblesk-amd64-debian-fatpack-qemu && \
	sha256sum raspiblesk-amd64-debian-fatpack.qcow2.gz > raspiblesk-amd64-debian-fatpack.qcow2.gz.sha256

	# List the generated files
	ls -lah ci/amd64/builds/raspiblesk-amd64-debian-lean-qemu/raspiblesk-amd64-debian-fatpack.qcow2.*

arm64-rpi-lean-image:
	# Run the build script
	cd ci/arm64-rpi && \
	sudo bash packer.build.arm64-rpi.local.sh \
	  --pack lean \
	  --github_user $(GITHUB_ACTOR) \
	  --branch $(GITHUB_HEAD_REF) \
	  $(GLCOIN_SOURCE_ARG)

	# Compute the checksum of the raw image
	cd ci/arm64-rpi/packer-builder-arm && \
	sha256sum raspiblesk-arm64-rpi-lean.img > raspiblesk-arm64-rpi-lean.img.sha256

	# Compress the image
	cd ci/arm64-rpi/packer-builder-arm  && \
	gzip -v9 raspiblesk-arm64-rpi-lean.img

	# Compute the checksum of the compressed image
	cd ci/arm64-rpi/packer-builder-arm  && \
	sha256sum raspiblesk-arm64-rpi-lean.img.gz > raspiblesk-arm64-rpi-lean.img.gz.sha256

	# List the generated files
	ls -lah ci/arm64-rpi/packer-builder-arm/raspiblesk-arm64-rpi-lean.img.*

arm64-rpi-fatpack-image:
	# Run the build script
	cd ci/arm64-rpi && \
	bash packer.build.arm64-rpi.local.sh \
	  --pack fatpack \
	  --github_user $(GITHUB_ACTOR) \
	  --branch $(GITHUB_HEAD_REF) \
	  $(GLCOIN_SOURCE_ARG)

	# Compute the checksum of the raw image
	cd ci/arm64-rpi/packer-builder-arm  && \
	sha256sum raspiblesk-arm64-rpi-fatpack.img > raspiblesk-arm64-rpi-fatpack.img.sha256

	# Compress the image
	cd ci/arm64-rpi/packer-builder-arm  && \
	gzip -v9 raspiblesk-arm64-rpi-fatpack.img

	# Compute the checksum of the compressed image
	cd ci/arm64-rpi/packer-builder-arm  && \
	sha256sum raspiblesk-arm64-rpi-fatpack.img.gz > raspiblesk-arm64-rpi-fatpack.img.gz.sha256

	# List the generated files
	ls -lah ci/arm64-rpi/packer-builder-arm/raspiblesk-arm64-rpi-fatpack.img.*
