#!/system/bin/sh
# PitchKernel CPU & Scheduler Tuning Script
# Installed to /data/adb/post-fs-data.d/ by anykernel.sh at flash time.
# KSU/Magisk runs this automatically on every boot as root.
#
# Hardware reality confirmed from real dmesg on this device:
#   qcom_cpufreq_hw_read_lut skips Index[20] Frequency[3187200] at boot.
#   Real prime core ceiling = 2841600 kHz (cpu7).
#
# HSR/gaming fps fix: reduce schedutil rate_limit_us on all clusters.
# Default rate_limit_us = 500us (half of target_loads period). This causes
# the scheduler to lag 500us before responding to a new load burst — enough
# to miss a frame on a 60fps target (16.67ms frame budget).
# Setting to 200us gives faster response without burning power on idle loads.

CPU7_PATH="/sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq"
TARGET=2841600

# Wait for cpufreq sysfs node
i=0
while [ ! -f "$CPU7_PATH" ] && [ $i -lt 20 ]; do
  sleep 0.5
  i=$((i + 1))
done

if [ ! -f "$CPU7_PATH" ]; then
  log -p w -t PitchKernel "cpu7 scaling_max_freq not found after 10s"
  exit 1
fi

# Set cpu7 ceiling
ACTUAL=$(cat "$CPU7_PATH" 2>/dev/null)
if [ "$ACTUAL" != "$TARGET" ]; then
  echo "$TARGET" > "$CPU7_PATH" 2>/dev/null
  ACTUAL=$(cat "$CPU7_PATH" 2>/dev/null)
fi
log -p i -t PitchKernel "cpu7 scaling_max_freq = ${ACTUAL} kHz"

# Schedutil rate_limit_us tuning for all clusters
# Reduces frequency switch latency — helps with HSR/gaming burst frames
for cpu in 0 1 2 3 4 5 6 7; do
  RATE_PATH="/sys/devices/system/cpu/cpu${cpu}/cpufreq/schedutil/rate_limit_us"
  if [ -f "$RATE_PATH" ]; then
    echo "200" > "$RATE_PATH" 2>/dev/null
  fi
done

# Also tune hispeed_freq on schedutil for each cluster if exposed
# cpu0-3 = silver cluster, cpu4-6 = gold, cpu7 = prime
# hispeed_freq: below this freq, schedutil always boosts to at least this freq
# Set to a reasonable mid-point to prevent under-clocking on game load bursts
for cpu in 0 4 7; do
  HISPEED_PATH="/sys/devices/system/cpu/cpu${cpu}/cpufreq/schedutil/hispeed_freq"
  if [ -f "$HISPEED_PATH" ]; then
    case $cpu in
      0) echo "1497600" > "$HISPEED_PATH" 2>/dev/null ;;  # silver mid
      4) echo "1670400" > "$HISPEED_PATH" 2>/dev/null ;;  # gold mid
      7) echo "1804800" > "$HISPEED_PATH" 2>/dev/null ;;  # prime mid
    esac
  fi
done

log -p i -t PitchKernel "schedutil tuning applied for gaming"

