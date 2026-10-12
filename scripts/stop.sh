#!/usr/bin/env bash
# Stop anything started by the run-*.sh scripts.
pkill -f 'node origin/server.js' ; pkill -f 'mitmdump --listen-host 127.0.0.1' ; true
