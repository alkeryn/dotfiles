#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bspwm-wayland-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
protocol_dir=$(pkg-config --variable=pkgdatadir wayland-protocols)
layer="$root/scripts/protocols/wlr-layer-shell-unstable-v1.xml"
viewport="$protocol_dir/stable/viewporter/viewporter.xml"
wayland-scanner server-header "$layer" "$work/layer-server.h"
wayland-scanner private-code "$layer" "$work/layer.c"
wayland-scanner server-header "$viewport" "$work/viewport-server.h"
wayland-scanner private-code "$viewport" "$work/viewport.c"
wayland-scanner private-code "$protocol_dir/stable/xdg-shell/xdg-shell.xml" "$work/xdg.c"
# shellcheck disable=SC2046
${CC:-cc} -std=c11 -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter \
    -I"$work" $(pkg-config --cflags wayland-server) \
    "$root/tests/presel_feedback_native_test.c" "$work/layer.c" "$work/viewport.c" "$work/xdg.c" \
    $(pkg-config --libs wayland-server) -o "$work/test"
"$root/scripts/presel_feedback" --self-test
XDG_RUNTIME_DIR="$work" "$work/test" "$root/scripts/presel_feedback"
