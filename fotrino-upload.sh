#!/usr/bin/env bash

video2hls="$HOME/Workspace/video2hls/video2hls"

# DON'T CHANGE ANYTHING BELOW THIS LINE

# Check OS
os=$(uname)
[[ "$os" = 'Darwin' ]] || { echo "Unsupported Operating System!"; exit 1; }

# Check dependencies
declare -a deps=("$video2hls" 'ffmpeg' 'gm' 'md5sum' 'curl' 'mediainfo')
for dep in "${deps[@]}"; do
    which "$dep" &>/dev/null || { echo "Missing ${dep}..."; fail=1; }
done

# Check Python version
[[ $(python --version) == "Python 3."* ]] || { echo "Check Python version..."; fail=1; }

[[ -n $1 ]] || { echo "Missing parameter..."; fail=1; }

[[ $fail -eq 1 ]] && exit 1

# Check JSON
python -mjson.tool "${1}/Collection.json" &>/dev/null || { echo "Invalid JSON..."; fail=1; }

# Check Images
# TODO

# Check Media
for file in "$1/Media"*.*; do
    [[ $(mediainfo --Output="Video;%AspectRatio%" "$file") == "1.778" ]] || { echo "Wrong aspect ratio: ${file}..."; fail=1; }
done

[[ $fail -eq 1 ]] && exit 1

# Get API Token
[[ -f ~/.fotrino/token ]] || { read -pr "Enter API Token (Secret): " token; mkdir -p ~/.fotrino/; echo "$token" > ~/.fotrino/token; echo "Secret API Token written to ~/.fotrino/token."; }
[[ -f ~/.fotrino/token ]] || { echo "Unable to save token to disk..."; exit 1; }

echo "So far so good! But this script doesn't work yet."
exit 0

# TODO
# Convert Video
# video2hls --video-bitrates 4500 2500 1300 800 400 --video-widths 1920 1280 854 640 427  --no-poster --no-mp4 <path/to/file/>
# Optimise Images
# gm convert -resize 720x720 -strip -interlace Plane -quality 80 <path/to/original> <path/to/new>
# Create pending collection
# Upload Media
# Publish collection
