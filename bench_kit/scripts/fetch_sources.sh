#!/bin/sh
# Fetch the two benchmark sources (not bundled: they carry their own licenses).
set -e
mkdir -p third_party
[ -d third_party/coremark ]   || git clone --depth 1 https://github.com/eembc/coremark          third_party/coremark
[ -d third_party/dhrystone ]  || git clone --depth 1 https://github.com/sifive/benchmark-dhrystone third_party/dhrystone
echo "CoreMark  : $(git -C third_party/coremark  rev-parse --short HEAD)"
echo "Dhrystone : $(git -C third_party/dhrystone rev-parse --short HEAD)"