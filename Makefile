all: new.img

clean:
	rm -rf boot-kernel boot-ramdisk boot-ramdisk.cpio.gz
	rm -rf recovery-kernel recovery-ramdisk recovery-ramdisk.cpio.gz
	rm -rf new-ramdisk new-ramdisk.cpio.gz
	rm -f new.img

%.cpio.gz: %
	(cd $<; find . | cpio --quiet -R 0:0 -o -H newc) | gzip -c > $@

new.img: new-ramdisk.cpio.gz boot-ramdisk
	mkbootimg --base 0 --pagesize 2048 \
		--kernel_offset 0x40008000 \
		--ramdisk_offset 0x41000000 \
		--second_offset 0x40f00000 \
		--tags_offset 0x40000100 \
		--cmdline 'console=ttySAC2,115200' \
		--kernel boot-kernel \
		--ramdisk new-ramdisk.cpio.gz \
		-o new.img

new-ramdisk: boot-ramdisk recovery-ramdisk
	mkdir -p $@/sbin
	cp -a recovery-ramdisk/sbin/adbd $@/sbin/adbd
	cp -a recovery-ramdisk/sbin/recovery $@/sbin/busybox
	(cd $@/sbin; for f in $$(ls -la ../../recovery-ramdisk/sbin/ | grep -e '-> busybox$$' | awk '{print $$9}'); do ln -s busybox $$f; done)
	cp -a recovery-ramdisk/init $@/.
	ln -s ../init $@/sbin/ueventd
	cp default.prop $@/.
	cp init.rc $@/.
	chmod a+rx $@/init.rc
	mkdir -p $@/tmp  ## not strictly needed, but convenient

	cp -a mandelbrot mandelbrot.sh $@/.

mkbootimg/unmkbootimg:
	$(MAKE) -C mkbootimg

%-ramdisk: %.img
	./mkbootimg/unmkbootimg --kernel $*-kernel --ramdisk $*-ramdisk.cpio.gz -i $<
	mkdir $@
	(cd $@; gzip -dc ../$*-ramdisk.cpio.gz | cpio -i)
