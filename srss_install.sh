#!/bin/bash

# Steps:
#
# 1. Install software needed to build our own package:
#     64-bit:
#     apt-get install fakeroot alien pdksh lib32stdc++6 libldap-2.4-2 ldap-utils tftpd gawk ia32-libs xkb-data-legacy
#
#     32-bit:
#     apt-get install fakeroot alien sun-java6-jre pdksh  libldap-2.4-2 ldap-utils tftpd libmotif3 gawk
#
# 2. install the created srss package:
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

source_dir=$1
if [ -z $source_dir ]; then
    echo "Usage: $0 <srss software source dir>"
    exit 0
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
cp $source_dir/Supplemental/Java_Runtime_Environment/Linux/jre-1_5_0_11-linux-i586.bin $tmpdir/usr
cd $tmpdir/usr
(
    function more (){
        true    
    }         
    export -f more
    bash -x ./jre-1_5_0_11-linux-i586.bin < <(printf "yes\n")
)
mv $tmpdir/usr/jre1.5.0_11 $tmpdir/usr/j2se
rm $tmpdir/usr/jre-1_5_0_11-linux-i586.bin

echo "Patching... SunRay /opt/SUNWut software"
cd $tmpdir/opt/SUNWut
patch -p3 < $here/srss4.1.debian-3.patch

echo "Patching kernel modules..."
cd $tmpdir/usr/src/SUNWut
#patch -p1 < $here/modules-4.1beta.diff
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
mkdir -p $tmpdir/opt/SUNWut/lib/xkb
mkdir -p $tmpdir/opt/SUNWut/lib/xkb/compiled

echo "Fixing xkb stuff..."
(
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
    done
)

echo "Making symlinks..."
mkdir -p $tmpdir/usr/X11R6/lib
ln -s /etc/X11 $tmpdir/usr/X11R6/lib/X11
ln -s /usr/share/X11/XKeysymDB $tmpdir/etc/X11/XKeysymDB
mkdir -p $tmpdir/lib
ln -s /usr/lib32/libldap-2.4.so.2 $tmpdir/opt/SUNWut/lib/libldap.so.199
ln -s /usr/lib32/liblber-2.4.so.2 $tmpdir/opt/SUNWut/lib/liblber.so.199
ln -s /usr/bin/xkbcomp $tmpdir/opt/SUNWut/lib/xkb/xkbcomp

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

