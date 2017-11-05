#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo "Please pass version number, e.g. $0 2.0"
    exit 0
fi
#image version
imversion=$1
if [[ $# -eq 2 ]] ; then
  dev_path=$2
  isdevvalid=`fdisk -l | awk '$2 ~ /^\/dev\// {print $2}' | grep ${dev_path} `
  #echo $isdevvalid
  if [[ ! -z $isdevvalid ]]; then
    echo "$dev_path will be ereased!!! It's very dangrous! make sure passed correct device name."
    sleep 3
    read -p  "Sure to continue:No(Default),Yes " issure
    if [ ! $issure == "Yes" ]; then
      exit 0
    fi
  else
    echo "Wrong paramater. Second parameter should be device path. e.g. $0 2.0 /dev/sdc"
    exit 0
  fi
fi

imname=kali-$imversion-cubieboard1
basedir=`pwd`/${imname}
mkdir ${basedir}
echo "working dir:${basedir}"

cd ${basedir}
##################################################
#Download resources
##################################################
downloaddir=${basedir}/download
mkdir ${downloaddir}
imagesdir=${basedir}/images
mkdir ${imagesdir}
gcctool=gcc-linaro-7.1.1-2017.08-x86_64_arm-linux-gnueabihf
gccdir=${basedir}/${gcctool}
uBootdir=${downloaddir}/u-boot
linuxsunxidir=${downloaddir}/linux-sunxi

function prepare_env(){
  cd ${basedir}
  export PATH=${gccdir}/bin:${PATH}
  echo PATH:${PATH}

  architecture="armhf"
  # If you have your own preferred mirrors, set them here.
  # After generating the rootfs, we set the sources.list to the default settings.
  mirror=http.kali.org

  # Make sure that the cross compiler can be found in the path before we do
  # anything else, that way the builds don't fail half way through.
  export CROSS_COMPILE=arm-linux-gnueabihf-
  if [ $(compgen -c $CROSS_COMPILE | wc -l) -eq 0 ] ; then
      echo "Missing cross compiler. Set up PATH according to the README"
      exit 1
  fi
  # Unset CROSS_COMPILE so that if there is any native compiling needed it doesn't
  # get cross compiled.
  unset CROSS_COMPILE

  # Package installations for various sections.
  # This will build a minimal XFCE Kali system with the top 10 tools.
  # This is the section to edit if you would like to add more packages.
  # See http://www.kali.org/new/kali-linux-metapackages/ for meta packages you can
  # use. You can also install packages, using just the package name, but keep in
  # mind that not all packages work on ARM! If you specify one of those, the
  # script will throw an error, but will still continue on, and create an unusable
  # image, keep that in mind.

  arm="abootimg cgpt fake-hwclock ntpdate u-boot-tools vboot-utils vboot-kernel-utils"
  base="e2fsprogs initramfs-tools kali-defaults kali-menu parted sudo usbutils"
  desktop="fonts-croscore fonts-crosextra-caladea fonts-crosextra-carlito gnome-theme-kali gtk3-engines-xfce kali-desktop-xfce kali-root-login lightdm network-manager network-manager-gnome xfce4 xserver-xorg-video-fbdev"
  tools="aircrack-ng ethtool hydra john libnfc-bin mfoc nmap passing-the-hash sqlmap usbutils winexe wireshark"
  services="apache2 openssh-server"
  extras="iceweasel xfce4-terminal wpasupplicant"

  packages="${arm} ${base} ${desktop} ${tools} ${services} ${extras}"
}
prepare_env

function download_files(){
  echo "Start download files"
  cd ${downloaddir}
  #download kali-archive-keyring
  if [ ! -f ${downloaddir}/kali-archive-keyring_2015.2_all.deb ];then
  wget -P ${downloaddir} http://repo.kali.org/kali/pool/main/k/kali-archive-keyring/kali-archive-keyring_2015.2_all.deb
  fi
  #get kali debootstrap
  git clone --depth 1 git://git.kali.org/packages/debootstrap.git kali-debootstrap
  #use kali's debootstrap， but need to mask the setup_devices for new debootstrap
  #This may change in new version, only for current state.
  sed -i '77 s/setup_devices/# setup_devices/g'  ${downloaddir}/kali-debootstrap/scripts/kali

  #kali arm linux script
  cd ${downloaddir}
  git clone https://github.com/offensive-security/kali-arm-build-scripts

  #linaro gcc tool
  if [ ! -f ${downloaddir}/${gcctool}.tar.xz ];then
  wget https://releases.linaro.org/components/toolchain/binaries/7.1-2017.08/arm-linux-gnueabihf/${gcctool}.tar.xz
  tar -Jxvf ${gcctool}.tar.xz -C ${basedir}
  fi
  #get u-boot
  #mainline
  git clone git://git.denx.de/u-boot.git --depth=1
  cd ${uBootdir}
  git checkout v2017.05

  #get linux-sunxi
  #mainline
  cd ${downloaddir}
  git clone https://github.com/linux-sunxi/linux-sunxi.git -b sunxi-next --depth=1

  echo "All downloading finished..."
}


function kali_rootfs_stage1(){
  # Set this to use an http proxy, like apt-cacher-ng, and uncomment further down
  # to unset it.
  #export http_proxy="http://localhost:3142/"
  #install kali-archive-keyring to donwload debs.
  dpkg -i ${downloaddir}/kali-archive-keyring_2015.2_all.deb

  #cp ${downloaddir}/kali-debootstrap/scripts/kali ${debootstrapdir}/kali-rolling
  debootstrap --foreign --arch $architecture kali-rolling kali-$architecture http://$mirror/kali ${downloaddir}/kali-debootstrap/scripts/kali-rolling
  #install arm simulator to chroot directory
  cp /usr/bin/qemu-arm-static kali-$architecture/usr/bin/
  #install keyring in chroot direcotory
  #directly copy from local installed folder.
  mkdir -p kali-$architecture/usr/share/keyrings/
  cp /usr/share/keyrings/kali-archive-keyring.gpg kali-$architecture/usr/share/keyrings/
  #run debootstrap second-stage
  LANG=C chroot kali-$architecture /debootstrap/debootstrap --second-stage
}

function kali_rootfs_stage2(){
  #config kali system stage two
  if [ ! -d kali-$architecture/etc/apt/ ];then
      mkdir -p kali-$architecture/etc/apt/
  fi

  cat << EOF > kali-$architecture/etc/apt/sources.list
  deb http://$mirror/kali kali-rolling main contrib non-free
EOF

  echo "kali" > kali-$architecture/etc/hostname

  cat << EOF > kali-$architecture/etc/hosts
  127.0.0.1       kali    localhost
  ::1             localhost ip6-localhost ip6-loopback
  fe00::0         ip6-localnet
  ff00::0         ip6-mcastprefix
  ff02::1         ip6-allnodes
  ff02::2         ip6-allrouters
EOF

  if [ ! -d kali-$architecture/etc/apt/ ]; then
      mkdir -p kali-$architecture/etc/network/
  fi
  cat << EOF > kali-$architecture/etc/network/interfaces
  auto lo
  iface lo inet loopback

  auto eth0
  iface eth0 inet dhcp
EOF

#  cat << EOF > kali-$architecture/etc/resolv.conf
#  nameserver 8.8.8.8
#EOF
}

function kali_rootfs_stage3(){
  #The custom config part. third stage
  export MALLOC_CHECK_=0 # workaround for LP: #520465
  export LC_ALL=C
  export DEBIAN_FRONTEND=noninteractive

  mount -t proc proc kali-$architecture/proc
  mount -o bind /dev/ kali-$architecture/dev/
  mount -o bind /dev/pts kali-$architecture/dev/pts

  cat << EOF > kali-$architecture/debconf.set
  console-common console-data/keymap/policy select Select keymap from full list
  console-common console-data/keymap/full select en-latin1-nodeadkeys
EOF

  cat << EOF > kali-$architecture/third-stage
  #!/bin/bash
  dpkg-divert --add --local --divert /usr/sbin/invoke-rc.d.chroot --rename /usr/sbin/invoke-rc.d
  cp /bin/true /usr/sbin/invoke-rc.d
  echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
  chmod +x /usr/sbin/policy-rc.d

  apt-get update
  apt-get --yes --force-yes install locales-all

  debconf-set-selections /debconf.set
  rm -f /debconf.set
  apt-get update
  apt-get -y install git-core binutils ca-certificates initramfs-tools u-boot-tools
  apt-get -y install locales console-common less nano git
  echo "root:toor" | chpasswd
  sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
  rm -f /etc/udev/rules.d/70-persistent-net.rules
  export DEBIAN_FRONTEND=noninteractive
  apt-get --yes --force-yes install $packages
  apt-get --yes --force-yes dist-upgrade
  apt-get --yes --force-yes autoremove

  rm -f /usr/sbin/policy-rc.d
  rm -f /usr/sbin/invoke-rc.d
  dpkg-divert --remove --rename /usr/sbin/invoke-rc.d

  rm -f /third-stage
EOF

  chmod +x kali-$architecture/third-stage
  LANG=C chroot kali-$architecture /third-stage

  # Enable the serial console
  echo "T1:12345:respawn:/sbin/agetty -L ttyS0 115200 vt100" >> kali-$architecture/etc/inittab
  # Load the ethernet module since it doesn't load automatically at boot.
  echo "sunxi_emac" >>kali-$architecture/etc/modules
}

function kali_rootfs_cleanup()
{

  cat << EOF > kali-$architecture/cleanup
  #!/bin/bash
  rm -rf /root/.bash_history
  apt-get update
  apt-get clean
  rm -f /0
  rm -f /hs_err*
  rm -f cleanup
  rm -f /usr/bin/qemu*
EOF

  chmod +x kali-$architecture/cleanup
  LANG=C chroot kali-$architecture /cleanup

  umount kali-$architecture/proc/sys/fs/binfmt_misc
  umount kali-$architecture/dev/pts
  umount kali-$architecture/dev/
  umount kali-$architecture/proc
}
##################################################################
#build u-boot and kernel
##################################################################
function build_kernel_uboot(){
	export ARCH=arm
	export CROSS_COMPILE=arm-linux-gnueabihf-
	dtbfile=sun4i-a10-cubieboard.dtb
	#build u-boot
	echo "Build u-boot..."
	cd ${uBootdir}
	make distclean
	make Cubieboard_defconfig
	make -j $(grep -c processor /proc/cpuinfo)
	cp u-boot-sunxi-with-spl.bin ${imagesdir}

	#build kernel
	#dtbfile=sun4i-a10-cubieboard.dtb
	echo "Build kernel..."
	cd ${linuxsunxidir}
	#make distclean
	make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- sunxi_defconfig
	make -j $(grep -c processor /proc/cpuinfo)  zImage dtbs modules
	make modules_install INSTALL_MOD_PATH=${imagesdir}
	cp arch/arm/boot/zImage ${imagesdir}
	cp arch/arm/boot/dts/${dtbfile}  ${imagesdir}

	cd ${basedir}
	#make boot.scr
	# Create boot.txt file
	cat << EOF > ${imagesdir}/boot.cmd
	setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait panic=10 ${extra} rw rootfstype=ext4 net.ifnames=0
	load mmc 0:1 0x43000000 ${dtbfile}
	load mmc 0:1 0x42000000 zImage
	bootz 0x42000000 - 0x43000000
EOF

	mkimage -A arm -T script -C none -d ${imagesdir}/boot.cmd ${imagesdir}/boot.scr
}

########################################################################
#we now can make image with all these resources.
########################################################################
function create_sd_image(){
  if [[ $# -eq 1 ]] ; then
    dev_path=$1
    echo "devie:${dev_path}"
  else
    dev_path=""
      echo "Not set device path. Use file image"
  fi
  cd ${imagesdir}
  if [ -z ${dev_path} ] ; then
    # Create the disk and partition it
    dd if=/dev/zero of=$imname.img bs=1M count=7000
    parted $imname.img --script -- mklabel msdos
    parted $imname.img --script -- mkpart primary fat32 2048s 264191s
    parted $imname.img --script -- mkpart primary ext4 264192s 100%

    # Set the partition variables
    loopdevice=`losetup -f --show $imname.img`
    device=`kpartx -va $loopdevice| sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
    sleep 5
    device="/dev/mapper/${device}"
  else
    device=${dev_path}
    parted ${device} --script -- mklabel msdos
    parted ${device} --script -- mkpart primary fat32 2048s 264191s
    parted ${device} --script -- mkpart primary ext4 264192s 100%
    bootp=${device}1
    rootp=${device}2
  fi
  # Create file systems
  mkfs.vfat $bootp
  mkfs.ext4 -O ^flex_bg -O ^metadata_csum $rootp

  # Create the dirs for the partitions and mount them
  mkdir -p bootp rootp
  mount $bootp ./bootp
  mount $rootp ./rootp
#write u-boot
  dd if=./u-boot-sunxi-with-spl.bin of=${device} bs=1024 seek=8
  cp ./sun4i-a10-cubieboard.dtb  ./bootp
  cp ./zImage  ./bootp
  cp ./boot.cmd ./bootp
  cp ./boot.scr ./bootp
  echo "Rsyncing rootfs to image file"
  rsync -HPavz -q ${basedir}/kali-$architecture/ ./rootp/
  cp -rf ./lib/modules/* ./rootp/lib/modules/*
  #
  umount  bootp
  rm -rf bootp
  umount  rootp
  rm -rf  rootp
}
download_files
kali_rootfs_stage1
kali_rootfs_stage2
kali_rootfs_stage3
kali_rootfs_cleanup
build_kernel_uboot
create_sd_image ${dev_path}
cd ${basedir}
echo "Finished..."
