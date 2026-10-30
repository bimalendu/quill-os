#!/bin/bash

set -euxo pipefail

#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

#======================================
# Greeting...
#--------------------------------------
echo "Configure image: [$kiwi_iname]-[$kiwi_profiles]..."

#======================================
# Set SELinux booleans
#--------------------------------------
## Fixes KDE Plasma, see rhbz#2058657
setsebool -P selinuxuser_execmod 1

#======================================
# Clear machine specific configuration
#--------------------------------------
## Clear machine-id on pre generated images
rm -f /etc/machine-id
echo 'uninitialized' > /etc/machine-id
## remove random seed, the newly installed instance should make its own
rm -f /var/lib/systemd/random-seed

#======================================
# Configure grub correctly
#--------------------------------------
## Disable submenus to match Fedora
echo "GRUB_DISABLE_SUBMENU=true" >> /etc/default/grub
## Disable recovery entries to match Fedora
echo "GRUB_DISABLE_RECOVERY=true" >> /etc/default/grub
## Disable OS prober. OS selection on apple silicon systems has to go through
## the native startup disk selection
echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub

if [[ "$kiwi_profiles" == *"-Desktop"* ]]; then
	## Enable menu_auto_hide to match Fedora anaconda installs
	## Set boot_success to avoid displaying the grub menu on first boot
	grub2-editenv /boot/grub2/grubenv set menu_auto_hide=1 boot_indeterminate=1
fi

#======================================
# Delete & lock the root user password
#--------------------------------------
passwd -d root
passwd -l root

#======================================
# Setup default services
#--------------------------------------

## Enable persistent journal
mkdir -p /var/log/journal

#======================================
# Setup firstboot initial setup
#--------------------------------------

if [[ "$kiwi_profiles" != *"GNOME"* ]] && [[ "$kiwi_profiles" != *"KDE"* ]]; then
	## Enable initial-setup
	systemctl enable initial-setup.service
	## Enable reconfig mode
	touch /etc/reconfigSys
fi

## Enable swap setup on firstboot
systemctl enable asahi-setup-swap-firstboot.service

## Enable extras install on firstboot; this will only run if the extras are
## actually present (and self disable afterwards)
systemctl enable asahi-extras-firstboot.service

#======================================
# Setup default target
#--------------------------------------
if [[ "$kiwi_profiles" == *"GNOME"* ]] || [[ "$kiwi_profiles" == *"KDE"* ]]; then
	systemctl set-default graphical.target
else
	systemctl set-default multi-user.target
fi

#======================================
# Import GPG keys
#--------------------------------------

releasever=$(rpm --eval '%{fedora}')
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-primary
echo "Packages within this disk image"
rpm -qa --qf '%{size}\t%{name}-%{version}-%{release}.%{arch}\n' |sort -rn

# Note that running rpm recreates the rpm db files which aren't needed or wanted
rm -f /var/lib/rpm/__db*

#======================================
# Override `DEFAULTKERNEL` in /etc/sysconfig/kernel
# The file is now owned by grubby
#======================================
sed -i 's:\(DEFAULTKERNEL=\)kernel-core:\1kernel-16k-core:' /etc/sysconfig/kernel

#======================================
# Generate boot.bin
#======================================
update-m1n1 /boot/efi/m1n1/boot.bin
rm /boot/efi/.builder

exit 0
