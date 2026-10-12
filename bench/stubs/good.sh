#!/usr/bin/env bash
# Fake adapter: copies the known-good solution into the workdir.
cp -r "$(dirname "$1")/solution/." "$2"
