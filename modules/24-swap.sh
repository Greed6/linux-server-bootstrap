#!/usr/bin/env bash
# @group   system
# @title   Swap-файл и swappiness | Swap file and swappiness
# @default on
# @os      all

module_run() {
    local ram_mb def size file=/swapfile mb avail_mb fs swappiness

    if [[ -n $(swapon --show --noheadings 2>/dev/null) ]]; then
        info "$(L 'Swap уже есть:' 'Swap already exists:')"
        swapon --show
    else
        ram_mb=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
        if   (( ram_mb <= 2048 )); then def=2G
        elif (( ram_mb <= 8192 )); then def="$(( (ram_mb + 1023) / 1024 ))G"
        else def=4G; fi

        ask size SWAP_SIZE "$(L "Размер swap-файла (RAM: ${ram_mb} МБ)" "Swap file size (RAM: ${ram_mb} MB)")" "$def"
        if [[ ! $size =~ ^([0-9]+)([MG])$ ]]; then
            err "$(L 'Формат размера: 512M или 2G' 'Size format: 512M or 2G')"; return 1
        fi
        mb=${BASH_REMATCH[1]}; [[ ${BASH_REMATCH[2]} == G ]] && mb=$((mb * 1024))
        avail_mb=$(df -Pm / | awk 'NR==2 {print $4}')
        if (( avail_mb < mb + 1024 )); then
            err "$(L "Мало места на / (${avail_mb} МБ свободно)" "Not enough space on / (${avail_mb} MB free)")"; return 1
        fi

        fs=$(stat -f -c %T / 2>/dev/null)
        rm -f "$file"
        if [[ $fs == btrfs ]]; then
            truncate -s 0 "$file" && chattr +C "$file" 2>/dev/null
            dd if=/dev/zero of="$file" bs=1M count="$mb" status=none
        else
            fallocate -l "${mb}M" "$file" 2>/dev/null || dd if=/dev/zero of="$file" bs=1M count="$mb" status=none
        fi
        chmod 600 "$file"
        mkswap "$file" >/dev/null || { rm -f "$file"; return 1; }
        if ! swapon "$file"; then
            err "$(L 'swapon не сработал (контейнер или ФС без поддержки swap?)' 'swapon failed (container or FS without swap support?)')"
            rm -f "$file"; return 1
        fi
        backup /etc/fstab
        grep -qE "^$file\s" /etc/fstab || echo "$file none swap sw 0 0" >> /etc/fstab
        summary "Swap: $file ($size)"
    fi

    ask swappiness SWAPPINESS "vm.swappiness" "10"
    [[ $swappiness =~ ^[0-9]+$ ]] || swappiness=10
    mkdir -p /etc/sysctl.d
    echo "vm.swappiness = $swappiness" > /etc/sysctl.d/90-linux-start-swap.conf
    sysctl -q -w "vm.swappiness=$swappiness" 2>/dev/null
    summary "vm.swappiness = $swappiness"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }
