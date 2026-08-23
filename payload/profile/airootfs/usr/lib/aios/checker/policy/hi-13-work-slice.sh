#!/bin/sh
# HI-13: work agents file intents; they never enact.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "${here}/work-slice.sh"
