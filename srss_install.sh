#!/bin/bash
#
# Lot's of this script got together with help from "The Internet":
#
#  https://help.ubuntu.com/community/UbuntuOnSunRay
#  http://wiki.sun-rays.org/index.php/Sun_Ray_on_Ubuntu
#
# So lot's of credits goes to those people. However, I want nice and clean
# reproducible results, so I combined this in a script that makes a deb package
# that can be installed easily. Also, at the time (release date ubuntu 8.04)
# that I made this, I had to spend alot of time to get e.g. the sound working
# with all applications on all window managers.
#
# Steps:
#
# 0. download the srss 4.1 linux from Sun.
# 1. install software needed to build our own package:
#     64-bit:
#       apt-get install fakeroot alien pdksh lib32stdc++6 \
#                   libldap-2.4-2 ldap-utils tftpd gawk ia32-libs 
#     
#     Ubuntu 8.04/8.10, add this too (not for 9.04):
#       apt-get install xkb-data-legacy
#
#     Optionally, you can add different kernels. The patch for the modules that
#     I made makes it possible that multiple kernel-versioned modules can be
#     built. e.g. -rt,-server,-generic, all for different versions.
#
#     32-bit:
#       apt-get install fakeroot alien sun-java6-jre pdksh  \
#                   libldap-2.4-2 ldap-utils tftpd libmotif3 gawk
#
# 2. build the srss package, as a regular user:
#     bash ./srss_install.sh <dir to srss unpack or iso mount>
#
# 3. install the created srss package:
#     dpkg -i srss*.deb
#
# 4. configure the sunray software:
#     /opt/SUNWut/sbin/utconfig
#     /opt/SUNWut/sbin/utadm -L on
#     /opt/SUNWut/sbin/utadm -A 166.59.84.0  # ignore errors here
#     /opt/SUNWut/sbin/utfwadm -A -f /opt/SUNWut/lib/firmware_gui  -V -a
#     /opt/SUNWut/sbin/utrestart
#     /etc/init.d/zsunray-init stop
#     /etc/init.d/zsunray-init start
#
# 5. configure a DHCP server somwhere. The reason I didn't leave this in thos
#    script somewhere is because it's not really needed, and it is usually
#    easier to have one seperate somwhere.
#
#    Taken from https://help.ubuntu.com/community/UbuntuOnSunRay :
#
#         # Example SunRay dhcpd.conf
#         # IP of SunRay server: 192.168.1.101
#         # IP-Range for SunRays: 192.168.1.185-192.168.1.199
#         # SunRay firmware version: 3.0_51,REV=2004.11.10.16.18
# 
#         #Sun Ray
#         option space SunRay;
#         option SunRay.AuthSrvr  code 21 = ip-address;
#         option SunRay.AuthSrvr  192.168.1.101;
#         option SunRay.FWSrvr    code 31 = ip-address;
#         option SunRay.FWSrvr    192.168.1.101;
#         option SunRay.NewTVer   code 23 = text;
#         option SunRay.NewTVer   "3.0_51,REV=2004.11.10.16.18";
#         option SunRay.Intf      code 33 = text;
#         option SunRay.Intf      "eth2";
#         option SunRay.LogHost   code 24 = ip-address;
#         option SunRay.LogHost   192.168.1.101;
#         option SunRay.LogKern   code 25 = integer 8;
#         option SunRay.LogKern   6;
#         option SunRay.LogNet    code 26 = integer 8;
#         option SunRay.LogNet    6;
#         option SunRay.LogUSB    code 27 = integer 8;
#         option SunRay.LogUSB    6;
#         option SunRay.LogVid    code 28 = integer 8;
#         option SunRay.LogVid    6;
#         option SunRay.LogAppl   code 29 = integer 8;
#         option SunRay.LogAppl   6;
# 
#         group
#         {
#                 vendor-option-space SunRay;
#                 subnet 192.168.1.0 netmask 255.255.255.0 {
#                         default-lease-time 720000;
#                         max-lease-time 1440000;
#                         authoritative;
#                         option routers 192.168.1.30;
#                         range 192.168.1.185 192.168.1.199; 
#                 }
#         }
#
#
#
#
# KNOWN ISSUES:
#
# 1. GNOME
# A known issue happens with the gnome-settings-daemon. Upon debugging this
# with gdb, this has something to do with libxklavier on ubuntu 9.04 x86_64.
# On ubuntu 8.04, something similar happens (although I didn't bother debugging
# that).
#
# 2. KDE 4
# Sadly enough, KDE 4 (and probably Qt4) uses XRENDER *alot*. As that's not
# implemented (probably going to be as of the next release of srss), it looks
# ugly. Even if XRENDER would be supported, it's probably going to use lot's of
# cpu resources, and it would be a bad idea to have 50 users running KDE 4.
#
# 3. flash (for in firefox)
# nsppluginwrapper flash sucks. However, as that is a 32-bit flash, colors look
# allright. The 64-bit flash is better for stability, however, red and blue
# colors are switched. On ubuntu 9.04, this also appears to be the case I think
# when I checked this briefly. The colormask is different as from a normal X,
# this can be checked with xdpyinfo.
#
# 4. VMware's console viewer
# colors red and blue are swapped too.
#

source_dir=$1
version=$2
if [ -z $source_dir ]; then
    echo "Usage: $0 <srss software source dir> [version]"
    exit 0
fi

if [ -z $version ]; then
    version='4.1'
fi

here=$(dirname $(readlink -f $0))

tmpdir=/var/tmp/srss.$$
mkdir -p $tmpdir
echo "Using $tmpdir"

baseurl=http://fr.archive.ubuntu.com/ubuntu/pool/

for rpm in $source_dir/{Sun_Ray_*,Docs,Kiosk*}/Linux/Packages/*.rpm; do
    echo "Unpacking rpm $rpm"
    rpm2cpio $rpm|(cd $tmpdir; \
        cpio --extract \
             --make-directories \
             --no-absolute-filenames \
             --preserve-modification-time)
done

(
    cd $tmpdir
    wget $baseurl/main/g/gdbm/libgdbm3_1.8.3-3_i386.deb
    wget $baseurl/multiverse/o/openmotif/libmotif3_2.2.3-2_i386.deb
    wget $baseurl/universe/g/glib1.2/libglib1.2ldbl_1.2.10-19build1_i386.deb
    wget $baseurl/main/libx/libxfont/libxfont1_1.3.1-2_i386.deb
    wget $baseurl/main/libf/libfontenc/libfontenc1_1.0.4-3_i386.deb
)

for extra_pkg in $tmpdir/{libgdbm3_1.8.3-3_i386,libmotif3_2.2.3-2_i386,libglib1.2ldbl_1.2.10-19build1_i386,libxfont1_1.3.1-2_i386,libfontenc1_1.0.4-3_i386}.deb; do
    echo  "Adding $extra_pkg"
    pkg_tmpdir=/var/tmp/pkg_tmp_dir
    mkdir -p $pkg_tmpdir
    cd $pkg_tmpdir
    fakeroot alien $extra_pkg --to-tgz
    tar xvzf $pkg_tmpdir/*.tgz 
    rm -f $pkg_tmpdir/*.tgz
    cp -R $pkg_tmpdir/usr/* $tmpdir/opt/SUNWut
    if [ -d $pkg_tmpdir/lib ]; then
    	cp -R $pkg_tmpdir/lib/* $tmpdir/opt/SUNWut/lib
    fi
    rm -rf $pkg_tmpdir
done

echo "Adding java..."
mkdir -p $tmpdir/etc/opt/SUNWut
java_install_dir=$source_dir/Supplemental/Java_Runtime_Environment/Linux
java_install_file=$(basename `ls $java_install_dir/*.bin`)
cp $java_install_dir/$java_install_file $tmpdir/usr
cd $tmpdir/usr
(
    function more (){
        true    
    }         
    export -f more
    bash -x ./$java_install_file < <(printf "yes\n")
)
java_install_target_dir=$(basename `find $tmpdir/usr -name 'jre*' -type d`)
mv $tmpdir/usr/$java_install_target_dir $tmpdir/usr/j2se
rm $tmpdir/usr/$java_install_file

echo "Patching... SunRay /opt/SUNWut software"
cd $tmpdir/opt/SUNWut
if [ $version = '4.1' ]; then
    patch -p3 < $here/srss4.1.debian-3.patch
fi
if [ $version = '4.2' ]; then
    patch -p3 < $here/srss4.2.debian-3.patch
fi

echo "Patching kernel modules..."
cd $tmpdir/usr/src/SUNWut
patch -p0 < $here/utadem.patch
patch -p0 < $here/utdisk.patch
patch -p0 < $here/utio.patch
patch -p1 < $here/tims_patch.diff

echo "Building all kernel modules for all kernels we can find on the machine"
cd $tmpdir/usr
for module_dir in src/SUNWut/*; do
    echo "Build module $module_dir..."
    for V in `ls /usr/src|grep 'linux-headers'`; do
        V=$(basename $V|sed s/linux-headers-//g)
        (
            cd $module_dir
            echo $module_dir, $V
            make clean 
            VERSION=$V make
            if [ $? -eq 0 ]; then
                    mkdir -p $tmpdir/lib/modules/$V/misc
                    cp -R *.ko $tmpdir/lib/modules/$V/misc
                    make clean
            fi
        )
    done
done

echo "Making empty dirs..."
mkdir -p $tmpdir/var/dt
mkdir -p $tmpdir/var/opt/SUNWut/tokens
mkdir -p $tmpdir/var/opt/SUNWut/displays

echo "Fixing xkb stuff..."
(
    this_os_version=$(lsb_release -r -s)
    if [ $this_os_version = '8.04' \
         -o $this_os_version = '8.04.1' \
         -o $this_os_version = '8.10' ]; then
        cd $tmpdir
        wget $baseurl/universe/x/xkb-data-legacy/xkb-data-legacy_1.0.1-4_all.deb
        for extra_pkg in $tmpdir/xkb-data-legacy_1.0.1-4_all.deb; do
            pkg_tmpdir=/var/tmp/pkg_tmp_dir
            mkdir -p $pkg_tmpdir
            cd $pkg_tmpdir
            fakeroot alien $extra_pkg --to-tgz
            tar xvzf $pkg_tmpdir/*.tgz 
            rm -f $pkg_tmpdir/*.tgz
            mkdir -p $tmpdir/opt/SUNWut/lib
            cp -R $pkg_tmpdir/usr/share/X11/xkb/* $tmpdir/opt/SUNWut/lib/xkb
            rm -rf $pkg_tmpdir
            ln -s /usr/bin/xkbcomp $tmpdir/opt/SUNWut/lib/xkb/xkbcomp
            mkdir $tmpdir/etc/X11
            ln -s /usr/share/X11/XKeysymDB $tmpdir/etc/X11/XKeysymDB
        done
    else
        mv $tmpdir/opt/SUNWut/lib/xkb $tmpdir/opt/SUNWut/lib/xkb.bak
        ln -s /usr/share/X11/xkb $tmpdir/opt/SUNWut/lib/xkb
        mkdir -p $tmpdir/usr/share/X11/xkb
        cp -a $tmpdir/opt/SUNWut/lib/xkb.bak/xkbtable.map $tmpdir/usr/share/X11/xkb
        ln -s /var/lib/xkb $tmpdir/usr/share/X11/xkb/compiled
        ln -s /usr/bin/xkbcomp $tmpdir/usr/share/X11/xkb/xkbcomp
    fi
)

echo "Making symlinks..."
mkdir -p $tmpdir/usr/X11R6/lib
ln -s /etc/X11 $tmpdir/usr/X11R6/lib/X11
ln -s /usr/lib32/libldap-2.4.so.2 $tmpdir/opt/SUNWut/lib/libldap.so.199
ln -s /usr/lib32/liblber-2.4.so.2 $tmpdir/opt/SUNWut/lib/liblber.so.199

echo "Making symlink for tftp. SunRay software expects /tftpboot"
mkdir -p $tmpdir/srv/tftp
ln -s /srv/tftp $tmpdir/tftpboot

echo "Xnewt needs at least 1 font, in one fontpath"
mkdir -p $tmpdir/usr/share/X11/fonts
ln -s /usr/share/fonts/X11/misc $tmpdir/usr/share/X11/fonts/misc
mkdir -p $tmpdir/usr/lib/X11/fonts
ln -s /usr/share/fonts/X11/misc $tmpdir/usr/lib/X11/fonts/misc

echo "Copying our own files"
cp -R $here/{etc,opt,usr} $tmpdir

echo "Making tar..."
cd $tmpdir
fakeroot tar czf $tmpdir/srss-4.1_10.8.tgz *

echo "Making .deb..."
fakeroot alien -d $tmpdir/srss-4.1_10.8.tgz

cp $tmpdir/srss*.deb ~/
rm -rf $tmpdir

