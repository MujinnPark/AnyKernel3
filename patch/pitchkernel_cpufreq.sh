#!/system/bin/sh
# PitchKernel CPU & Scheduler Tuning Script
# Installed to /data/adb/post-fs-data.d/ by anykernel.sh at flash time.
# KSU/Magisk runs this automatically on every boot as root.
#
# Prime core (cpu7) real ceiling = 3187200 kHz (confirmed via FKM live read).
# The dmesg LUT-skip line was a red herring — hardware IS capable of 3187 MHz.
# We do NOT cap scaling_max_freq — let the hardware and schedutil decide freely.
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

