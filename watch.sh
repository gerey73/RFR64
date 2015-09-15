#!/bin/sh
make
while inotifywait -e modify *.asm ; do
    date +%Y-%m-%d-%H:%M:%S
    make
    echo "\n"
done
