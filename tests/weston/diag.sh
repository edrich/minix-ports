#!/bin/sh
# Diagnostics: fontconfig, then the headless Weston smoke test.
echo "== fc-list"
/usr/pkg/bin/fc-list
echo "== fc-match"
/usr/pkg/bin/fc-match monospace; echo "rc=$?"
