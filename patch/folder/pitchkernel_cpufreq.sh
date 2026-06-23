#!/system/bin/sh
# PitchKernel CPU Frequency Confirmation Script
# Runs via KSU/Magisk post-fs-data.d on every boot — no separate module needed.
# Placed into /data/adb/post-fs-data.d/ by anykernel.sh at flash time.
#
# Hardware reality (confirmed from real dmesg on this device):
#   qcom_cpufreq_hw_read_lut skips Index[20] Frequency[3187200] on boot.
#   The driver silently ignores writes of 3187200 to scaling_max_freq.
#   Real hardware ceiling = 2841600 kHz (prime core / cpu7).
#   This script confirms the ceiling is correct and logs the result.

CPU7_PATH="/sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq"
TARGET=2841600

# Wait for cpufreq sysfs node — not always ready at post-fs-data stage
i=0
while [ ! -f "$CPU7_PATH" ] && [ $i -lt 20 ]; do
  sleep 0.5
  i=$((i + 1))
done

if [ ! -f "$CPU7_PATH" ]; then
  log -p w -t PitchKernel "cpu7 scaling_max_freq not found after 10s, skipping"
  exit 1
fi

ACTUAL=$(cat "$CPU7_PATH" 2>/dev/null)
log -p i -t PitchKernel "cpu7 scaling_max_freq = ${ACTUAL} kHz (hardware ceiling: ${TARGET} kHz)"

if [ "$ACTUAL" != "$TARGET" ]; then
  # Attempt to enforce — will silently no-op if hardware rejects it
  echo "$TARGET" > "$CPU7_PATH" 2>/dev/null
  ACTUAL=$(cat "$CPU7_PATH" 2>/dev/null)
  log -p i -t PitchKernel "cpu7 after enforcement: ${ACTUAL} kHz"
fi

