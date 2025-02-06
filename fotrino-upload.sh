#!/usr/bin/env bash

api='https://films.fotrino.com'
# api='https://localhost:8081'
insecure=''
# insecure='-k'
video2hls="${HOME}/Workspace/video2hls/video2hls"

# DON'T CHANGE ANYTHING BELOW THIS LINE

# Check OS
os=$(uname)
[[ "$os" = 'Darwin' ]] || { echo "Unsupported Operating System!"; exit 1; }

# Check dependencies
declare -a deps=("$video2hls" 'md5sum' 'tar' 'ffmpeg' 'gm' 'exiftool' 'mediainfo' 'jq' 'curl')
for dep in "${deps[@]}"; do
    which "$dep" &>/dev/null || { echo "Missing ${dep}..."; fail=1; }
done

# Check Python version
[[ $(python --version) == "Python 3."* ]] || { echo "Check Python version..."; fail=1; }

# Check command line parameter(s)
[[ -n $1 && -d "$1" ]] || { echo "Missing or invalid parameter..."; fail=1; }

# STOP if there are errors
[[ $fail -eq 1 ]] && exit 1

# Check Images (Cover, Poster)
# TODO

# Check Media
for file in "$1/"Media.m[op][v4]; do
    [[ $(mediainfo --Output="Video;%AspectRatio%" "${file}") == "1.778" ]] || { echo "Wrong aspect ratio: ${file}..."; fail=1; }
    # Check Images (Preview)
    # TODO
done

# API Token Handling
# TODO

# STOP if there are errors
[[ $fail -eq 1 ]] && exit 1

# Convert Video
for file in "$1/Media".m[op][v4]; do
    "$video2hls" --video-bitrates 4500 2500 1300 800 400 --video-widths 1920 1280 854 640 427  --no-poster --no-mp4 "$file"
done

# Optimise Images
for file in "${1}/"*.[jp][pn]g; do
    dir="$(dirname "${file}")"
    filename=$(basename -- "${file}")   
    extension="${filename##*.}"
    basefile="${filename%.*}"
    gm convert -resize 720x720 -strip -interlace Plane -quality 80 "${file}" "${dir}/${basefile}_opt.${extension}"
done

echo "So far so good! But this script doesn't work yet."
exit 0

# TODO
# Hash and rename files
# Request pre-signed URLs from API
# Record length of video (number of segments)
# Upload
# Change pending status to false
