FROM archlinux:latest
RUN printf '%s\n' \
    'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' \
    'Server = https://mirrors.mit.edu/archlinux/$repo/os/$arch' \
    'Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch' \
    > /etc/pacman.d/mirrorlist && \
    pacman -Syu --noconfirm && \
    pacman -S --needed --noconfirm archiso grub git python shellcheck
WORKDIR /project
