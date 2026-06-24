### AnyKernel methods (DO NOT CHANGE)
## osm0sis @ xda-developers

[ "$OUTFD" ] || OUTFD=$1;

# set up working directory variables
[ "$AKHOME" ] || AKHOME=$PWD;
BOOTIMG=$AKHOME/boot.img;
BIN=$AKHOME/tools;
PATCH=$AKHOME/patch;
RAMDISK=$AKHOME/ramdisk;
SPLITIMG=$AKHOME/split_img;

### output/testing functions:
# ui_print "<text>" [...]
ui_print() {
  until [ ! "$1" ]; do
    echo "ui_print $1
      ui_print" >> /proc/self/fd/$OUTFD;
    shift;
  done;
}

# abort ["<text>" [...]]
abort() {
  ui_print " " "$@";
  exit 1;
}

# contains <string> <substring>
contains() {
  [ "${1#*$2}" != "$1" ];
}

# file_getprop <file> <property>
file_getprop() {
  grep "^$2=" "$1" | tail -n1 | cut -d= -f2-;
}
###

### file/directory attributes functions:
# set_perm <owner> <group> <mode> <file> [<file2> ...]
set_perm() {
  local uid gid mod;
  uid=$1; gid=$2; mod=$3;
  shift 3;
  chown $uid:$gid "$@" || chown $uid.$gid "$@";
  chmod $mod "$@";
}

# set_perm_recursive <owner> <group> <dir_mode> <file_mode> <dir> [<dir2> ...]
set_perm_recursive() {
  local uid gid dmod fmod;
  uid=$1; gid=$2; dmod=$3; fmod=$4;
  shift 4;
  while [ "$1" ]; do
    chown -R $uid:$gid "$1" || chown -R $uid.$gid "$1";
    find "$1" -type d -exec chmod $dmod {} +;
    find "$1" -type f -exec chmod $fmod {} +;
    shift;
  done;
}
###

### dump_boot functions:
# split_boot (dump and split image only)
split_boot() {
  local splitfail;

  if [ ! -e "$(echo "$BLOCK" | cut -d\  -f1)" ]; then
    abort "Invalid partition. Aborting...";
  fi;
  if echo "$BLOCK" | grep -q ' '; then
    BLOCK=$(echo "$BLOCK" | cut -d\  -f1);
    CUSTOMDD=$(echo "$BLOCK" | cut -d\  -f2-);
  elif [ ! "$CUSTOMDD" ]; then
    CUSTOMDD="bs=1048576";
  fi;
  if [ -f "$BIN/nanddump" ]; then
    nanddump -f $BOOTIMG $BLOCK;
  else
    dd if=$BLOCK of=$BOOTIMG $CUSTOMDD;
  fi;
  if [ $? != 0 ]; then
    abort "Dumping image failed. Aborting...";
  fi;

  mkdir -p $SPLITIMG;
  cd $SPLITIMG;
  if [ -f "$BIN/unpackelf" ] && unpackelf -i $BOOTIMG -h -q 2>/dev/null; then
    if [ -f "$BIN/elftool" ]; then
      mkdir elftool_out;
      elftool unpack -i $BOOTIMG -o elftool_out;
    fi;
    unpackelf -i $BOOTIMG;
    [ $? != 0 ] && splitfail=1;
    mv -f boot.img-kernel kernel.gz;
    mv -f boot.img-ramdisk ramdisk.cpio.gz;
    mv -f boot.img-cmdline cmdline.txt 2>/dev/null;
    if [ -f boot.img-dt -a ! -f "$BIN/elftool" ]; then
      case $(od -ta -An -N4 boot.img-dt | sed -e 's/ del//' -e 's/   //g') in
        QCDT|ELF) mv -f boot.img-dt dt;;
        *)
          gzip -c kernel.gz > kernel.gz-dtb;
          cat boot.img-dt >> kernel.gz-dtb;
          rm -f boot.img-dt kernel.gz;
        ;;
      esac;
    fi;
  elif [ -f "$BIN/mboot" ]; then
    mboot -u -f $BOOTIMG;
  elif [ -f "$BIN/dumpimage" ]; then
    dd bs=$(($(printf '%d\n' 0x$(hexdump -n 4 -s 12 -e '16/1 "%02x""\n"' $BOOTIMG)) + 64)) count=1 conv=notrunc if=$BOOTIMG of=boot-trimmed.img;
    dumpimage -l boot-trimmed.img > header;
    grep "Name:" header | cut -c15- > boot.img-name;
    grep "Type:" header | cut -c15- | cut -d\  -f1 > boot.img-arch;
    grep "Type:" header | cut -c15- | cut -d\  -f2 > boot.img-os;
    grep "Type:" header | cut -c15- | cut -d\  -f3 | cut -d- -f1 > boot.img-type;
    grep "Type:" header | cut -d\( -f2 | cut -d\) -f1 | cut -d\  -f1 | cut -d- -f1 > boot.img-comp;
    grep "Address:" header | cut -c15- > boot.img-addr;
    grep "Point:" header | cut -c15- > boot.img-ep;
    dumpimage -p 0 -o kernel.gz boot-trimmed.img;
    [ $? != 0 ] && splitfail=1;
    case $(cat boot.img-type) in
      Multi) dumpimage -p 1 -o ramdisk.cpio.gz boot-trimmed.img;;
      RAMDisk) mv -f kernel.gz ramdisk.cpio.gz;;
    esac;
  elif [ -f "$BIN/rkcrc" ]; then
    dd bs=4096 skip=8 iflag=skip_bytes conv=notrunc if=$BOOTIMG of=ramdisk.cpio.gz;
  else
    (set -o pipefail; magiskboot unpack -h $BOOTIMG 2>&1 | tee infotmp >&2);
    case $? in
      1) splitfail=1;;
      2) touch chromeos;;
    esac;
  fi;

  if [ $? != 0 -o "$splitfail" ]; then
    abort "Splitting image failed. Aborting...";
  fi;
  cd $AKHOME;
}

# unpack_ramdisk (extract ramdisk only)
unpack_ramdisk() {
  local comp;

  cd $SPLITIMG;
  if [ -f ramdisk.cpio.gz ]; then
    if [ -f "$BIN/mkmtkhdr" ]; then
      mv -f ramdisk.cpio.gz ramdisk.cpio.gz-mtk;
      dd bs=512 skip=1 conv=notrunc if=ramdisk.cpio.gz-mtk of=ramdisk.cpio.gz;
    fi;
    mv -f ramdisk.cpio.gz ramdisk.cpio;
  fi;

  if [ -f ramdisk.cpio ]; then
    comp=$(magiskboot decompress ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p');
  else
    abort "No ramdisk found to unpack. Aborting...";
  fi;
  if [ "$comp" ]; then
    mv -f ramdisk.cpio ramdisk.cpio.$comp;
    magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio;
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      echo "Attempting ramdisk unpack with busybox $comp..." >&2;
      $comp -dc ramdisk.cpio.$comp > ramdisk.cpio;
    fi;
  fi;

  [ -d $RAMDISK ] && mv -f $RAMDISK $AKHOME/rdtmp;
  mkdir -p $RAMDISK;
  chmod 755 $RAMDISK;

  cd $RAMDISK;
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F $SPLITIMG/ramdisk.cpio -i;
  if [ $? != 0 -o ! "$(ls)" ]; then
    abort "Unpacking ramdisk failed. Aborting...";
  fi;
  if [ -d "$AKHOME/rdtmp" ]; then
    cp -af $AKHOME/rdtmp/* .;
  fi;
}
### dump_boot (dump and split image, then extract ramdisk)
dump_boot() {
  split_boot;
  unpack_ramdisk;
}
###

### write_boot functions:
# repack_ramdisk (repack ramdisk only)
repack_ramdisk() {
  local comp packfail mtktype;

  cd $AKHOME;
  if [ "$RAMDISK_COMPRESSION" != "auto" ] && [ "$(grep HEADER_VER $SPLITIMG/infotmp | sed -n 's;.*\[\(.*\)\];\1;p')" -gt 3 ]; then
    ui_print " " "Warning: Only lz4-l ramdisk compression is allowed with hdr v4+ images. Resetting to auto...";
    RAMDISK_COMPRESSION=auto;
  fi;
  case $RAMDISK_COMPRESSION in
    auto|"") comp=$(ls $SPLITIMG/ramdisk.cpio.* 2>/dev/null | grep -v 'mtk' | rev | cut -d. -f1 | rev);;
    none|cpio) comp="";;
    gz) comp=gzip;;
    lzo) comp=lzop;;
    bz2) comp=bzip2;;
    lz4-l) comp=lz4_legacy;;
    *) comp=$RAMDISK_COMPRESSION;;
  esac;

  if [ -f "$BIN/mkbootfs" ]; then
    mkbootfs $RAMDISK > ramdisk-new.cpio;
  else
    cd $RAMDISK;
    find . | cpio -H newc -o > $AKHOME/ramdisk-new.cpio;
  fi;
  [ $? != 0 ] && packfail=1;

  cd $AKHOME;
  if [ ! "$NO_MAGISK_CHECK" ]; then
    magiskboot cpio ramdisk-new.cpio test;
    magisk_patched=$?;
  fi;
  [ "$magisk_patched" -eq 1 ] && magiskboot cpio ramdisk-new.cpio "extract .backup/.magisk $SPLITIMG/.magisk";
  if [ "$comp" ]; then
    magiskboot compress=$comp ramdisk-new.cpio;
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      echo "Attempting ramdisk repack with busybox $comp..." >&2;
      $comp -9c ramdisk-new.cpio > ramdisk-new.cpio.$comp;
      [ $? != 0 ] && packfail=1;
      rm -f ramdisk-new.cpio;
    fi;
  fi;
  if [ "$packfail" ]; then
    abort "Repacking ramdisk failed. Aborting...";
  fi;

  if [ -f "$BIN/mkmtkhdr" -a -f "$SPLITIMG/boot.img-base" ]; then
    mtktype=$(od -ta -An -N8 -j8 $SPLITIMG/ramdisk.cpio.gz-mtk | sed -e 's/ nul//g' -e 's/   //g' | tr '[:upper:]' '[:lower:]');
    case $mtktype in
      rootfs|recovery) mkmtkhdr --$mtktype ramdisk-new.cpio*;;
    esac;
  fi;
}

# flash_boot (build, sign and write image only)
flash_boot() {
  local varlist i kernel ramdisk fdt cmdline comp part0 part1 needskernelpatch nocompflag signfail pk8 cert avbtype;

  cd $SPLITIMG;
  if [ -f "$BIN/mkimage" ]; then
    varlist="name arch os type comp addr ep";
  elif [ -f "$BIN/mk" -a -f "$BIN/unpackelf" -a -f boot.img-base ]; then
    mv -f cmdline.txt boot.img-cmdline 2>/dev/null;
    varlist="cmdline base pagesize kernel_offset ramdisk_offset tags_offset";
  fi;
  for i in $varlist; do
    if [ -f boot.img-$i ]; then
      eval local $i=\"$(cat boot.img-$i)\";
    fi;
  done;

  cd $AKHOME;
  for i in zImage zImage-dtb Image Image-dtb Image.gz Image.gz-dtb Image.bz2 Image.bz2-dtb Image.lzo Image.lzo-dtb Image.lzma Image.lzma-dtb Image.xz Image.xz-dtb Image.lz4 Image.lz4-dtb Image.fit; do
    if [ -f $i ]; then
      kernel=$AKHOME/$i;
      break;
    fi;
  done;
  if [ "$kernel" ]; then
    if [ -f "$BIN/mkmtkhdr" -a -f "$SPLITIMG/boot.img-base" ]; then
      mkmtkhdr --kernel $kernel;
      kernel=$kernel-mtk;
    fi;
  elif [ "$(ls $SPLITIMG/kernel* 2>/dev/null)" ]; then
    kernel=$(ls $SPLITIMG/kernel* | grep -v 'kernel_dtb' | tail -n1);
  fi;
  if [ "$(ls ramdisk-new.cpio* 2>/dev/null)" ]; then
    ramdisk=$AKHOME/$(ls ramdisk-new.cpio* | tail -n1);
  elif [ -f "$BIN/mkmtkhdr" -a -f "$SPLITIMG/boot.img-base" ]; then
    ramdisk=$SPLITIMG/ramdisk.cpio.gz-mtk;
  else
    ramdisk=$(ls $SPLITIMG/ramdisk.cpio* 2>/dev/null | tail -n1);
  fi;
  for fdt in dt recovery_dtbo dtb; do
    for i in $AKHOME/$fdt $AKHOME/$fdt.img $SPLITIMG/$fdt; do
      if [ -f $i ]; then
        eval local $fdt=$i;
        break;
      fi;
    done;
  done;

  cd $SPLITIMG;
  if [ -f "$BIN/mkimage" ]; then
    [ "$comp" == "uncompressed" ] && comp=none;
    part0=$kernel;
    case $type in
      Multi) part1=":$ramdisk";;
      RAMDisk) part0=$ramdisk;;
    esac;
    mkimage -A $arch -O $os -T $type -C $comp -a $addr -e $ep -n "$name" -d $part0$part1 $AKHOME/boot-new.img;
  elif [ -f "$BIN/elftool" ]; then
    [ "$dt" ] && dt="$dt,rpm";
    [ -f cmdline.txt ] && cmdline="cmdline.txt@cmdline";
    elftool pack -o $AKHOME/boot-new.img header=elftool_out/header $kernel $ramdisk,ramdisk $dt $cmdline;
  elif [ -f "$BIN/mboot" ]; then
    cp -f $kernel kernel;
    cp -f $ramdisk ramdisk.cpio.gz;
    mboot -d $SPLITIMG -f $AKHOME/boot-new.img;
  elif [ -f "$BIN/rkcrc" ]; then
    rkcrc -k $ramdisk $AKHOME/boot-new.img;
  elif [ -f "$BIN/mkbootimg" -a -f "$BIN/unpackelf" -a -f boot.img-base ]; then
    [ "$dt" ] && dt="--dt $dt";
    mkbootimg --kernel $kernel --ramdisk $ramdisk --cmdline "$cmdline" --base $base --pagesize $pagesize --kernel_offset $kernel_offset --ramdisk_offset $ramdisk_offset --tags_offset "$tags_offset" $dt --output $AKHOME/boot-new.img;
  else
    [ "$kernel" ] && cp -f $kernel kernel;
    [ "$ramdisk" ] && cp -f $ramdisk ramdisk.cpio;
    [ "$dt" -a -f extra ] && cp -f $dt extra;
    for i in dtb recovery_dtbo; do
      [ "$(eval echo \$$i)" -a -f $i ] && cp -f $(eval echo \$$i) $i;
    done;
    case $kernel in
      *Image*)
        if [ ! "$magisk_patched" -a ! "$NO_MAGISK_CHECK" ]; then
          magiskboot cpio ramdisk.cpio test;
          magisk_patched=$?;
        fi;
        if [ "$magisk_patched" -eq 1 ]; then
          ui_print " " "Magisk detected! Patching kernel so reflashing Magisk is not necessary...";
          comp=$(magiskboot decompress kernel 2>&1 | grep -vE 'raw|zimage' | sed -n 's;.*\[\(.*\)\];\1;p');
          (magiskboot split $kernel || magiskboot decompress $kernel kernel) >&2;
          if [ $? != 0 -a "$comp" ] && $comp --help 2>/dev/null; then
            echo "Attempting kernel unpack with busybox $comp..." >&2;
            $comp -dc $kernel > kernel;
          fi;
          # legacy SAR kernel string skip_initramfs -> want_initramfs
          magiskboot hexpatch kernel 736B69705F696E697472616D6673 77616E745F696E697472616D6673 && needskernelpatch=1;
          if [ "$(file_getprop $AKHOME/anykernel.sh do.modules)" == 1 ] && [ "$(file_getprop $AKHOME/anykernel.sh do.systemless)" == 1 ]; then
            strings kernel 2>/dev/null | grep -E -m1 'Linux version.*#' > $AKHOME/vertmp;
          fi;
          if [ "$needskernelpatch" ]; then
            if [ "$comp" ]; then
              magiskboot compress=$comp kernel kernel.$comp;
              if [ $? != 0 ] && $comp --help 2>/dev/null; then
                echo "Attempting kernel repack with busybox $comp..." >&2;
                $comp -9c kernel > kernel.$comp;
              fi;
              mv -f kernel.$comp kernel;
            fi;
          else
            echo "Restoring untouched new kernel since no patching required..." >&2;
            (magiskboot split -n $kernel || cp -f $kernel kernel) >&2;
          fi;
          [ ! -f .magisk ] && magiskboot cpio ramdisk.cpio "extract .backup/.magisk .magisk";
          export $(cat .magisk);
          for fdt in dtb extra kernel_dtb recovery_dtbo; do
            [ -f $fdt ] && magiskboot dtb $fdt patch; # remove dtb verity/avb
          done;
        elif [ -d /data/data/me.weishu.kernelsu ] && [ "$(file_getprop $AKHOME/anykernel.sh do.modules)" == 1 ] && [ "$(file_getprop $AKHOME/anykernel.sh do.systemless)" == 1 ]; then
          ui_print " " "KernelSU detected! Setting up for kernel helper module...";
          comp=$(magiskboot decompress kernel 2>&1 | grep -vE 'raw|zimage' | sed -n 's;.*\[\(.*\)\];\1;p');
          (magiskboot split $kernel || magiskboot decompress $kernel kernel) >&2;
          if [ $? != 0 -a "$comp" ] && $comp --help 2>/dev/null; then
            echo "Attempting kernel unpack with busybox $comp..." >&2;
            $comp -dc $kernel > kernel;
          fi;
          strings kernel > stringstmp 2>/dev/null;
          if grep -q -E '^/data/adb/ksud$' stringstmp; then
            touch $AKHOME/kernelsu_patched;
            grep -E -m1 'Linux version.*#' stringstmp > $AKHOME/vertmp;
            [ -d $RAMDISK/overlay.d ] && ui_print " " "Warning: overlay.d detected in ramdisk but not currently supported by KernelSU!";
          else
            ui_print " " "Warning: No KernelSU support detected in kernel!";
          fi;
          rm -f stringstmp;
          if [ "$comp" ]; then
            magiskboot compress=$comp kernel kernel.$comp;
            if [ $? != 0 ] && $comp --help 2>/dev/null; then
              echo "Attempting kernel repack with busybox $comp..." >&2;
              $comp -9c kernel > kernel.$comp;
            fi;
            mv -f kernel.$comp kernel;
          fi;
        else
          case $kernel in
            *-dtb) rm -f kernel_dtb;;
          esac;
        fi;
        unset magisk_patched KEEPVERITY KEEPFORCEENCRYPT RECOVERYMODE PREINITDEVICE SHA1 RANDOMSEED; # leave PATCHVBMETAFLAG set for repack
      ;;
    esac;
    case $RAMDISK_COMPRESSION in
      none|cpio) nocompflag="-n";;
    esac;
    case $PATCH_VBMETA_FLAG in
      auto|"") [ "$PATCHVBMETAFLAG" ] || export PATCHVBMETAFLAG=false;;
      1) export PATCHVBMETAFLAG=true;;
      *) export PATCHVBMETAFLAG=false;;
    esac;
    magiskboot repack $nocompflag $BOOTIMG $AKHOME/boot-new.img;
  fi;
  if [ $? != 0 ]; then
    abort "Repacking image failed. Aborting...";
  fi;
  [ "$PATCHVBMETAFLAG" ] && unset PATCHVBMETAFLAG;
  [ -f .magisk ] && touch $AKHOME/magisk_patched;

  cd $AKHOME;
  if [ -f "$BIN/futility" -a -d "$BIN/chromeos" ]; then
    if [ -f "$SPLITIMG/chromeos" ]; then
      echo "Signing with CHROMEOS..." >&2;
      futility vbutil_kernel --pack boot-new-signed.img --keyblock $BIN/chromeos/kernel.keyblock --signprivate $BIN/chromeos/kernel_data_key.vbprivk --version 1 --vmlinuz boot-new.img --bootloader $BIN/chromeos/empty --config $BIN/chromeos/empty --arch arm --flags 0x1;
    fi;
    [ $? != 0 ] && signfail=1;
  fi;
  if [ -d "$BIN/avb" ]; then
    pk8=$(ls $BIN/avb/*.pk8);
    cert=$(ls $BIN/avb/*.x509.*);
    case $BLOCK in
      *recovery*|*RECOVERY*|*SOS*) avbtype=recovery;;
      *) avbtype=boot;;
    esac;
    if [ -f "$BIN/boot_signer-dexed.jar" ]; then
      if [ -f /system/bin/dalvikvm ] && [ "$(/system/bin/dalvikvm -Xnoimage-dex2oat -cp $BIN/boot_signer-dexed.jar com.android.verity.BootSignature -verify boot.img 2>&1 | grep VALID)" ]; then
        echo "Signing with AVBv1 /$avbtype..." >&2;
        /system/bin/dalvikvm -Xnoimage-dex2oat -cp $BIN/boot_signer-dexed.jar com.android.verity.BootSignature /$avbtype boot-new.img $pk8 $cert boot-new-signed.img;
      fi;
    else
      if magiskboot verify boot.img; then
        echo "Signing with AVBv1 /$avbtype..." >&2;
        magiskboot sign /$avbtype boot-new.img $cert $pk8;
      fi;
    fi;
  fi;
  if [ $? != 0 -o "$signfail" ]; then
    abort "Signing image failed. Aborting...";
  fi;
  mv -f boot-new-signed.img boot-new.img 2>/dev/null;

  if [ ! -f boot-new.img ]; then
    abort "No repacked image found to flash. Aborting...";
  elif [ "$(wc -c < boot-new.img)" -gt "$(wc -c < boot.img)" ]; then
    abort "New image larger than target partition. Aborting...";
  fi;
  blockdev --setrw $BLOCK 2>/dev/null;
  if [ -f "$BIN/flash_erase" -a -f "$BIN/nandwrite" ]; then
    flash_erase $BLOCK 0 0;
    nandwrite -p $BLOCK boot-new.img;
  elif [ "$CUSTOMDD" ]; then
    dd if=/dev/zero of=$BLOCK $CUSTOMDD 2>/dev/null;
    dd if=boot-new.img of=$BLOCK $CUSTOMDD;
  else
    cat boot-new.img /dev/zero > $BLOCK 2>/dev/null || true;
  fi;
  if [ $? != 0 ]; then
    abort "Flashing image failed. Aborting...";
  fi;
}

# flash_generic <name>
flash_generic() {
  local avb avbblock avbpath file flags img imgblock imgsz isro isunmounted path;

  cd $AKHOME;
  for file in $1 $1.img; do
    if [ -f $file ]; then
      img=$file;
      break;
    fi;
  done;

  if [ "$img" -a ! -f ${1}_flashed ]; then
    for path in /dev/block/mapper /dev/block/by-name /dev/block/bootdevice/by-name; do
      for file in $1 $1$SLOT; do
        if [ -e $path/$file ]; then
          imgblock=$path/$file;
          break 2;
        fi;
      done;
    done;
    if [ ! "$imgblock" ]; then
      abort "$1 partition could not be found. Aborting...";
    fi;
    if [ ! "$NO_BLOCK_DISPLAY" ]; then
      ui_print " " "$imgblock";
    fi;
    if [ "$path" == "/dev/block/mapper" ]; then
      avb=$(httools_static avb $1);
      [ $? == 0 ] || abort "Failed to parse fstab entry for $1. Aborting...";
      if [ "$avb" ] && [ ! "$NO_VBMETA_PARTITION_PATCH" ]; then
        flags=$(httools_static disable-flags);
        [ $? == 0 ] || abort "Failed to parse top-level vbmeta. Aborting...";
        if [ "$flags" == "enabled" ]; then
          ui_print " " "dm-verity detected! Patching $avb...";
          for avbpath in /dev/block/mapper /dev/block/by-name /dev/block/bootdevice/by-name; do
            for file in $avb $avb$SLOT; do
              if [ -e $avbpath/$file ]; then
                avbblock=$avbpath/$file;
                break 2;
              fi;
            done;
          done;
          cd $BIN;
          httools_static patch $1 $AKHOME/$img $avbblock || abort "Failed to patch $1 on $avb. Aborting...";
          cd $AKHOME;
        fi
      fi
      imgsz=$(wc -c < $img);
      if [ "$imgsz" != "$(wc -c < $imgblock)" ]; then
        if [ -d /postinstall/tmp -a "$SLOT_SELECT" == "inactive" ]; then
          echo "Resizing $1$SLOT snapshot..." >&2;
          snapshotupdater_static update $1 $imgsz || abort "Resizing $1$SLOT snapshot failed. Aborting...";
        else
          echo "Removing any existing $1_ak3..." >&2;
          lptools_static remove $1_ak3;
          echo "Clearing any merged cow partitions..." >&2;
          lptools_static clear-cow;
          echo "Attempting to create $1_ak3..." >&2;
          if lptools_static create $1_ak3 $imgsz; then
            echo "Replacing $1$SLOT with $1_ak3..." >&2;
            lptools_static unmap $1_ak3 || abort "Unmapping $1_ak3 failed. Aborting...";
            lptools_static map $1_ak3 || abort "Mapping $1_ak3 failed. Aborting...";
            lptools_static replace $1_ak3 $1$SLOT || abort "Replacing $1$SLOT failed. Aborting...";
            imgblock=/dev/block/mapper/$1_ak3;
            ui_print " " "Warning: $1$SLOT replaced in super. Reboot before further logical partition operations.";
          else
            echo "Creating $1_ak3 failed. Attempting to resize $1$SLOT..." >&2;
            httools_static umount $1 || abort "Unmounting $1 failed. Aborting...";
            if [ -e $path/$1-verity ]; then
              lptools_static unmap $1-verity || abort "Unmapping $1-verity failed. Aborting...";
            fi
            lptools_static unmap $1$SLOT || abort "Unmapping $1$SLOT failed. Aborting...";
            lptools_static resize $1$SLOT $imgsz || abort "Resizing $1$SLOT failed. Aborting...";
            lpt
