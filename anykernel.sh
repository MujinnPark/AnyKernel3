# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers
# PitchKernel by Mujinn

## AnyKernel setup
properties() { '
kernel.string=PitchKernel by Mujinn
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=munch
device.name2=munchin
device.name3=
device.name4=
device.name5=
supported.versions=
'; } # end properties

block=/dev/block/bootdevice/by-name/boot;
is_slot_device=1;
ramdisk_compression=auto;

## AnyKernel methods
. tools/ak3-core.sh;

ui_print " ";
ui_print "  PitchKernel by Mujinn";
ui_print " ";

## ROM detection — auto from zip filename, volume-key fallback
case "$ZIPFILE" in
  *miui*|*MIUI*|*hyper*|*HyperOS*)
    ui_print "┌─────────────────────────────────┐";
    ui_print "│    MIUI/HyperOS ROM Detected    │";
    ui_print "└─────────────────────────────────┘";
    os="miui";
    mv "$AKHOME"/munch-miui-dtbo.img "$AKHOME"/dtbo.img 2>/dev/null;
    rm -f "$AKHOME"/munch-aosp-dtbo.img 2>/dev/null;
    ;;
  *)
    ui_print "> ROM: MIUI/HyperOS (Vol +) || AOSP (Vol -)";
    ui_print "  (waiting 8s, defaults to AOSP)";
    ROM_SEL="aosp";
    i=0;
    while [ $i -lt 16 ]; do
      ev=$(timeout 0.5 getevent -qlc 1 2>/dev/null);
      case "$ev" in
        *KEY_VOLUMEUP*DOWN*)
          ROM_SEL="miui"; break ;;
        *KEY_VOLUMEDOWN*DOWN*)
          ROM_SEL="aosp"; break ;;
      esac;
      i=$((i+1));
    done;
    case "$ROM_SEL" in
      miui)
        ui_print "┌─────────────────────────────────┐";
        ui_print "│      MIUI/HyperOS Selected      │";
        ui_print "└─────────────────────────────────┘";
        os="miui";
        mv "$AKHOME"/munch-miui-dtbo.img "$AKHOME"/dtbo.img 2>/dev/null;
        rm -f "$AKHOME"/munch-aosp-dtbo.img 2>/dev/null;
        ;;
      *)
        ui_print "┌─────────────────────────────────┐";
        ui_print "│        AOSP ROM Detected        │";
        ui_print "└─────────────────────────────────┘";
        os="aosp";
        mv "$AKHOME"/munch-aosp-dtbo.img "$AKHOME"/dtbo.img 2>/dev/null;
        rm -f "$AKHOME"/munch-miui-dtbo.img 2>/dev/null;
        ;;
    esac;
    ;;
esac;
ui_print " ";

## BUG FIX: Move kernel Image and dtb from kernels/$os/ to $AKHOME/ root.
## ak3-core.sh write_boot() searches for Image at $AKHOME/ root (line 264).
## Without this mv, write_boot falls through to split_img/kernel (the OLD kernel
## from the current boot partition) and reflashes the old kernel — not PitchKernel.
if [ -f "$AKHOME/kernels/$os/Image" ]; then
  mv "$AKHOME/kernels/$os/Image" "$AKHOME/Image";
  mv "$AKHOME/kernels/$os/dtb"   "$AKHOME/dtb"   2>/dev/null;
  ui_print "  kernel: $os Image loaded";
else
  ui_print "  ERROR: No kernel Image found for $os in this zip!";
  exit 1;
fi;
ui_print " ";

## CPU note: SM8250 prime core (cpu7) has OPP states up to 3187200 kHz, including
## the stock ceiling 2841600 kHz plus a higher overclock-style step at 3187200 kHz.
## Confirmed via on-device time_in_state: cpu7 genuinely runs at 3187200 kHz under
## real load (this is working as designed, not a bug). No sysfs write is made here.
ui_print "  CPU: prime core OPP table includes up to 3187200 kHz";
ui_print " ";

## Install cpufreq script to post-fs-data.d.
## KSU/Magisk runs this on every boot automatically as root.
mkdir -p /data/adb/post-fs-data.d 2>/dev/null;
cp "$AKHOME"/patch/pitchkernel_cpufreq.sh /data/adb/post-fs-data.d/pitchkernel_cpufreq.sh 2>/dev/null;
chmod 755 /data/adb/post-fs-data.d/pitchkernel_cpufreq.sh 2>/dev/null;
if [ -f /data/adb/post-fs-data.d/pitchkernel_cpufreq.sh ]; then
  ui_print "  cpufreq script installed to post-fs-data.d";
else
  ui_print "  WARNING: could not write to /data/adb/post-fs-data.d";
  ui_print "  (KSU/Magisk may not be initialized yet on first flash)";
fi;
ui_print " ";

## Boot flash
ui_print "  -> installing BOOT";
dump_boot;
write_boot;

## vendor_boot — reset_ak, dump_boot, write_boot (same as Perf+)
ui_print "  -> installing VENDOR_BOOT";
block=/dev/block/bootdevice/by-name/vendor_boot;
is_slot_device=1;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

reset_ak;
dump_boot;
write_boot;

ui_print " ";
ui_print "  PitchKernel installed successfully!";
## end install


