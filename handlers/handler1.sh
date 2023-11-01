#!/bin/bash

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timestamp)
      timestamp="$2"
      shift 2
      ;;
    --events)
      events="$2"
      shift 2
      ;;
    --path)
      path="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "[HANDLER 1]: Timestamp: $timestamp, Events: $events, Path: $path" >> /tmp/testoutput.log