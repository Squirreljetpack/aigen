#!/bin/zsh
# 
setopt +o nomatch; # suppress glob err msg zsh

MAX_TRIALS=3

# Default values
manager="--user"
SYSD_DIR=$HOME/.config/systemd/user
VERBOSE=false
FILES_DIR=./aigen # files are stored here: todo, set to SYS_DIR
MAX_TRIALS=5 # retries for improving output

usage(){
    echo "Usage:  $0 [-s manager] [-v] [-f FILES_DIR] [-t max_tries]
    Autogenerates a systemd timer for you!"
}

while getopts "s:v" opt; do
  case ${opt} in
    s )
      manager=--system
      SYSD_DIR="/etc/systemd/system/"
      ;;
    v )
      VERBOSE=true
      ;;
    f )
      FILES_DIR=$OPTARG
      ;;
    t )
      MAX_TRIALS=$OPTARG
      ;;
    
    \? )
      echo "Usage: $0 [-s manager] [-v]"
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))


created_files=()

create_file() {
  local filename="$1"
  local content="$2"
  if [[ -t 0 ]]; then
    echo "$content" > "$FILES_DIR/$filename"
  else
    cat > "$FILES_DIR/$filename"
  fi

  printf "Content written to "; info "$FILES_DIR/$filename" "\n"
  created_files+=("$filename")
  verify_and_fix_systemd_file "$FILES_DIR/$filename"
}


dbg() {
    echo "\e[47m\e[30m${@}\e[0m" >&2
}
info() {
    printf "\e[32m${1}\e[0m${2}"
}
err() {
    echo "\e[41m${@}\e[0m" >&2
}

direct() {
    echo "\e[1m\e[34m${@}\e[0m"
}

generate_unique_filename() {
    local name="$1"
    local extension="$2"
    local description="$3"
    local filename
    local dir
    done=false
    valid=true
    while true; do
      while [[ $valid == false ]] || ls "$FILES_DIR/$name"* >/dev/null 2>&1;  do
          filename=$(aichat -r filenamer "${description}
Extension: .${extension}" | grep -o "[[:alnum:]]*\.$extension" | head -n 1) # adjust temp/top_p
          dir=$(dirname "$filename")
          name=$(basename "$filename")
          name="${name%.*}"
          [[ -n "$name" ]] && valid=true
          dbg "$filename"
      done
      { printf "Chosen name: "; info "$name" " (Empty to accept): "; } >&2
      read -r answ
      [[ -z "$answ" ]] && echo "$name" && return 0
      valid=false
    done
}

generate_description() {
    local script_path="$1"
    local additional_info
    local description
    [[ -z "$2" ]] && additionl_info="" || additional_info="Additionally: $2."

    while (( trials < MAX_TRIALS )); do
        description=$(aichat -f "$(realpath $1)" "Provide a concise one-paragraph description of the purpose of the included script, suitable as a description field for a systemd unit file.$additional_info Begin your answer with Description="  | awk '{$1=$1};1' | grep . | head -n 1)
        if [[ $? -ne 0 ]]; then
            err "Error generating description. Please try again."
            continue
        fi
        if [[ $description == Description=* ]]; then
            echo "$description"
            return 0
        else
            dbg "$description"
            err "Generated description doesn't start with 'Description='. Retrying..."
        fi
        ((trials++))
    done
}

write_files() {
    local content="$1"
    local selection="$2"
    local base_filename="$3"

    # Process the blocks of content into an array
    local blocks=()
    local in_block=0
    local current_block=""
    local answ

    while IFS= read -r line; do
        if [[ "$line" == '```'* ]]; then
            if (( $in_block == 1 )); then
                blocks+=("$current_block")
                dbg "$(( ${#blocks[@]}+1 )): "
                dbg "$current_block"
                current_block=""
            fi
            (( in_block ^= 1 ))
        elif (( $in_block == 1 )); then
            current_block+="$line"$'\n'
        fi
    done <<< "$content"

    # If there's a last block, add it
    # if [[ -n "$current_block" ]]; then
    #     blocks+=("$current_block")
    # fi

    # Display available blocks
    # echo "Available blocks:"
    # for i in "${!blocks[@]}"; do
    #     echo "$((i + 1)):"
    #     echo "${blocks[$i]}"
    #     echo "---"
    # done

    # Process selection
    if [[ -z "$selection" ]]; then
      selected_indices=($(seq 1 ${#blocks[@]}))
    else
      selected_indices=("${(@s/,/)selection}")
    fi
    # todo, 0 index
    for index in "${selected_indices[@]}"; do
    if (( index > 0 && index <= ${#blocks[@]} )); then
    
        filename="${base_filename}_$index.timer"
        create_file "$filename" "${blocks[$index]}"

        # Insert Unit link, do it after create for more consistency
        tempfile=$(mktemp)
        awk -v base_filename="$base_filename" '
        /^Unit=/ { next }
        /^\[Timer\]/ { print; print "Unit=" base_filename ".service"; next }
        { print }
        ' < "$FILES_DIR/$filename" > "$tempfile"

        mv "$tempfile" "$FILES_DIR/$filename"
        else
            err "Invalid selection: $index. Retry..."
        fi
    done
    printf "Please review the following files: (Enter)"
    read
    for index in "${selected_indices[@]}"; do
        $EDITOR "$FILES_DIR/${base_filename}_$index.timer"
    done
    printf "Proceed or (R)egenerate?: (P) "
    read answ
    [[ "$answ" == "${answ#Rr}" ]] && return 0 || return 1
}

verify_and_fix_systemd_file() {
    local file_path="$1"
    local max_retries=3
    local retry_count=0

    while (( retry_count < max_retries )); do
        if systemd-analyze verify "$file_path"; then
            return 0
        else
            local error_message=$(systemd-analyze verify "$file_path" 2>&1)
            dbg "Verification failed: $error_message. Attempting to fix..."
            
            local fixed_content=$(aichat .role fix-source -f "$file_path" "The following systemd unit file failed verification. Please cat the fixed version. Error message: $error_message" |
                awk '
                    /```/ {
                        if (flag == 1) {
                            exit
                        }
                        flag++
                        next
                    }
                    flag == 1 && NF {
                        print
                    }
                ')
            
            echo "$fixed_content" > "$file_path"
            ((retry_count++))
        fi
    done

    err "Failed to fix systemd file after $max_retries attempts."
    return 1
}


# Main script
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <script_path>"
    exit 1
fi

script_path="$(realpath $1)"
script_filename=$(basename "$script_path")
script_ext="${script_filename##*.}"
script_name="${script_filename%.*}"

# Generate service file description
service_file_desc=$(generate_description "$script_path" "")

while true; do
    echo "Current description:"
    echo "$service_file_desc"
    direct "Enter to accept, or type a message to revise: "
    read -r comment
    
    [[ -z "$comment" ]] && break
    
    service_file_desc=$(generate_description "$script_path" "$comment")
done

# Create service file content
service_file_content="[Unit]
$service_file_desc

[Service]
Type=oneshot
ExecStart=$script_path

[Install]
WantedBy=default.target
"


          

mkdir -p "$FILES_DIR"
dbg "$script_name" "service"  "$service_file_desc"
service_filename=$(generate_unique_filename "$script_name" "service"  "$service_file_desc")
create_file "$service_filename.service" "$service_file_content"



# Generate timer file
direct "Enter a description for your desired schedule:"
read -r schedule_description
echo
echo "...generating..."
echo
while true; do
    trials=0
    while (( trials < MAX_TRIALS )); do
        service_timer_content=$(aichat -r sysdtimer "$schedule_description")
          onCal=$(echo "$service_timer_content" | grep "OnCalendar=")
          if [[ -z "$onCal" ]] || systemd-analyze calendar $(cut -d'=' -f 2- <<< "$onCal"); then
            break
          fi
          dbg "$service_timer_content"
          if grep -qi "impossible" <<< "$onCal"; then
            echo "WARN: Model deems your request is likely impossible" >&2
            break
          fi
        ((trials++))
    done

    echo
    echo "...round complete..."
    echo
    
    if (( trials == MAX_TRIALS )); then
        err "WARN: max trials exceeded" >&2
    fi

    
    info "Generated timer content" "(Each block will be created as a seperate file linked to the service unit):\n"
    echo "$service_timer_content"
    direct "Enter comma sperated list of files to apply (default all), type a message to revise, or Ctrl-C to exit: "
    read -r comment
    [[ "$comment" =~ ^[1234567890,]*$ ]] && write_files "$service_timer_content" "$comment" "${service_filename%.*}" && break
    echo
    echo "--------------------------------------------------------"
    echo
done

# TODO: cleanup if unsuccessful


# direct "Enter the directory to symlink to (default: $SYSD_DIR): "
# read -r symlink_dir

# if [[ "$symlink_dir" != "$FILES_DIR" ]]; then
#     mkdir -p "$symlink_dir"
#     for file in "$FILES_DIR"/*; do
#         ln -sfn "$file" "$symlink_dir/$(basename "$file")"
#     done
#     echo "Symlinks created in $symlink_dir"
# fi

# Ask to enable units
direct "Do you want to enable and start the units? (Y/n): "
read -r enable_units
succeeded=0
if [[ -z "$enable_units" || "$enable_units" =~ ^[Yy]$ ]]; then
    for unit in "${created_files[@]}"; do
        systemctl --user enable --now "$(realpath $FILES_DIR/$unit)" && (( succeeded+=1 ))
    done
fi

(( $succeeded < ${#created_files[@]} )) && printf "\e[41m$succeeded\e[0m" || info "$succeeded"; echo "/${#created_files[@]} units enabled. Execution complete."

