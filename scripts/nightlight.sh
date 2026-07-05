#!/bin/sh
# Usage:
#   nightlight.sh off              — disable night light
#   nightlight.sh manual <temp>    — fixed temperature (e.g. 4500)
#   nightlight.sh auto <day> <night> — sunset/sunrise mode (geoclue2)

pkill -x gammastep 2>/dev/null

case "${1:-off}" in
  off)
    exit 0
    ;;
  manual)
    temp="${2:-4500}"
    gammastep -O "$temp" &
    ;;
  auto)
    day="${2:-6500}"
    night="${3:-3500}"
    gammastep -l geoclue2 -t "$day:$night" -m wayland &
    ;;
esac
