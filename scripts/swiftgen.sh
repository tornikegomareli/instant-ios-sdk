#!/bin/bash

if which swiftgen >/dev/null; then
 swiftgen
else
 "${SRCROOT}/Tools/swiftgen"
fi
