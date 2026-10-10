#!/bin/bash
# ./sheet.sh W H name tile scale  -> out/contact_<name>.png from stills at the beat list below
set -e
TIMES=0.5,1.5,2.4,4,6.5,8.2,8.9,9.2,11,12.3,13,15,16.3,17.3,18.3,19.1,20.5,22.7,23.6,24.7,25.3,25.9,26.3,26.7,27.5,28.2,28.4,28.7,29.2,30,31,31.9
rm -rf out/stills
node render.mjs --w $1 --h $2 --stills ${STILLS:-$TIMES} >/dev/null
ffmpeg -y -loglevel error -pattern_type glob -i 'out/stills/*.png' -vf "scale=$5:-1,tile=$4" -frames:v 1 out/contact_$3.png
