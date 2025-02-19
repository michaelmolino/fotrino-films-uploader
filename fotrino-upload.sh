#!/usr/bin/env bash

# Credit to Vincent Bernat
video2hls="${HOME}/Workspace/video2hls"

# DON'T CHANGE ANYTHING BELOW THIS LINE

api='https://films.fotrino.com'
insecure=''
minio_web_root='https://media-us.fotrino.com'

while getopts ":d" OPTION; do
    case "$OPTION" in
        d)
            echo "WARNING: Running in dev-mode"
            api='https://localhost:8081'
            insecure='-k'
            minio_web_root='http://localhost:9000/fotrino'
            ;;
        ?)
            echo "Usage: $(basename "$0") [-d] /path/to/Media.mov"
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

shopt -s nullglob

# Check OS
os=$(uname)
[[ "$os" = 'Darwin' ]] || { echo "I've only tested this on Mac."; read -r -p "Press enter to continue anyway."; }

# Check dependencies
declare -a deps=("${video2hls}/video2hls" 'md5sum' 'tar' 'ffmpeg' 'jq' 'curl')
for dep in "${deps[@]}"; do
    which "$dep" &>/dev/null || { echo "Missing ${dep}..."; fail=1; }
done

# Check Python version
[[ $(python3 --version) == "Python 3."* ]] || { echo "Check Python version..."; fail=1; }

# Check for code updates
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
git --git-dir="${script_dir}/.git" --work-tree="$script_dir" fetch
[[ $(git --git-dir="${script_dir}/.git" --work-tree="$script_dir" status 2>/dev/null |grep -c "Your branch is up to date with" ) == 1 ]] || { echo "fotrino-upload script must be updated..."; fail=1; }
git --git-dir="${video2hls}/.git/" --work-tree="${video2hls}/" fetch
[[ $(git --git-dir="${video2hls}/.git/" --work-tree="${video2hls}/" status 2>/dev/null |grep -c "Your branch is up to date with" ) == 1 ]] || { echo "video2hls must be updated..."; fail=1; }

# Check command line parameter(s)
[[ -n $1 && -f "$1" ]] || { echo "Usage: $(basename "$0") [-d] /path/to/Media.mov"; fail=1; }

# STOP if there are errors
[[ $fail -eq 1 ]] && exit 1

# API Token Handling
read -r -p "Enter tokens JSON: " tokens
uploadToken=$(echo "$tokens" | jq -r '.uploadToken')
userToken=$(echo "$tokens" | jq -r '.userToken')
status=$(curl -s -o /dev/null -w "%{http_code}" $insecure -s -H "Authorization: Bearer $userToken" ${api}/api/upload/hello)
[[ "$status" == "200" ]] || { echo "Unable to validate user token..."; exit 1; }

# STOP if there are errors
[[ $fail -eq 1 ]] && exit 1

# Check Media
files=("${1}/"Media.{mp4,mov,webm})
[[ ${#files[@]} -gt 0 ]] || { echo "Missing Media..."; fail=1; }

# STOP if there are errors
[[ $fail -eq 1 ]] && exit 1

# Process Media
files=("${1}/"Media.{mp4,mov,webm})
[[ ${#files[@]} -gt 0 ]] && { 
    "${video2hls}/video2hls" --no-poster --no-mp4 "${1}" || { echo "Media failed to convert..."; exit 1; } 
    :
}

echo
read -r -p "Make sure there are no errors before continuing with upload. You can safely ignore the 'cannot extract codec' warning or any warnings about skipped resolutions. Press enter to continue."
echo

# Upload files
process_object () {
    file=$1; object=$2; type=$3
    while true; do
        echo "        $(date) Uploading: $(basename "$file")"
        url=$(curl -s $insecure -H "Authorization: Bearer $userToken" -H "X-Upload-Token: $uploadToken" -H "Content-Type: application/json" -X GET -d "{\"object\": \"${object}\"}" ${api}/api/upload/objectUrl 2>/dev/null | jq -r '.url')
        status=$(curl -X PUT -H "Content-Type: $type" --data-binary "@${file}" --progress-bar -o /dev/null -w "%{http_code}" "$url")
        if [[ "$status" == "200" ]]; then
            break
        fi
        echo "Retrying... (HTTP $status)"
        sleep 1
    done
}

echo
echo "$(date) Starting upload..."

media_folder="${1%.*}"
hash=$(tar -C / -cf - "${media_folder:1}" |md5sum |awk '{print $1}')
for file in "${media_folder}"/*.ts; do
    object="media/${hash}/$(basename "$file")"
    process_object "$file" "$object" "video/mp4"
done

for file in "${media_folder}"/*.m3u8; do
    object="media/${hash}/$(basename "$file")"
    process_object "$file" "$object" "text/plain"
done
srcUrl="${minio_web_root}/media/${hash}/index.m3u8"

# Change pending status to false
payload="{ \"src\": \"$srcUrl\", \"type\": \"application/vnd.apple.mpegurl\" }"
while true; do
    status=$(curl -s -o /dev/null -w "%{http_code}" $insecure \
        -H "Authorization: Bearer $userToken" \
        -H "X-Upload-Token: $uploadToken" \
        -H "Content-Type: application/json" \
        -X POST -d "$payload" ${api}/api/upload 2>/dev/null)

    if [[ "$status" == "200" ]]; then
        break
    fi
    echo "Retrying... (HTTP $status)"
    sleep 1
done

echo "Success!"

# NOTES
# I should replace video2hls with ffmpeg
# ffmpeg -i input.mp4 -map 0:v:0 -map 0:a:0 -c:a aac -b:a 128k -c:v h264 -crf 23 -g 48 -sc_threshold 0 \
#   -filter:v:0 "scale=-2:240"  -b:v:0 400k  -maxrate:v:0 450k  -bufsize:v:0 800k  -preset faster \
#   -filter:v:1 "scale=-2:480"  -b:v:1 800k  -maxrate:v:1 900k  -bufsize:v:1 1600k  -preset faster \
#   -filter:v:2 "scale=-2:720"  -b:v:2 2800k -maxrate:v:2 3000k -bufsize:v:2 5600k -preset faster \
#   -filter:v:3 "scale=-2:1080" -b:v:3 5000k -maxrate:v:3 5500k -bufsize:v:3 10000k -preset faster \
#   -f hls -hls_time 6 -hls_playlist_type vod \
#   -hls_segment_filename "hls/%v/segment_%03d.ts" \
#   -master_pl_name "hls/master.m3u8" \
#   -var_stream_map "v:0,a:0 v:1,a:0 v:2,a:0 v:3,a:0" \
#   "hls/%v/index.m3u8"