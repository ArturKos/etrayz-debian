#!/bin/sh
# settings.sh — CGI endpoint for EtrayZ settings
# GET  → returns current settings + live status as JSON
# POST → saves settings and applies them

CONF=/etc/etrayz/settings.conf
DEFAULTS=/etc/etrayz/defaults.conf

# URL-decode helper
urldecode() {
    echo "$1" | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf "%b" 2>/dev/null || echo "$1"
}

# Read settings file as JSON
settings_to_json() {
    [ -f "$CONF" ] || cp "$DEFAULTS" "$CONF"
    . "$CONF"

    # Live status
    FAN_TEMP=$(awk '/temps_counter/{print $NF}' /proc/therm-fan 2>/dev/null)
    FAN_RPM=$(awk '/measured-fan_speed/{print $NF}' /proc/therm-fan 2>/dev/null)
    FAN_CUR=$(awk '/set_fan_speed/{print $NF}' /proc/therm-fan 2>/dev/null)
    USB_STATE=$(cat /sys/bus/usb/devices/usb1/authorized 2>/dev/null)
    USB_DEV=""
    USB_MOUNT=""
    for dev in /sys/block/sd[b-z] ; do
        [ -d "$dev" ] || continue
        # Skip SATA devices (USB devices have 'usb' in their sysfs path)
        DEVPATH=$(readlink -f "$dev/device" 2>/dev/null)
        case "$DEVPATH" in */usb*) USB_DEV=$(basename "$dev") ;; esac
    done
    [ -n "$USB_DEV" ] && USB_MOUNT=$(mount | grep "/dev/$USB_DEV" | awk '{print $3}')
    TRANS_RUNNING=0
    pidof transmission-daemon >/dev/null 2>&1 && TRANS_RUNNING=1
    SAMBA_RUNNING=0
    pidof smbd >/dev/null 2>&1 && SAMBA_RUNNING=1
    SSH_RUNNING=0
    pidof sshd >/dev/null 2>&1 && SSH_RUNNING=1
    DLNA_RUNNING=0
    pidof minidlna >/dev/null 2>&1 && DLNA_RUNNING=1
    ARIA2_RUNNING=0
    pidof aria2c >/dev/null 2>&1 && ARIA2_RUNNING=1
    SSH_KEYS=""
    [ -f /home/sysadmin/.ssh/authorized_keys ] && SSH_KEYS=$(cat /home/sysadmin/.ssh/authorized_keys 2>/dev/null | sed 's/"/\\"/g' | tr '\n' '|')
    CUR_TZ=$(cat /etc/timezone 2>/dev/null)

    # Disk 2 status
    DISK2_DETECTED=0
    DISK2_DEV=""
    DISK2_FSTYPE=""
    DISK2_MOUNTED=""
    DISK2_SIZE=""
    DISK2_USED=""
    if [ -d /sys/block/sdb ]; then
        # Check it's SATA not USB
        D2PATH=$(readlink -f /sys/block/sdb/device 2>/dev/null)
        case "$D2PATH" in */usb*) ;; *)
            DISK2_DETECTED=1
            if [ -b /dev/sdb1 ]; then DISK2_DEV=sdb1; else DISK2_DEV=sdb; fi
            DISK2_FSTYPE=$(blkid -s TYPE -o value /dev/$DISK2_DEV 2>/dev/null)
            DISK2_MOUNTED=$(mount | grep "^/dev/$DISK2_DEV " | awk '{print $3}')
            if [ -n "$DISK2_MOUNTED" ]; then
                DISK2_SIZE=$(df -h "$DISK2_MOUNTED" 2>/dev/null | tail -1 | awk '{print $3"/"$2}')
                DISK2_USED=$(df "$DISK2_MOUNTED" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
            else
                # Get raw size from /proc/partitions
                BLOCKS=$(awk "/[[:space:]]${DISK2_DEV}\$/{print \$3}" /proc/partitions 2>/dev/null)
                [ -n "$BLOCKS" ] && DISK2_SIZE="$(( BLOCKS / 1048576 ))G raw"
            fi
        ;; esac
    fi

    cat << JSONEOF
{
"timezone":"${TIMEZONE}","cur_tz":"${CUR_TZ}",
"dashboard_auth":"${DASHBOARD_AUTH}",
"beep_startup":"${BEEP_STARTUP}","beep_pattern":"${BEEP_PATTERN}","beep_torrent":"${BEEP_TORRENT}",
"fan_mode":"${FAN_MODE}","fan_speed":"${FAN_SPEED}",
"fan_temp":"${FAN_TEMP}","fan_rpm":"${FAN_RPM}","fan_cur":"${FAN_CUR}",
"usb_enabled":"${USB_ENABLED}","usb_automount":"${USB_AUTOMOUNT}",
"usbcopy_enabled":"${USBCOPY_ENABLED}","usbcopy_target":"${USBCOPY_TARGET}",
"usb_state":"${USB_STATE}","usb_dev":"${USB_DEV}","usb_mount":"${USB_MOUNT}",
"samba_workgroup":"${SAMBA_WORKGROUP}",
"samba_home_enabled":"${SAMBA_HOME_ENABLED}","samba_home_path":"${SAMBA_HOME_PATH}","samba_home_guest":"${SAMBA_HOME_GUEST}","samba_home_readonly":"${SAMBA_HOME_READONLY}",
"samba_public_enabled":"${SAMBA_PUBLIC_ENABLED}","samba_public_path":"${SAMBA_PUBLIC_PATH}","samba_public_guest":"${SAMBA_PUBLIC_GUEST}","samba_public_readonly":"${SAMBA_PUBLIC_READONLY}",
"samba_downloads_enabled":"${SAMBA_DOWNLOADS_ENABLED}","samba_downloads_path":"${SAMBA_DOWNLOADS_PATH}","samba_downloads_guest":"${SAMBA_DOWNLOADS_GUEST}","samba_downloads_readonly":"${SAMBA_DOWNLOADS_READONLY}",
"trans_enabled":"${TRANS_ENABLED}","trans_download_dir":"${TRANS_DOWNLOAD_DIR}","trans_incomplete_dir":"${TRANS_INCOMPLETE_DIR}","trans_watch_dir":"${TRANS_WATCH_DIR}",
"trans_speed_up":"${TRANS_SPEED_UP}","trans_speed_down":"${TRANS_SPEED_DOWN}","trans_ratio":"${TRANS_RATIO}","trans_peer_port":"${TRANS_PEER_PORT}","trans_rpc_whitelist":"${TRANS_RPC_WHITELIST}",
"trans_running":"${TRANS_RUNNING}","samba_running":"${SAMBA_RUNNING}","ssh_running":"${SSH_RUNNING}","dlna_running":"${DLNA_RUNNING}",
"dlna_enabled":"${DLNA_ENABLED}","dlna_name":"${DLNA_NAME}","dlna_port":"${DLNA_PORT}","dlna_media_dir":"${DLNA_MEDIA_DIR}","dlna_inotify":"${DLNA_INOTIFY}",
"aria2_enabled":"${ARIA2_ENABLED}","aria2_running":"${ARIA2_RUNNING}","aria2_download_dir":"${ARIA2_DOWNLOAD_DIR}","aria2_max_concurrent":"${ARIA2_MAX_CONCURRENT}","aria2_max_conn":"${ARIA2_MAX_CONN}","aria2_upload_limit":"${ARIA2_UPLOAD_LIMIT}","aria2_rpc_port":"${ARIA2_RPC_PORT}",
"ssh_port":"${SSH_PORT}","ssh_root_login":"${SSH_ROOT_LOGIN}","ssh_password_auth":"${SSH_PASSWORD_AUTH}",
"ssh_keys":"${SSH_KEYS}",
"disk2_enabled":"${DISK2_ENABLED}","disk2_mount":"${DISK2_MOUNT}","disk2_format_new":"${DISK2_FORMAT_NEW}",
"disk2_share_enabled":"${DISK2_SHARE_ENABLED}","disk2_share_name":"${DISK2_SHARE_NAME}","disk2_share_guest":"${DISK2_SHARE_GUEST}","disk2_share_readonly":"${DISK2_SHARE_READONLY}",
"disk2_detected":"${DISK2_DETECTED}","disk2_dev":"${DISK2_DEV}","disk2_fstype":"${DISK2_FSTYPE}","disk2_mounted":"${DISK2_MOUNTED}","disk2_size":"${DISK2_SIZE}","disk2_used":"${DISK2_USED}",
"dashboard_port":"${DASHBOARD_PORT}","website_port":"${WEBSITE_PORT}","website_title":"${WEBSITE_TITLE}",
"dev_gcc":"$(gcc --version 2>/dev/null | head -1 | sed 's/gcc (Debian //' | sed 's/) .*//')",
"dev_make":"$(make --version 2>/dev/null | head -1 | sed 's/GNU Make //')",
"dev_glibc":"$(ldd --version 2>/dev/null | head -1 | awk '{print $NF}')",
"dev_kernel":"$(uname -r 2>/dev/null)",
"dev_php":"$(dpkg -s php5-cgi 2>/dev/null | awk '/^Version:/{print $2}')",
"dev_python":"$(python --version 2>&1 | awk '{print $2}')",
"dev_shell":"dash 0.5 + bash",
"dev_sqlite":"$(sqlite3 -version 2>/dev/null | awk '{print $1}')",
"dev_dropbear":"$(/usr/local/sbin/dropbear -V 2>&1 | sed -n 's/.*v\(.*\)/\1/p')",
"dev_dropbear_running":"$(pidof dropbear >/dev/null 2>&1 && echo 1 || echo 0)"
}
JSONEOF
}

save_settings() {
    # Read POST data (CONTENT_LENGTH bytes from stdin)
    if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
        POST_DATA=$(dd bs="$CONTENT_LENGTH" count=1 2>/dev/null)
    else
        read -r POST_DATA
    fi
    [ -z "$POST_DATA" ] && { echo '{"error":"no data"}'; return; }

    # Check for special actions
    case "$POST_DATA" in
        action=reset*)
            cp "$DEFAULTS" "$CONF"
            echo '{"ok":1,"msg":"Reset to defaults"}'
            sudo /usr/local/bin/etrayz-apply all >/dev/null 2>&1 &
            return
            ;;
        action=usb_mount*)
            # Find USB block device
            for dev in /sys/block/sd[b-z]; do
                [ -d "$dev" ] || continue
                USBDEV="/dev/$(basename $dev)1"
                mkdir -p /mnt/usb
                sudo mount "$USBDEV" /mnt/usb 2>&1 && echo '{"ok":1,"msg":"Mounted"}' || echo '{"ok":0,"msg":"Mount failed"}'
                return
            done
            echo '{"ok":0,"msg":"No USB device"}'
            return
            ;;
        action=usb_unmount*)
            sudo umount /mnt/usb 2>&1 && echo '{"ok":1,"msg":"Unmounted"}' || echo '{"ok":0,"msg":"Unmount failed"}'
            return
            ;;
        action=usb_copy*)
            . "$CONF"
            USB_MOUNT=$(mount | grep "/dev/sd[b-z]" | head -1 | awk '{print $3}')
            if [ -n "$USB_MOUNT" ]; then
                mkdir -p "$USBCOPY_TARGET"
                sudo cp -r "$USB_MOUNT"/* "$USBCOPY_TARGET"/ 2>/dev/null &
                echo '{"ok":1,"msg":"Copy started"}'
            else
                echo '{"ok":0,"msg":"No USB mounted"}'
            fi
            return
            ;;
        action=disk2_mount*)
            . "$CONF"
            sudo /etc/init.d/etrayz-disk2 start 2>&1
            sleep 1
            if mount | grep -q " ${DISK2_MOUNT:-/home2} "; then
                echo '{"ok":1,"msg":"Disk 2 mounted"}'
            else
                echo '{"ok":0,"msg":"Mount failed — check log"}'
            fi
            sudo /usr/local/bin/etrayz-apply samba >/dev/null 2>&1 &
            return
            ;;
        action=disk2_unmount*)
            . "$CONF"
            sudo umount "${DISK2_MOUNT:-/home2}" 2>&1 && echo '{"ok":1,"msg":"Disk 2 unmounted"}' || echo '{"ok":0,"msg":"Unmount failed"}'
            sudo /usr/local/bin/etrayz-apply samba >/dev/null 2>&1 &
            return
            ;;
        action=disk2_format*)
            if [ -d /sys/block/sdb ]; then
                # Safety: refuse if mounted
                if mount | grep -q "^/dev/sdb"; then
                    echo '{"ok":0,"msg":"Unmount disk first"}'
                    return
                fi
                sudo mkfs.xfs -f -L etrayz-data2 /dev/sdb 2>&1
                if [ $? -eq 0 ]; then
                    echo '{"ok":1,"msg":"Formatted as XFS"}'
                else
                    echo '{"ok":0,"msg":"Format failed"}'
                fi
            else
                echo '{"ok":0,"msg":"No disk in bay 2"}'
            fi
            return
            ;;
        action=dlna_rescan*)
            sudo /etc/init.d/minidlna force-reload 2>/dev/null &
            echo '{"ok":1,"msg":"DLNA rescan started"}'
            return
            ;;
        action=test_buzzer*)
            PATTERN=$(echo "$POST_DATA" | sed 's/.*pattern=\([^&]*\).*/\1/')
            sudo /usr/local/bin/etrayz-buzzer "$PATTERN" 2>/dev/null &
            echo '{"ok":1}'
            return
            ;;
        action=dropbear_start*)
            if [ -x /usr/local/sbin/dropbear ]; then
                sudo /etc/init.d/dropbear start 2>/dev/null
                sleep 1
                if pidof dropbear >/dev/null 2>&1; then
                    echo '{"ok":1,"msg":"Dropbear started"}'
                else
                    echo '{"ok":0,"msg":"Dropbear failed to start"}'
                fi
            else
                echo '{"ok":0,"msg":"Dropbear not installed"}'
            fi
            return
            ;;
        action=dropbear_stop*)
            sudo /etc/init.d/dropbear stop 2>/dev/null
            echo '{"ok":1,"msg":"Dropbear stopped"}'
            return
            ;;
        action=save_keys*)
            KEYS=$(echo "$POST_DATA" | sed 's/action=save_keys&keys=//')
            KEYS=$(urldecode "$KEYS")
            mkdir -p /home/sysadmin/.ssh
            echo "$KEYS" | tr '|' '\n' | grep -v '^$' > /home/sysadmin/.ssh/authorized_keys
            chown -R sysadmin:sysadmin /home/sysadmin/.ssh
            chmod 700 /home/sysadmin/.ssh
            chmod 600 /home/sysadmin/.ssh/authorized_keys
            echo '{"ok":1,"msg":"Keys saved"}'
            return
            ;;
        action=load_accounts*)
            ACCT_DIR="/etc/etrayz/aria2-accounts"
            mkdir -p "$ACCT_DIR"
            echo -n '{"accounts":['
            FIRST=1
            for f in "$ACCT_DIR"/*.conf; do
                [ -f "$f" ] || continue
                SVC=""; USR=""; PASS=""; REF=""; COOK=""
                . "$f"
                COOKFILE="$ACCT_DIR/$(basename "$f" .conf).cookies"
                [ -f "$COOKFILE" ] && COOK=$(cat "$COOKFILE" 2>/dev/null | sed 's/\\/\\\\/g;s/"/\\"/g' | tr '\n' '|')
                [ "$FIRST" = "1" ] && FIRST=0 || echo -n ','
                echo -n "{\"service\":\"$SVC\",\"user\":\"$USR\",\"pass\":\"$PASS\",\"referer\":\"$REF\",\"cookies\":\"$COOK\"}"
            done
            echo ']}'
            return
            ;;
        action=save_accounts*)
            DATA=$(echo "$POST_DATA" | sed 's/^action=save_accounts&data=//')
            DATA=$(urldecode "$DATA")
            ACCT_DIR="/etc/etrayz/aria2-accounts"
            mkdir -p "$ACCT_DIR"
            # Clear old accounts
            rm -f "$ACCT_DIR"/*.conf "$ACCT_DIR"/*.cookies 2>/dev/null
            # Parse JSON array manually — each account is {service,user,pass,referer,cookies}
            # Use awk to split the JSON array into individual objects
            IDX=0
            echo "$DATA" | sed 's/^\[//;s/\]$//' | awk 'BEGIN{RS="},{";ORS="\n"}{gsub(/^{/,"");gsub(/}$/,"");print}' | while read -r OBJ; do
                SVC=$(echo "$OBJ" | sed 's/.*"service":"\([^"]*\)".*/\1/')
                USR=$(echo "$OBJ" | sed 's/.*"user":"\([^"]*\)".*/\1/')
                PASS=$(echo "$OBJ" | sed 's/.*"pass":"\([^"]*\)".*/\1/')
                REF=$(echo "$OBJ" | sed 's/.*"referer":"\([^"]*\)".*/\1/')
                COOK=$(echo "$OBJ" | sed 's/.*"cookies":"\([^"]*\)".*/\1/')
                [ -z "$SVC" ] && SVC="account_${IDX}"
                # Sanitize service name for filename
                FNAME=$(echo "$SVC" | tr -c 'a-zA-Z0-9._-' '_')
                cat > "$ACCT_DIR/${FNAME}.conf" << ACCTEOF
SVC="$SVC"
USR="$USR"
PASS="$PASS"
REF="$REF"
ACCTEOF
                # Save cookies to separate file (may be multi-line, pipe-separated from JS)
                if [ -n "$COOK" ]; then
                    echo "$COOK" | tr '|' '\n' | grep -v '^$' > "$ACCT_DIR/${FNAME}.cookies"
                fi
                IDX=$((IDX + 1))
            done
            chmod 600 "$ACCT_DIR"/*.conf "$ACCT_DIR"/*.cookies 2>/dev/null
            chown www-data:www-data "$ACCT_DIR"/*.conf "$ACCT_DIR"/*.cookies 2>/dev/null
            echo '{"ok":1,"msg":"Accounts saved"}'
            return
            ;;
    esac

    # Parse key=value pairs from POST and write to settings.conf
    # Start with current settings as base, overlay with POST values
    cp "$CONF" /tmp/settings_new.conf

    # Parse each field from POST data
    OLD_IFS="$IFS"
    IFS='&'
    for pair in $POST_DATA; do
        key=$(echo "$pair" | cut -d= -f1)
        val=$(echo "$pair" | cut -d= -f2-)
        val=$(urldecode "$val")

        KEY_UPPER=$(echo "$key" | tr 'a-z' 'A-Z')
        # Update in temp file
        if grep -q "^${KEY_UPPER}=" /tmp/settings_new.conf; then
            # Quote values containing spaces
            case "$val" in *" "*) val="\"${val}\"" ;; esac
            sed -i "s|^${KEY_UPPER}=.*|${KEY_UPPER}=${val}|" /tmp/settings_new.conf
        fi
    done
    IFS="$OLD_IFS"

    cp /tmp/settings_new.conf "$CONF"
    rm -f /tmp/settings_new.conf

    # Output response before applying (apply can be slow)
    echo '{"ok":1,"msg":"Settings saved and applied"}'

    # Apply all settings in background
    sudo /usr/local/bin/etrayz-apply all >/dev/null 2>&1 &
}

# --- Main ---
echo "Content-Type: application/json"
echo ""

if [ "$REQUEST_METHOD" = "POST" ]; then
    save_settings
else
    settings_to_json
fi
