You are going to make the iso/image file of hyprflux, currently the hyprflux is dotfiles distribution, so I am planing to make it complete operating system of archlinux

I want an iso that first install the base archlinux using archiso/archinstall and then

start installing the hyprflux, hyprflux configured to install the arch-hyprland and hyprland-dots repos like in diagram

so I want Iso that has that handle all of that, automatically,

for ISO UI I want: TUI Installer (that prompts (questions if needed) and handle the rest)

also I want UI to like omarchy very big logo of HyprFlux on top and Center and Instllation output below the logo like in image,

also work first understand the HyprFlux files to get deeper understanding

don't need to make it in single shot, make the deep plan and store in multiple mds(markdown file in seperate folder) divided in multiple phases so we can on each phase

so you first task to write extremely detailed plans in phases stored in mds and We will work on each phase one by one

Repo Instructions

- First it install the base archlinux and then start the HyprFlux
- HyprFlux: clones the Arch-Hyprland and then Hyprland-Dotes
- Then Apply custom dotfiles

- TUI Installer (that prompts and handle the rest)
- Both UEFI and BISO/Lagecy Support
- Two Option for Partition
  - Automatic
  - Manual (EFI/Swap/Root)

also handle the archiso things like timezone search keyboard layout search and other things we need
