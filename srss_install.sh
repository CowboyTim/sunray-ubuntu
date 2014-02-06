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
#       apt-get install fakeroot alien build-essential linux-headers-amd64
#     
#     Optionally, you can add different kernels. The patch for the modules that
#     I made makes it possible that multiple kernel-versioned modules can be
#     built. e.g. -rt,-server,-generic, all for different versions.
#
# 2. build the srss package, as a regular user:
#     bash ./srss_install.sh <dir to srss unpack or iso mount> [4.2|4.1]
#
# 3. install the created srss package, as root:
#     echo "deb file:///home/test /"      > /etc/apt/sources.list.d/srss.list
#     echo "deb http://some.repository.org/debs/srss /" > /etc/apt/sources.list.d/srss.list
#     echo "deb http://ftp.debian.org/debian/ unstable main non-free contrib"      > /etc/apt/sources.list.d/unstable.list
#     echo "deb-src http://ftp.debian.org/debian/ unstable main non-free contrib" >> /etc/apt/sources.list.d/unstable.list
#     dpkg --add-architecture i386
#     apt-get update
#     apt-get install srss
#     update-rc.d zsunray-init enable  3 5
#
# 4. configure the sunray software:
#     /opt/SUNWut/sbin/utconfig
#     /opt/SUNWut/sbin/utadm -L on
#     /opt/SUNWut/sbin/utadm -A 192.168.1.0  # ignore errors here
#     /opt/SUNWut/sbin/utfwadm -A -f /opt/SUNWut/lib/firmware_gui  -V -a
#     /opt/SUNWut/sbin/utrestart
#     /etc/init.d/zsunray-init stop
#     /etc/init.d/zsunray-init start
#
# 5. configure a DHCP server somwhere. The reason I didn't leave this in this
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

source_dir=$1
version=5.4.1
if [ -z $source_dir ]; then
    echo "Usage: $0 <srss software source dir>"
    exit 0
fi

rev=11

here=$(dirname $(readlink -f $0))

tmproot=/var/tmp/srss.$$
tmpdir=/var/tmp/srss.$$/srss
mkdir -p $tmpdir
echo "Using $tmpdir"

echo "Adding regular rpms..."
for rpm in \
            $source_dir/{Sun_Ray_*,Docs,Kiosk*}/Linux/Packages/*.rpm \
            $source_dir/Components/*/Content/{Sun_Ray_*,Docs,Kiosk*,Sun_Ray_Connector*,VMware_View_Connector*}/Linux/Packages/*.rpm \
            $source_dir/Components/*/Patches/linux/*.rpm \
            $source_dir/Version/Linux/Packages/*.rpm; do
    echo "Unpacking rpm $rpm"
    rpm2cpio $rpm|(cd $tmpdir; \
        cpio --extract \
             --make-directories \
             --unconditional \
             --no-absolute-filenames \
             --preserve-modification-time)
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

echo "Building all kernel modules for all kernels we can find on the machine"
(
cd $tmpdir/usr
tar cvzf src.tgz src
KDEPS=""
for V in `ls /usr/src|grep 'linux-headers'|grep -v common`; do
    V=$(basename $V|sed s/linux-headers-//g)
    if [ -z "$KDEPS" ]; then
        KDEPS="linux-image-$V"
    else
        KDEPS="$KDEPS | linux-image-$V"
    fi
    rm -rf $tmpdir/usr/src
    tar xvzfm src.tgz

    echo "Patching kernel modules for kernel version $V..."
    (
        cd $tmpdir/usr/src/SUNWut
        if [[ $V =~ ^2 ]]; then
            echo "no-op"
        else
            patch -p2 < $here/kernel-patches/new-3.2.0-kernel-module.patch.v5.3
        fi
    )

    for module_dir in src/SUNWut/*; do
        echo "Build module $module_dir..."
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
rm src.tgz
echo $KDEPS > $tmproot/kdeps
)


debianbase=http://ftp.us.debian.org/debian/pool
ubuntubase=http://fr.archive.ubuntu.com/ubuntu/pool/

for pkg in $debianbase/main/g/gdbm/libgdbm3_1.8.3-11_i386.deb \
           $ubuntubase/multiverse/o/openmotif/libmotif3_2.2.3-2_i386.deb \
           $ubuntubase/universe/g/glib1.2/libglib1.2ldbl_1.2.10-19build1_i386.deb \
           $debianbase/main/libx/libxfont/libxfont1_1.4.5-2_i386.deb \
           $debianbase/main/g/gdm/gdm_2.20.11-4_amd64.deb \
           $debianbase/main/libf/libfontenc/libfontenc1_1.1.1-1_i386.deb; do
    (cd $tmpdir && wget $pkg || exit 1) || exit $?
done

for extra_pkg in $tmpdir/{libgdbm3*,libmotif3*,libglib1.2ldbl*,libxfont1*,libfontenc1*}_i386.deb $tmpdir/gdm_*_amd64.deb; do
    echo "Adding $extra_pkg"
    pkg_tmpdir=$tmproot/pkg_tmp_dir
    mkdir -p $pkg_tmpdir
    (
    cd $pkg_tmpdir
    fakeroot alien -c -g $extra_pkg
    if [[ $extra_pkg =~ gdm.*amd64\.deb ]]; then
        echo "Adding GDM"
        cp -a $pkg_tmpdir/*.orig/* $tmpdir/
        rm -rf $pkg_tmpdir/*.orig
        mkdir -p $tmproot/postbak
        cp -a $pkg_tmpdir/gdm*/debian/{post,pre}* $tmproot/postbak/
    else
        pkg_tmpdir=$pkg_tmpdir/*.orig/
        cp -a $pkg_tmpdir/usr/* $tmpdir/opt/SUNWut
        if [ -d $pkg_tmpdir/lib ]; then
            cp -a $pkg_tmpdir/lib/* $tmpdir/opt/SUNWut/lib
        fi
    fi
    )
    rm -rf $tmproot/pkg_tmp_dir
    rm -f $extra_pkg
done

echo "Patching... SunRay /opt/SUNWut software"
if [ $version = '4.2' ]; then
    cd $tmpdir/opt/SUNWut
    patch -p3 < $here/srss-patches/srss4.2.debian-3.patch
    echo "Xstartup helper must not be +x, as it's a ksh script, being"
    echo "sourced by a sh program else, see /etc/opt/SUNWut/gdm/SunRayPreSession/Default"
    chmod -x $tmpdir/opt/SUNWut/lib/prototype/Xstartup.SUNWut.prototype
fi
if [ $version = '4.4' ]; then
    cd $tmpdir/
    patch -p1 < $here/srss-patches/srss4.4.debian-3.patch
    echo "Xstartup helper must not be +x, as it's a ksh script, being"
    echo "sourced by a sh program else, see /etc/opt/SUNWut/gdm/SunRayPreSession/Default"
    chmod -x $tmpdir/opt/SUNWut/lib/prototype/Xstartup.SUNWut.prototype
fi
if [ $version = '5.4.1' ]; then
    cd $tmpdir/
    patch -p1 < $here/srss-patches/srss5.4.1.debian-3.patch
    echo "Xstartup helper must not be +x, as it's a ksh script, being"
    echo "sourced by a sh program else, see /etc/opt/SUNWut/gdm/SunRayPreSession/Default"
    chmod -x $tmpdir/opt/SUNWut/lib/prototype/Xstartup.SUNWut.prototype
fi

echo "Making empty dirs..."
mkdir -p $tmpdir/var/dt
mkdir -p $tmpdir/var/opt/SUNWut/tokens
mkdir -p $tmpdir/var/opt/SUNWut/displays

mv $tmpdir/opt/SUNWut/lib/xkb $tmpdir/opt/SUNWut/lib/xkb.bak
ln -s /usr/share/X11/xkb $tmpdir/opt/SUNWut/lib/xkb
mkdir -p $tmpdir/usr/share/X11/xkb
cp -a $tmpdir/opt/SUNWut/lib/xkb.bak/xkbtable.map $tmpdir/usr/share/X11/xkb
ln -s /var/lib/xkb $tmpdir/usr/share/X11/xkb/compiled
ln -s /usr/bin/xkbcomp $tmpdir/usr/share/X11/xkb/xkbcomp

echo "Making symlinks..."
mkdir -p $tmpdir/usr/X11R6/lib
ln -s /etc/X11 $tmpdir/usr/X11R6/lib/X11
ln -s /usr/lib32/libldap-2.4.so.2 $tmpdir/opt/SUNWut/lib/libldap-2.3.so.0
ln -s /usr/lib32/liblber-2.4.so.2 $tmpdir/opt/SUNWut/lib/liblber-2.3.so.0
ln -s /opt/SUNWut/lib/i386-linux-gnu/libgdbm.so.3 $tmpdir/opt/SUNWut/lib/libgdbm.so.2

echo "Making symlink for tftp. SunRay software expects /tftpboot"
mkdir -p $tmpdir/srv/tftp
ln -s /srv/tftp $tmpdir/tftpboot

echo "Xnewt needs at least 1 font, in one fontpath"
mkdir -p $tmpdir/usr/share/X11/fonts
ln -s /usr/share/fonts/X11/misc $tmpdir/usr/share/X11/fonts/misc
mkdir -p $tmpdir/usr/lib/X11/fonts
ln -s /usr/share/fonts/X11/misc $tmpdir/usr/lib/X11/fonts/misc

echo "Making a ld.so.conf.d entry..."
mkdir -p $tmpdir/etc/ld.so.conf.d/
cat > $tmpdir/etc/ld.so.conf.d/srss.conf <<EOld
/opt/SUNWut/lib/
/opt/SUNWut/lib/i386-linux-gnu
EOld

echo "Copying our own files"
cp -R $here/{etc,opt,usr} $tmpdir

echo "Copying gdm.conf-sunray over gdm.conf itself..."
cp -a $here/etc/gdm/gdm.conf-sunray $tmpdir/etc/gdm/gdm.conf
cp -a $here/etc/gdm/gdm.conf-sunray $tmpdir/usr/share/gdm/defaults.conf

echo "adding symlink SecurityPolicy"
ln -s /opt/SUNWut/lib/X11/SecurityPolicy $tmpdir/etc/opt/SUNWut/X11/SecurityPolicy

echo "Making tar..."
cd $tmpdir
fakeroot tar czf $tmpdir/srss-${version}.tgz *

echo "Making .deb..."
fakeroot alien --version=${version} --bump=$rev -g -c -d $tmpdir/srss-${version}.tgz

KDEPS=`cat $tmproot/kdeps`

mv $tmproot/postbak/* $tmpdir/srss-${version}/debian/
cat > $tmpdir/srss-${version}/debian/control <<EOctrl
Source: srss
Section: x11
Priority: extra
Maintainer: root <root@whatever.com>

Package: srss
Architecture: amd64
Depends: \${shlibs:Depends}, ed, pulseaudio, pdksh, lib32stdc++6, ia32-libs (=20130215), ldap-utils, gawk, xkb-data, tftpd
Conflicts: xkb-data-legacy, gdm, xdm, mdm, virtualbox-guest-x11
Recommends: openbox
Provides: gdm3
Replaces: gdm3, gdm, mdm, gnome-control-center-data
Suggests: xfce4, gnome, kde
Description: Sun Ray server software
 This is Oracle's Sun Ray server software nicely packaged into one clean debian
 package.
EOctrl
cat > $tmpdir/srss-${version}/debian/prerm <<EOrm
#!/bin/sh
rm -rf /var/dt /var/opt/SUNWut /var/log/SUNWut /etc/opt/SUNWut /etc/opt /opt/SUNWut/lib /opt/SUNWuttsc/lib /var/lib/gdm /etc/gdm/custom.conf /srv/tftp/Corona* /srv/tftp/SunRay*
EOrm
(cd $tmpdir/srss-${version}/ && fakeroot debian/rules binary)

mkdir -p ~/srss/
cp $tmpdir/srss*.deb ~/srss/
(cd ~/srss/ && dpkg-scanpackages . /dev/null| gzip -c -9 > ~/srss/Packages.gz)
echo 'Please copy ~/srss to a webserver and configure apt on the target system like this:'
echo
echo 'echo "deb http://some.repository.org/debs/srss /" > /etc/apt/sources.list.d/srss.list'
echo 'apt-get update'
rm -rf $tmproot

