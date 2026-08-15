#!/bin/bash

# ==============================================================================
# NETWORK SPEED METRICS
# Reads /proc/net/dev deltas for download/upload, pings 1.1.1.1 for latency.
# Emits clean JSON for the Quickshell bar widget (no bc, no jq):
#   {"interface":"wlan0","downKBs":1234,"upKBs":234,"pingMs":12,"connected":true}
# ==============================================================================

STATH="/proc/net/dev"
ROUTE_IP="1.1.1.1"

INTERFACE=$(ip route get "$ROUTE_IP" 2>/dev/null | awk '{print $5; exit}')
# Sanitize for safe JSON output (interface names are alnum/-/_/. in practice).
INTERFACE=$(printf '%s' "$INTERFACE" | tr -cd '[:alnum:]._-')
[ -z "$INTERFACE" ] && INTERFACE="unknown"

DOWNS=0
UPS=0

if [ "$INTERFACE" != "unknown" ]; then
  read -r UP1 DOWN1 < <(grep "$INTERFACE" "$STATH" | awk '{print $10, $2}')
  sleep 1
  read -r UP2 DOWN2 < <(grep "$INTERFACE" "$STATH" | awk '{print $10, $2}')
  DOWNS=$(( (DOWN2 - DOWN1) / 1024 ))
  UPS=$(( (UP2 - UP1) / 1024 ))
fi
[ "$DOWNS" -lt 0 ] && DOWNS=0
[ "$UPS" -lt 0 ] && UPS=0

# Latency. "null" when the host is unreachable or no route exists.
PING=$(ping -c 1 -W 1 "$ROUTE_IP" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | cut -d' ' -f1 | cut -d. -f1)
if [ -n "$PING" ]; then
  PING_JSON="$PING"
  CONNECTED=true
else
  PING_JSON=null
  CONNECTED=false
fi

printf '{"interface":"%s","downKBs":%d,"upKBs":%d,"pingMs":%s,"connected":%s}\n' \
  "$INTERFACE" "$DOWNS" "$UPS" "$PING_JSON" "$CONNECTED"
