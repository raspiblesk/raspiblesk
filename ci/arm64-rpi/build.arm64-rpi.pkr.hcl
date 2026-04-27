variable "pack" { default = "lean" }
variable "github_user" { default = "raspiblesk" }
variable "branch" { default = "dev" }
variable "image_link" { default = "https://downloads.raspberrypi.com/raspios_arm64/images/raspios_arm64-2026-04-21/2026-04-21-raspios-trixie-arm64.img.xz" }
variable "image_checksum" { default = "2b016db1eafc3f642eacfe5a1d9bf9e49be8b8caa0360c293901bf7b88bdebca" }
variable "image_size" { default = "24G" }

source "arm" "raspiblesk-arm64-rpi" {
  file_checksum_type    = "sha256"
  file_checksum         = var.image_checksum
  file_target_extension = "xz"
  file_unarchive_cmd    = ["xz", "--decompress", "$ARCHIVE_PATH"]
  file_urls             = [var.image_link]
  image_build_method    = "resize"
  image_chroot_env      = ["PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"]
  image_partitions {
    filesystem   = "vfat"
    mountpoint   = "/boot"
    name         = "boot"
    size         = "256M"
    start_sector = "8192"
    type         = "c"
  }
  image_partitions {
    filesystem   = "ext4"
    mountpoint   = "/"
    name         = "root"
    size         = "0"
    start_sector = "532480"
    type         = "83"
  }
  image_path                   = "raspiblesk-arm64-rpi-${var.pack}.img"
  image_size                   = var.image_size
  image_type                   = "dos"
  qemu_binary_destination_path = "/usr/bin/qemu-arm-static"
  qemu_binary_source_path      = "/usr/bin/qemu-arm-static"
}

build {
  sources = ["source.arm.raspiblesk-arm64-rpi"]

  dynamic "provisioner" {
    for_each = var.glcoin_source_path != "" ? [1] : []
    labels   = ["file"]
    content {
      source      = var.glcoin_source_path
      destination = "/tmp/glcoin-src"
    }
  }

  provisioner "shell" {
    inline = [
      "echo 'nameserver 1.1.1.1' > /etc/resolv.conf",
      "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf",
      "echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections",
      "apt-get update",
      "apt-get install -y sudo wget",
      "apt-get -y autoremove",
      "apt-get -y clean",
      "touch /boot/ssh",
      "echo 'pi:$6$TE7HmruYY9EaNiKP$Vz0inJ6gaoJgJvQrC5z/HMDRMTN2jKhiEnG83tc1Jsw7lli5MYdeA83g3NOVCsBaTVW4mUBiT/1ZRWYdofVQX0' > /boot/userconf"
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "github_user=${var.github_user}",
      "branch=${var.branch}",
      "pack=${var.pack}"
    ]
    script = "./build.raspiblesk.sh"
  }

  provisioner "shell" {
    inline = [
      "echo '# delete the SSH keys (will be recreated on the first boot)'",
      "rm -f /etc/ssh/ssh_host_*",
      "echo 'OK'",
    ]
  }

  provisioner "shell" {
    inline = [
      "if [ \"${var.pack}\" = \"base\" ]; then echo 'Adding stop file to /boot/'; touch /boot/stop; fi"
    ]
  }
}
