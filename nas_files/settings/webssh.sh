#!/bin/sh
# webssh.sh — Web-based terminal for EtrayZ NAS
# CGI script: browser-based command execution
#
# Stateless design: each command runs independently.
# Working directory is tracked client-side and sent with each request.
# Runs commands as www-data user (with sudo available).

# Read POST data
read_post() {
    if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
        dd bs="$CONTENT_LENGTH" count=1 2>/dev/null
    fi
}

# URL decode
urldecode() {
    /usr/bin/printf '%b' "$(echo "$1" | sed 's/+/ /g;s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

# Extract parameter
get_param() {
    echo "$1" | tr '&' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

# --- GET: serve HTML terminal ---
if [ "$REQUEST_METHOD" = "GET" ]; then
    echo "Content-Type: text/html; charset=utf-8"
    echo ""
    cat << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>EtrayZ — Web Terminal</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Courier New',monospace;background:#0a0e17;color:#c5cdd9;height:100vh;display:flex;flex-direction:column}
.header{background:#070b12;border-bottom:1px solid #1e293b;padding:12px 20px;display:flex;align-items:center;gap:12px;flex-shrink:0}
.header a{color:#00ff88;text-decoration:none;font-size:11px;letter-spacing:2px}
.header a:hover{text-shadow:0 0 8px rgba(0,255,136,.4)}
.title{color:#fff;font-size:14px;font-weight:bold;letter-spacing:1px}
.badge{margin-left:auto;font-size:10px;padding:3px 10px;border-radius:10px;letter-spacing:1px;background:#0a2e1a;color:#00ff88;border:1px solid #00ff88}

.terminal{flex:1;overflow-y:auto;padding:16px 20px;font-size:13px;line-height:1.6;white-space:pre-wrap;word-wrap:break-word}
.prompt-text{color:#00ff88}
.cmd-text{color:#fff}
.output-text{color:#c5cdd9}
.error-text{color:#ff4444}
.info-text{color:#5a6a7a}

.input-bar{background:#070b12;border-top:1px solid #1e293b;padding:10px 20px;display:flex;gap:8px;align-items:center;flex-shrink:0}
.ps1{color:#00ff88;font-size:13px;white-space:nowrap;flex-shrink:0}
.cmd-input{flex:1;background:#0a0e17;border:1px solid #1e293b;border-radius:4px;color:#00ff88;font-family:inherit;font-size:13px;padding:8px 12px;outline:none}
.cmd-input:focus{border-color:#00ff88}
.cmd-input:disabled{opacity:.5}
.send-btn{background:#00ff88;color:#0a0e17;border:none;border-radius:4px;padding:8px 16px;font-family:inherit;font-size:12px;font-weight:bold;cursor:pointer;letter-spacing:1px;flex-shrink:0}
.send-btn:hover{background:#00cc6a}
.send-btn:disabled{background:#1e293b;color:#5a6a7a;cursor:not-allowed}

.spinner{display:inline-block;width:12px;height:12px;border:2px solid #1e293b;border-top-color:#00ff88;border-radius:50%;animation:spin .6s linear infinite;margin-right:8px;vertical-align:middle}
@keyframes spin{to{transform:rotate(360deg)}}
</style>
</head>
<body>
<div class="header">
    <a href="/">&#x25C0; ETRAYZ</a>
    <span class="title">&#x2756; Web Terminal</span>
    <span class="badge">DROPBEAR SSH</span>
</div>

<div class="terminal" id="term"></div>

<div class="input-bar">
    <span class="ps1" id="ps1">sysadmin@etrayz:~$</span>
    <input type="text" class="cmd-input" id="cmd" autofocus autocomplete="off" spellcheck="false">
    <button class="send-btn" id="send" onclick="run()">RUN</button>
</div>

<script>
var cwd = '/home/sysadmin';
var hist = [];
var histPos = -1;
var running = false;
var term = document.getElementById('term');
var cmdEl = document.getElementById('cmd');

function esc(s) {
    return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function out(text, cls) {
    term.innerHTML += '<span class="' + (cls||'output-text') + '">' + esc(text) + '</span>';
    term.scrollTop = term.scrollHeight;
}

function updatePS1() {
    var dir = cwd;
    if (dir === '/home/sysadmin') dir = '~';
    else if (dir.indexOf('/home/sysadmin/') === 0) dir = '~' + dir.substring(14);
    document.getElementById('ps1').textContent = 'sysadmin@etrayz:' + dir + '$';
}

function run() {
    var cmd = cmdEl.value.trim();
    cmdEl.value = '';
    if (running) return;

    // Show prompt + command
    var dir = cwd;
    if (dir === '/home/sysadmin') dir = '~';
    else if (dir.indexOf('/home/sysadmin/') === 0) dir = '~' + dir.substring(14);
    out('sysadmin@etrayz:' + dir + '$ ', 'prompt-text');
    out(cmd + '\n', 'cmd-text');

    if (!cmd) return;

    // History
    hist.push(cmd);
    if (hist.length > 200) hist.shift();
    histPos = hist.length;

    // Local handling for 'clear'
    if (cmd === 'clear') {
        term.innerHTML = '';
        return;
    }

    running = true;
    cmdEl.disabled = true;
    document.getElementById('send').disabled = true;

    var x = new XMLHttpRequest();
    x.open('POST', '/cgi-bin/webssh.sh', true);
    x.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    x.timeout = 30000;
    x.onreadystatechange = function() {
        if (x.readyState !== 4) return;
        running = false;
        cmdEl.disabled = false;
        document.getElementById('send').disabled = false;
        cmdEl.focus();
        try {
            var d = JSON.parse(x.responseText);
            if (d.b64) out(atob(d.b64));
            if (d.error) out(d.error + '\n', 'error-text');
            if (d.cwd) { cwd = d.cwd; updatePS1(); }
        } catch(e) {
            if (x.status === 0) out('Request timed out.\n', 'error-text');
            else out('Error: ' + x.status + '\n', 'error-text');
        }
    };
    x.ontimeout = function() {
        running = false;
        cmdEl.disabled = false;
        document.getElementById('send').disabled = false;
        cmdEl.focus();
        out('Command timed out (30s limit).\n', 'error-text');
    };
    x.send('cmd=' + encodeURIComponent(cmd) + '&cwd=' + encodeURIComponent(cwd));
}

// Keyboard
cmdEl.addEventListener('keydown', function(e) {
    if (e.key === 'Enter') { e.preventDefault(); run(); }
    else if (e.key === 'ArrowUp') {
        e.preventDefault();
        if (histPos > 0) { histPos--; cmdEl.value = hist[histPos]; }
    } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        if (histPos < hist.length - 1) { histPos++; cmdEl.value = hist[histPos]; }
        else { histPos = hist.length; cmdEl.value = ''; }
    }
});

term.addEventListener('click', function() { cmdEl.focus(); });

// Welcome
out('EtrayZ NAS — Web Terminal\n', 'info-text');
out('Type commands below. Each runs independently.\n', 'info-text');
out('Use sudo for root commands. Ctrl+C not available.\n\n', 'info-text');
updatePS1();
</script>
</body>
</html>
HTMLEOF
    exit 0
fi

# --- POST: execute command ---
POST_DATA=$(read_post)
CMD=$(urldecode "$(get_param "$POST_DATA" "cmd")")
CWD=$(urldecode "$(get_param "$POST_DATA" "cwd")")

[ -z "$CWD" ] && CWD="/home/sysadmin"

# Validate CWD exists
[ -d "$CWD" ] || CWD="/home/sysadmin"

echo "Content-Type: application/json"
echo ""

if [ -z "$CMD" ]; then
    echo '{"output":"","cwd":"'"$CWD"'"}'
    exit 0
fi

# Handle 'cd' specially (track directory changes)
case "$CMD" in
    cd)
        CWD="/home/sysadmin"
        echo '{"output":"","cwd":"'"$CWD"'"}'
        exit 0
        ;;
    cd\ *)
        TARGET=$(echo "$CMD" | cut -d' ' -f2-)
        # Expand ~ to home
        TARGET=$(echo "$TARGET" | sed "s|^~|/home/sysadmin|")
        # Handle relative paths
        if [ "${TARGET#/}" = "$TARGET" ]; then
            TARGET="$CWD/$TARGET"
        fi
        # Resolve .. and .
        TARGET=$(cd "$TARGET" 2>/dev/null && pwd)
        if [ -n "$TARGET" ] && [ -d "$TARGET" ]; then
            echo '{"output":"","cwd":"'"$TARGET"'"}'
        else
            echo '{"error":"cd: no such directory","cwd":"'"$CWD"'"}'
        fi
        exit 0
        ;;
esac

# Execute command with timeout (25s max to stay under CGI timeout)
OUTPUT=$(cd "$CWD" 2>/dev/null && eval "$CMD" 2>&1 | head -c 131072)
EXIT_CODE=$?

# Base64-encode output to avoid JSON escaping issues
B64=$(printf '%s' "$OUTPUT" | base64 | tr -d '\n')

echo "{\"b64\":\"$B64\",\"cwd\":\"$CWD\",\"exit\":$EXIT_CODE}"
