# Barebones Android

Scavenging a kernel, initramfs, and recovery tooling from a
Cyanogenmod installation, and using them to make a horrible
Frankenstein's monster.

![Frank](frank.jpg)  
(This is a picture of Frank, lifted from the [VPRI STEPS 2010 report](http://www.vpri.org/pdf/tr2010004_steps10.pdf). He's not very horrible.)

## Hardware

Samsung Galaxy Note 10.1 (GT-N8013), running Cyanogenmod
10.2-20140323-NIGHTLY-n8013, with Linux kernel version
3.0.64-CM-gb4c422f.

Recovery is "CWM-based Recovery v6.0.2.7".

## Make a backup

Use the recovery to make a backup.

For example, mine produced the on-device folder,

    /data/media/clockworkmod/backup/2017-11-16.18.56.53

which I was able to retrieve to my laptop via

    adb pull /data/media/clockworkmod/backup/2017-11-16.18.56.53

Having the backup is important for being able to get back to a working
Android setup again later!

## Unpack boot.img and recovery.img

The tool `unmkbootimg` can be used to tease apart a working `*.img` file into two pieces:

 - the kernel `zImage`, and
 - a gzipped `cpio` archive, the `initrd`.

For example,

    ./mkbootimg/unmkbootimg --kernel boot-kernel --ramdisk boot-ramdisk.cpio.gz -i boot.img
    ./mkbootimg/unmkbootimg --kernel recovery-kernel --ramdisk recovery-ramdisk.cpio.gz -i recovery.img

The tool prints out a helpful `mkbootimg` command for reassembling the
pieces later. Here's what it suggested for the `boot.img` command
above:

    mkbootimg --base 0 --pagesize 2048 --kernel_offset 0x40008000 --ramdisk_offset 0x41000000 --second_offset 0x40f00000 --tags_offset 0x40000100 --cmdline 'console=ttySAC2,115200' --kernel boot-kernel --ramdisk boot-ramdisk.cpio.gz -o boot.img

(Another *fantastic* tool is
[binwalk](https://github.com/ReFirmLabs/binwalk).)

Having unpacked the `*.img` files, we need to unpack the `cpio` archives:

    mkdir boot-ramdisk; (cd boot-ramdisk; gzip -dc ../boot-ramdisk.cpio.gz | cpio -i)
    mkdir recovery-ramdisk; (cd recovery-ramdisk; gzip -dc ../recovery-ramdisk.cpio.gz | cpio -i)

I haven't tried building my own kernel yet;
[this repo](https://github.com/tonyg/kernel_n8013_ics) and
[this repo](https://github.com/tonyg/initramfs_n8013_ics) might be
helpful for doing so. (Other candidates:
[here](https://github.com/espenfjo/kernel_n8000_ics) and
[here](https://github.com/dsb9938/GT-N8013-JB-Kernel).)

## Smush them together

[This article][yhcting]
has some helpful advice on creating minimal `initrd` images for
development and testing.
[This article](https://unix.stackexchange.com/questions/64546/booting-native-arch-linux-on-an-android-device)
talks about getting an Arch distribution to run natively on an Android
device by modifying the `initrd`.

[yhcting]: https://yhcting.wordpress.com/2011/05/31/android-creating-minimum-set-of-android-kernel-adbd-ueventd-for-android-kernel-test/

This is the `initrd` structure we will create:

 - `/sbin`
     - `adbd`
     - `busybox` + its symlinks
     - `ueventd`, which appears to be a symlink to `/init`
 - `/init`
 - `/init.rc`
 - `/default.prop`
 - `/tmp`, not strictly necessary, but convenient

We will also add a small ARM7 program of our own:

 - `/mandelbrot.sh` - contains, essentially, `exec /mandelbrot > /dev/graphics/fb0`
 - `/mandelbrot` - a simple statically-linked program (from [pi-nothing](https://github.com/tonyg/pi-nothing/blob/master/mandelbrot-for-galaxynote.nothing))

Our `init.rc` is as follows:

    on early-init
        start ueventd

    on init
        sysclktz 0
        export PATH /sbin

        # This is not strictly necessary, but is convenient.
        #
        mount /tmp /tmp tmpfs

    on boot

        # These lines seem to be necessary for my Samsung Galaxy Note 10.1 device.
        #
        write /sys/class/android_usb/android0/functions adb
        write /sys/class/android_usb/android0/enable 1

        start adbd

        # This line makes adb start as a root shell. Omitting this causes it to
        # have trouble because it can't find /system/bin/sh.
        #
        setprop service.adb.root 1

        start mandelbrot

    service ueventd /sbin/ueventd

    service adbd /sbin/adbd

    service mandelbrot /sbin/sh /mandelbrot.sh
        oneshot

In addition to the minimal boilerplate, I've added a few lines that
seem to be required for my hardware. I've also added a service that
runs the `mandelbrot.sh` program.

I ended up using only the kernel from `boot.img`; all the other
components (except `init.rc` and `default.prop`) came from
`recovery.img`.

Here's the `default.prop` I'll use:

    ro.secure=1
    ro.allow.mock.location=0
    ro.debuggable=1

The `busybox` in recovery is a symlink to the `recovery` binary.

Hence:

    mkdir -p new-ramdisk/sbin
    cp -a recovery-ramdisk/sbin/adbd new-ramdisk/sbin/adbd
    cp -a recovery-ramdisk/sbin/recovery new-ramdisk/sbin/busybox
    (cd new-ramdisk/sbin; for f in $(ls -la ../../recovery-ramdisk/sbin/ | grep -e '-> busybox$' | awk '{print $9}'); do ln -s busybox $f; done)
    cp -a recovery-ramdisk/init new-ramdisk/.
    ln -s ../init new-ramdisk/sbin/ueventd
    cp default.prop new-ramdisk/.
    cp init.rc new-ramdisk/.
    chmod a+rx new-ramdisk/init.rc
    mkdir -p new-ramdisk/tmp  ## not strictly needed, but convenient
    cp -a mandelbrot mandelbrot.sh new-ramdisk/.

## Repack into a new boot.img

    (cd new-ramdisk; find . | cpio --quiet -R 0:0 -o -H newc) | gzip -c > new-ramdisk.cpio.gz
    mkbootimg --base 0 --pagesize 2048 --kernel_offset 0x40008000 --ramdisk_offset 0x41000000 --second_offset 0x40f00000 --tags_offset 0x40000100 --cmdline 'console=ttySAC2,115200' --kernel boot-kernel --ramdisk new-ramdisk.cpio.gz -o new.img

## Flash the boot.img

Boot your device into ROM download mode (for me, it's press-and-hold
`power+volumedown`, and then confirm with `volumeup`).

Alternatively, `adb reboot bootloader`.

Then:

    heimdall flash --BOOT new.img

## Perhaps later restore the original boot.img

You kept `boot.img` from the original backup, right?

    heimdall flash --BOOT boot.img
