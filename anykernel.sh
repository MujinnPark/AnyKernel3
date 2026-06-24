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
## Uses $AKHOME (correct variable in this ak3-core.sh), not $home
case "$ZIPFILE" in
  *miui*|*MIUI*|*hyper*|*HyperOS*)
    ui_print "┌─────────────────────────────────┐";
    ui_print "│    MIUI/HyperOS ROM Detected    │";
    ui_print "└─────────────────────────────────┘";
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
        mv "$AKHOME"/munch-miui-dtbo.img "$AKHOME"/dtbo.img 2>/dev/null;
        rm -f "$AKHOME"/munch-aosp-dtbo.img 2>/dev/null;
        ;;
      *)
        ui_print "┌─────────────────────────────────┐";
        ui_print "│        AOSP ROM Detected        │";
        ui_print "└─────────────────────────────────┘";
        mv "$AKHOME"/munch-aosp-dtbo.img "$AKHOME"/dtbo.img 2>/dev/null;
        rm -f "$AKHOME"/munch-miui-dtbo.img 2>/dev/null;
        ;;
    esac;
    ;;
esac;
ui_print " ";

## CPU frequency note
## qcom_cpufreq_hw_read_lut skips Index[20] Frequency[3187200] on this
## kernel — confirmed from real dmesg. Hardware ceiling is 2841600 kHz.
## No sysfs write needed — the driver enforces the real ceiling at boot.
ui_print "  CPU: prime core ceiling 2841600 kHz (hardware-enforced)";
ui_print " ";

## Install cpufreq script to post-fs-data.d — no separate module needed.
## KSU/Magisk (already installed via ReSukiSU) polls /data/adb/post-fs-data.d/
## on every boot automatically. The script runs as root and logs via logcat.
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

## Boot flash — dump_boot then write_boot, matching Perf+ exactly.
## No ramdisk modification. Boot header v3 ramdisk patching
## (unpack_ramdisk/repack_ramdisk) caused bootloop into fastboot —
## confirmed from recovery.log showing both partitions growing in size.
ui_print "  -> installing BOOT";
dump_boot;
write_boot;

## vendor_boot — same as Perf+: reset_ak, dump_boot, write_boot.
## No ramdisk patching here either.
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
