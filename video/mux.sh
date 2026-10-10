#!/bin/bash
# ./mux.sh 16x9  -> out/omninote_16x9.mp4 (music + SFX, limited, -16 LUFS)
set -e
ffmpeg -y -loglevel error -i out/silent_$1.mp4 -i out/score.wav -i out/sfx.wav \
  -filter_complex "[1:a][2:a]amix=inputs=2:normalize=0,alimiter=limit=0.7:level=false,loudnorm=I=-16:TP=-2:LRA=11[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -ar 48000 -shortest out/omninote_$1.mp4
