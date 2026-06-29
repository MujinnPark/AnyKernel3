#!/system/bin/sh
# PitchKernel CPU & Scheduler Tuning Script
# Installed to /data/adb/post-fs-data.d/ by anykernel.sh at flash time.
# KSU/Magisk runs this automatically on every boot as root.
#
# CPU FREQUENCY NOTE:
# FKM and other tools show "Prime cluster max freq: 3187 MHz" — this is correct.
# cpuinfo_max_freq = what the SM8250 hardware OPP table reports as capable.
# With uclamp disabled, schedutil will NOT boost to 3187 MHz for normal tasks.
# The 3187 MHz entry is there in hardware but the governor won't reach it without
# an explicit uclamp boost request from a task. This is the intended behaviour.
#
# I/O SCHEDULER FIX:
# Android's init.qcom.rc resets the block device scheduler to cfq at boot.
# This script re-enforces mq-deadline on every boot AFTER init.rc runs,
# since post-fs-data.d runs after early init but has root access to sysfs.
#
# Gaming fix: reduce schedutil rate_limit_us for faster frequency response.
# Default = 500us — lags before responding to load burst, causes frame drops.
# 200us = faster response without burning power on idle.

# --- I/O Scheduler enforcement ---
# UFS on SM8250 appears as /dev/sda or /dev/sdf depending on firmware.
# Try all common block device names. mq-deadline is correct for UFS 3.1 NVMe-like queue.
for blkdev in sda sdb sdc sdd sde sdf; do
  SCHED_PATH="/sys/block/${blkdev}/queue/scheduler"
  if [ -f "$SCHED_PATH" ]; then
    # Only change if mq-deadline is available (kernel compiled with CONFIG_MQ_IOSCHED_DEADLINE)
    if grep -q "mq-deadline" "$SCHED_PATH" 2>/dev/null; then
      echo "mq-deadline" > "$SCHED_PATH" 2>/dev/null
      log -p i -t PitchKernel "iosched: set mq-deadline on /dev/${blkdev} (was: $(cat $SCHED_PATH 2>/dev/null))"
    else
      log -p w -t PitchKernel "iosched: mq-deadline not available on /dev/${blkdev}, available: $(cat $SCHED_PATH 2>/dev/null)"
    fi
  fi
done

# --- Schedutil rate_limit_us — faster CPU freq response for gaming ---
for cpu in 0 1 2 3 4 5 6 7; do
  RATE_PATH="/sys/devices/system/cpu/cpu${cpu}/cpufreq/schedutil/rate_limit_us"
  if [ -f "$RATE_PATH" ]; then
    echo "200" > "$RATE_PATH" 2>/dev/null
  fi
done

# --- hispeed_freq per cluster — minimum freq to jump to on load burst ---
for cpu in 0 4 7; do
  HISPEED_PATH="/sys/devices/system/cpu/cpu${cpu}/cpufreq/schedutil/hispeed_freq"
  if [ -f "$HISPEED_PATH" ]; then
    case $cpu in
      0) echo "1497600" > "$HISPEED_PATH" 2>/dev/null ;;  # silver mid
      4) echo "1670400" > "$HISPEED_PATH" 2>/dev/null ;;  # gold mid
      7) echo "2419200" > "$HISPEED_PATH" 2>/dev/null ;;  # prime — jump high on burst
    esac
  fi
done

log -p i -t PitchKernel "tuning applied: mq-deadline enforced, schedutil rate_limit_us=200, hispeed set per cluster"
