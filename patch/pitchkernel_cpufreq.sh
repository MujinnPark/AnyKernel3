#!/system/bin/sh
# PitchKernel CPU & Scheduler Tuning Script
# Installed to /data/adb/post-fs-data.d/ by anykernel.sh at flash time.
# KSU/Magisk runs this automatically on every boot as root.
#
# Prime core (cpu7) ceiling: the qcom-cpufreq-hw driver reads the OPP LUT from
# hardware and skips Index[20] Frequency[3187200] (confirmed in dmesg at boot).
# The real driver-enforced ceiling is 2841600 kHz. We do NOT write scaling_max_freq
# — the driver already handles this. Writing it would be redundant at best and
# could fight governor decisions at worst.
#
# Gaming fix: reduce schedutil rate_limit_us for faster frequency response.
# Default = 500us — lags before responding to load burst, causes frame drops.
# 200us = faster response without burning power on idle.

# Schedutil rate_limit_us — faster CPU freq response for gaming (HSR, CoD, Genshin)
for cpu in 0 1 2 3 4 5 6 7; do
  RATE_PATH="/sys/devices/system/cpu/cpu${cpu}/cpufreq/schedutil/rate_limit_us"
  if [ -f "$RATE_PATH" ]; then
    echo "200" > "$RATE_PATH" 2>/dev/null
  fi
done

# hispeed_freq per cluster — minimum freq to jump to on load burst
# Prevents under-clocking during sudden game load spikes
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

log -p i -t PitchKernel "schedutil tuning applied (rate_limit_us=200, hispeed set per cluster)"

