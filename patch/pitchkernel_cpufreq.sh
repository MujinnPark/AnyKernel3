#!/system/bin/sh
# PitchKernel CPU Frequency Confirmation Script
# Installed to /data/adb/post-fs-data.d/ by anykernel.sh at flash time.
# KSU/Magisk runs this automatically on every boot — no separate module needed.
#
# Hardware reality confirmed from real dmesg on this device:
#   qcom_cpufreq_hw_read_lut skips Index[20] Frequency[3187200] at boot.
#   Real hardware ceiling = 2841600 kHz (prime core / cpu7).

CPU7_PATH="/sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq"
TARGET=2841600

i=0
while [ ! -f "$CPU7_PATH" ] && [ $i -lt 20 ]; do
  sleep 0.5
  i=$((i + 1))
done

if [ ! -f "$CPU7_PATH" ]; then
  log -p w -t PitchKernel "cpu7 scaling_max_freq not found after 10s"
  exit 1
fi

ACTUAL=$(cat "$CPU7_PATH" 2>/dev/null)
if [ "$ACTUAL" != "$TARGET" ]; then
  echo "$TARGET" > "$CPU7_PATH" 2>/dev/null
  ACTUAL=$(cat "$CPU7_PATH" 2>/dev/null)
fi

log -p i -t PitchKernel "cpu7 scaling_max_freq = ${ACTUAL} kHz"
