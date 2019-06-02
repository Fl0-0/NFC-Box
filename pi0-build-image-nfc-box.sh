#!/bin/bash

# Based on scipt pi-builder created by Chris Blake, https://github.com/riptidewave93 , 2013-10-17
# 
# Modified by Flo & Stan 2017-03-15 for Rapsberry Pi 0 Raspbian Jessie image with NFC tools a GUI
# 
# Required Debian Packages: binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools xz-utils
#
# V1.1: Add ssh server and cdc_ether USB gadget to access the Box over Pi Zero OTG USB port
# 
# To Do: Error Checking

# Date format, used in the image file name
mydate=`date +%Y%m%d-%H%M`

# Size of the image and boot partitions
imgsize="1800M"
bootsize="64M"

# Location of the build environment, where the image will be mounted during build
basedir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
buildenv="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/BuildEnv"


distrib_name="raspbian"
deb_mirror="http://archive.raspbian.org/raspbian"
deb_release="buster"
deb_arch="armhf"
echo "PI-BUILDER: Building $distrib_name Image"

# Check to make sure this is ran by root
if [ $EUID -ne 0 ]; then
  echo "PI-BUILDER: this tool must be run as root"
  exit 1
fi

# make sure no builds are in process (which should never be an issue)
if [ -e ./.pibuild-$1 ]; then
	echo "PI-BUILDER: Build already in process, aborting"
	exit 1
else
	touch ./.pibuild-$1
fi

# Create the buildenv folder
mkdir -p $buildenv
cd $buildenv

#  start the debootstrap of the system
echo "PI-BUILDER: debootstraping..."
debootstrap --no-check-gpg --foreign --arch $deb_arch $deb_release $buildenv $deb_mirror
cp /usr/bin/qemu-arm-static usr/bin/

# Copy files before chroot
cp -r $basedir/nfc_box root/
cp $basedir/mfoc usr/bin/

LANG=C chroot $buildenv /debootstrap/debootstrap --second-stage

# Start adding content to the system files
echo "PI-BUILDER: Setting up custom files/settings relating to rpi"

# apt mirrors
echo "deb $deb_mirror $deb_release main contrib non-free
deb-src $deb_mirror $deb_release main contrib non-free" > etc/apt/sources.list

# Boot commands
echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 init=/bin/systemd elevator=deadline fsck.repair=yes rootwait quiet fastboot noswap ro" > boot/cmdline.txt

# Set gpu_mem to minimum, enable turbo mode, disable HDMI output, enable SPI & i2c
echo "gpu_mem=16
force_turbo=1
dtoverlay=pi3-disable-bt
dtoverlay=pi3-disable-wifi
dtoverlay=dwc2
dtparam=spi=on
dtparam=i2c_arm=on
disable_splash=1
hdmi_blanking=2
#dtparam=act_led_trigger=none
#dtparam=act_led_activelow=on" > boot/config.txt

# Modules: load spi-dev, i2c-dev and g_ether
echo "i2c-dev
dwc2
g_ether" >> etc/modules

# IBM Remote USB RNDIS vendor and product IDs for Windows auto detection
echo "options g_ether idVendor=0x04b3 idProduct=0x4010
" > etc/modprobe.d/g_ether.conf

# Mounts
echo "proc            /proc           proc    defaults        0       0
/dev/mmcblk0p1  /boot           vfat    defaults,ro        0       0
/dev/mmcblk0p2	/				ext4	noatime,ro		0		1
tmpfs	/var/log	tmpfs	nodev,nosuid	0	0
tmpfs	/var/tmp	tmpfs	nodev,nosuid	0	0
tmpfs	/var/lib/dhcp	tmpfs   nodev,nosuid    0       0
tmpfs	/tmp	tmpfs	nodev,nosuid	0	0
" > etc/fstab

# Hostname
host_name="pi0"
echo "${host_name}" > etc/hostname
echo "127.0.1.1	${host_name}" >> etc/host

# Networking
echo "auto lo
iface lo inet loopback

#iallow-hotplug eth0
#iface eth0 inet dhcp
#iface eth0 inet6 dhcp
auto usb0
allow-hotplug usb0
iface usb0 inet static
address 192.168.2.1
netmask 255.255.255.0
#gateway 192.168.2.1
" > etc/network/interfaces

# Console settings
echo "console-common	console-data/keymap/policy	select	Select keymap from full list
console-common	console-data/keymap/full	select	us
" > debconf.set

echo "#!/bin/sh -e
/root/nfc_box/menu_nfcbox.py &
exit 0
" > usr/bin/menu_nfcbox.sh
chmod +x usr/bin/menu_nfcbox.sh
cat << EOF > lib/systemd/system/nfc-box.service
[Unit]
Description=NFC Box Graphical interface
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/menu_nfcbox.sh
[Install]
WantedBy=multi-user.target
EOF
chmod +x lib/systemd/system/nfc-box.service

# Third Stage Setup Script (most of the setup process)
echo "#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update
apt-get -y install binutils wget curl locales console-common \
libnfc-bin i2c-tools rng-tools \
python-minimal python-smbus python-pip python-dev libfreetype6-dev libjpeg8-dev \
openssh-server isc-dhcp-server net-tools less vim bash-completion
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
apt-get -y dist-upgrade
apt-get -y install ttf-mscorefonts-installer
apt-get -y autoremove --purge
apt-get -y autoclean
pip install Pillow==4.1.1 RPi.GPIO luma.oled
chmod +x /root/nfc_box/menu_nfcbox.py
chmod +x /usr/bin/mfoc
chmod +x /root/nfc_box/remount-slash.sh
ln -s /root/nfc_box/remount-slash.sh /root/remount-slash.sh
wget https://raw.githubusercontent.com/Hexxeh/rpi-update/master/rpi-update -O /usr/bin/rpi-update
chmod +x /usr/bin/rpi-update
SKIP_WARNING=1 SKIP_BACKUP=1 UPDATE_SELF=0 CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt rpi-update
echo \"root:toor\" | chpasswd
echo 'HWCLOCKACCESS=no' >> /etc/default/hwclock
echo 'RAMTMP=yes' >> /etc/default/tmpfs
ln -sf /usr/lib/systemd/system/multi-user.target /etc/systemd/system/default.target
ln -s /tmp/random-seed /var/lib/systemd/random-seed
echo \"ExecStartPre=/bin/echo '' >/tmp/random-seed\" >> /lib/systemd/system/systemd-random-seed.service
mkdir /var/lib/systemd/coredump
rm /etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service
rm /etc/systemd/system/syslog.service
ln -sf ../proc/self/mounts /etc/mtab
sed -i -e 's/^INTERFACESv4=\"\"/INTERFACESv4=\"usb0\"/' /etc/default/isc-dhcp-server
sed -i -e 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^\"syntax on/syntax on/' /etc/vim/vimrc
echo 'HRNGDEVICE=/dev/hwrng' >> /etc/default/rng-tools
ln -sf /lib/systemd/system/nfc-box.service /etc/systemd/system/multi-user.target.wants/nfc-box.service
rm -f third-stage
" > third-stage
chmod +x third-stage
LANG=C chroot $buildenv /third-stage

echo 'ddns-update-style none;
option domain-name "domain.local";
option domain-name-servers 192.168.2.1;
default-lease-time 60;
max-lease-time 72;
authoritative;
subnet 192.168.2.0 netmask 255.255.255.0 {
range 192.168.2.2 192.168.2.10;
#/option routers 192.168.2.1;
}' > etc/dhcp/dhcpd.conf

echo "allow_autoscan = false
device.connstring=\"pn532_spi:/dev/spidev0.0:2000000\"" >> etc/nfc/libnfc.conf

echo "PI-BUILDER: Cleaning up build space/image"

# Cleanup Script
echo "#!/bin/bash
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
rm -rf /boot.bak
rm -f /usr/bin/qemu*
rm -r /root/.rpi-firmware > /dev/null 2>&1
rm -f cleanup
" > cleanup
chmod +x cleanup
LANG=C chroot $buildenv /cleanup

cd $basedir

# folders in the basedir to be mounted, one for rootfs, one for /boot
rootfs="${basedir}/rootfs"
bootfs="${rootfs}/boot"

# Create the image file
echo "PI-BUILDER: Creating Image file"
image="${basedir}/rpi_${distrib_name}_${deb_release}_${deb_arch}_${mydate}.img"
dd if=/dev/zero of=$image bs=$imgsize count=1
device=`losetup -f --show $image`
echo "PI-BUILDER: Image $image created and mounted as $device"

# Format the image file partitions
echo "PI-BUILDER: Setting up MBR/Partitions"
fdisk $device << EOF
n
p
1

+$bootsize
t
c
n
p
2


w
EOF

# Some systems need partprobe to run before we can fdisk the device
partprobe

# Mount the loopback device so we can modify the image, format the partitions, and mount/cd into rootfs
device=`kpartx -va $image | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
sleep 1 # Without this, we sometimes miss the mapper device!
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2
echo "PI-BUILDER: Formatting Partitions"
mkfs.vfat $bootp
mkfs.ext4 $rootp -L root
mkdir -p $rootfs
mount $rootp $rootfs
cd $rootfs
mkdir boot

# Mount the boot partition
mount -t vfat $bootp $bootfs

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${buildenv}/ ${rootfs}/
sync

# Unmount some partitions
echo "PI-BUILDER: Unmounting Partitions"
umount -l $bootp
umount -l $rootp
kpartx -d $image

# Properly terminate the loopback devices
echo "PI-BUILDER: Finished making the image $image"
dmsetup remove_all
losetup -D

cd $basedir

# Compressing with xz and terminating
echo "PI-BUILDER: Compressing, then terminating"
xz -9 -T 0 ./rpi_${distrib_name}_${deb_release}_${deb_arch}_${mydate}.img
rm ./.pibuild-$1
rm -Rf $buildenv
rm -Rf $rootfs
echo "PI-BUILDER: Finished!"
exit 0
