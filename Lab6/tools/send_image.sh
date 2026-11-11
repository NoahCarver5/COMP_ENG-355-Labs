#!/usr/bin/env bash
#
# Send an image to the board's SDRAM.  A wrapper around sdram_writer.tcl
# that knows where Quartus is installed, because the command-line tools
# are not on PATH by default on this machine and "command not found" is
# a confusing way to be told that.
#
#     ./send_image.sh ../memory/vr360_image_0.mif
#     ./send_image.sh image.raw
#     ./send_image.sh                       (built-in test pattern)
#
# Program the FPGA first -- this talks to logic that only exists once
# the device is configured and running:
#
#     ./send_image.sh --program
#
set -e

QUARTUS_BIN="/c/altera_pro/26.1.1/quartus/bin64"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ ! -x "$QUARTUS_BIN/quartus_stp.exe" ]; then
    echo "Quartus not found at $QUARTUS_BIN"
    echo "Edit QUARTUS_BIN in this script to point at your install."
    exit 1
fi

export PATH="$QUARTUS_BIN:$PATH"

if [ "$1" = "--program" ]; then
    SOF="$HERE/../syn/output_files/vr360.sof"
    if [ ! -f "$SOF" ]; then
        echo "No .sof at $SOF -- run the Quartus flow first."
        exit 1
    fi
    echo "Programming $SOF"
    quartus_pgm -m jtag -o "p;$SOF"
    exit $?
fi

exec quartus_stp -t "$HERE/sdram_writer.tcl" "$@"
