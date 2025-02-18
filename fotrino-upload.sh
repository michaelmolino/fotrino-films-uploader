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
            echo "Usage: $(basename "$0") [-d] /path/to/Media"
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

shopt -s nullglob

# Check OS
os=$(uname)
[[ "$os" = 'Darwin' ]] || { echo "Untested Operating System!"; read -r -p "Press enter to continue."; }

# Check dependencies
declare -a deps=("${video2hls}/video2hls" 'md5sum' 'tar' 'ffmpeg' 'gm' 'jq' 'curl')
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
[[ -n $1 && -d "$1" ]] || { echo "Usage: $(basename "$0") [-d] /path/to/Media"; fail=1; }

# STOP if there are errors
[[ $fail -eq 1 ]] && exit 1

# API Token Handling
read -r -p "Enter tokens JSON: " tokens
uploadToken=$(echo "$tokens" | jq -r '.uploadToken')
userToken=$(echo "$tokens" | jq -r '.userToken')
status=$(curl -s -o /dev/null -w "%{http_code}" $insecure -s -H "Authorization: Bearer $userToken" ${api}/api/upload/hello)
[[ "$status" == "200" ]] || { echo "Unable to validate tokens..."; exit 1; }

# Get metadata
metadata=$(curl -s -w "%{http_code}" $insecure -H "Authorization: Bearer $userToken" -H "X-Upload-Token: $uploadToken" ${api}/api/upload/metadata)
http_status="${metadata: -3}"
if [[ "$http_status" == "200" ]]; then
    metadata="${metadata%???}"
    channel_pending=$(echo "$metadata" | jq -r '.channel_pending')
    project_pending=$(echo "$metadata" | jq -r '.project_pending')
else
    echo "Unable to validate tokens..."
    exit 1;
fi

# STOP if there are errors
[[ $fail -eq 1 ]] && exit 1

# Check Media
files=("${1}/"Media.{mp4,mov,webm})
[[ ${#files[@]} -gt 0 ]] || { echo "Missing Media..."; fail=1; }

files=("${1}/"Preview.{jpg,jpeg,png,webp})
[[ ${#files[@]} -gt 0 ]] || { echo "Missing Preview..."; fail=1; }

if [[ "$project_pending" == true ]]; then
    files=("${1}/"Poster.{jpg,jpeg,png,webp})
    [[ ${#files[@]} -gt 0 ]] || { echo "Missing Poster..."; fail=1; }
fi

if [[ "$channel_pending" == true ]]; then
    files=("${1}/"Cover.{jpg,jpeg,png,webp})
    [[ ${#files[@]} -gt 0 ]] || { echo "Missing Cover..."; fail=1; }
fi

# STOP if there are errors
[[ $fail -eq 1 ]] && exit 1

# Process Media
files=("${1}/"Media.{mp4,mov,webm})
[[ ${#files[@]} -gt 0 ]] && { 
    "${video2hls}/video2hls" --no-poster --no-mp4 "${1}/"Media.* || { echo "Media failed to convert..."; exit 1; } 
    :
}

# Optimise Images
for file in "${1}/"*.{jpg,jpeg,png,webp}; do
    if [[ ! "$file" =~ _opt\.(jpg|jpeg|png|webp)$ ]]; then
        dir="$(dirname "${file}")"
        filename=$(basename -- "${file}")
        basefile="${filename%.*}"
        gm convert -resize 720x720 -strip -interlace Plane -quality 80 "${file}" "${dir}/${basefile}_opt.jpg" || { echo "$filename failed to process..."; exit 1; }
    fi
done

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

if [[ "$channel_pending" == true ]]; then
    file="${1}/Cover_opt.jpg"
    cover="covers/$(md5sum "${file}"|awk '{print $1}').jpg"
    process_object "$file" "$cover" "image/jpeg"
    coverUrl="${minio_web_root}/${cover}"
fi

if [[ "$project_pending" == true ]]; then
    file="${1}/Poster_opt.jpg"
    poster="posters/$(md5sum "${file}"|awk '{print $1}').jpg"
    process_object "$file" "$poster" "image/jpeg"
    posterUrl="${minio_web_root}/${poster}"
fi

file="${1}/Preview_opt.jpg"
preview="previews/$(md5sum "${file}"|awk '{print $1}').jpg"
process_object "$file" "$preview" "image/jpeg"
previewUrl="${minio_web_root}/${preview}"

hash=$(tar -C / -cf - "${1:1}/Media" |md5sum |awk '{print $1}')
for file in "${1}"/Media/*.ts; do
    object="media/${hash}/$(basename "$file")"
    process_object "$file" "$object" "video/mp4"
done

for file in "${1}"/Media/*.m3u8; do
    object="media/${hash}/$(basename "$file")"
    process_object "$file" "$object" "text/plain"
done
srcUrl="${minio_web_root}/media/${hash}/index.m3u8"

# Change pending status to false
payload="{ \"cover\": \"$coverUrl\", \"poster\": \"$posterUrl\", \"preview\": \"$previewUrl\", \"src\": \"$srcUrl\", \"type\": \"application/vnd.apple.mpegurl\" }"
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
