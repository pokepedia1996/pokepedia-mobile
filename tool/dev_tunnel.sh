#!/usr/bin/env bash
# Exposes the local backend (Supabase :54321 + pokepedia-web :3000) on one
# ngrok URL for testing on a physical device. See tool/dev_proxy.js.
#
# DEV ONLY. While this runs, anyone with the URL reaches your local
# Supabase (default local keys) and web API. Stop it when you're done.
#
# Needs: `supabase start` and `bun run dev` running in pokepedia-web, and an
# ngrok account (`ngrok config add-authtoken <token>`). Ctrl+C stops both.
set -euo pipefail
cd "$(dirname "$0")"

bun dev_proxy.js &
PROXY_PID=$!
trap 'kill $PROXY_PID 2>/dev/null' EXIT

ngrok http 8080
