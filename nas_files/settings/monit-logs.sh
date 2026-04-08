#!/bin/sh
# CGI log viewer — dark themed, matches dashboard/monit proxy
# Usage: /cgi-bin/monit-logs.sh?log=messages&lines=100

# Parse query string
LOG="messages"
LINES=100
if [ -n "$QUERY_STRING" ]; then
  for param in $(echo "$QUERY_STRING" | tr '&' ' '); do
    key=$(echo "$param" | cut -d= -f1)
    val=$(echo "$param" | cut -d= -f2-)
    case "$key" in
      log) LOG="$val" ;;
      lines) LINES="$val" ;;
    esac
  done
fi

# Whitelist of allowed log files (security)
case "$LOG" in
  messages|syslog|monit.log|daemon.log|auth.log|kern.log|minidlna.log)
    LOGFILE="/var/log/$LOG" ;;
  transmission)
    LOGFILE="/var/log/transmission-daemon/transmission-daemon.log" ;;
  samba)
    LOGFILE="/var/log/samba/log.smbd" ;;
  etrayz-disk2)
    LOGFILE="/var/log/etrayz-disk2.log" ;;
  *)
    LOGFILE="/var/log/messages" ; LOG="messages" ;;
esac

# Cap lines
[ "$LINES" -gt 500 ] 2>/dev/null && LINES=500
[ "$LINES" -lt 10 ] 2>/dev/null && LINES=10

echo "Content-Type: text/html"
echo ""

cat <<'HTMLHEAD'
<!DOCTYPE html><html><head><title>EtrayZ Logs</title>
<style>
body{background:#0a0e17;color:#c5cdd9;margin:0;font-family:"Courier New",monospace;font-size:12px}
.header{background:#111827;border-bottom:1px solid #1e293b;padding:12px 20px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px}
.header a{color:#00ff88;text-decoration:none;font-size:13px}
.header a:hover{text-decoration:underline}
.title{color:#fff;font-size:14px;font-weight:bold;letter-spacing:1px}
.nav{display:flex;gap:6px;flex-wrap:wrap}
.nav a{padding:4px 10px;border:1px solid #1e293b;border-radius:4px;color:#5a6a7a;font-size:11px;text-decoration:none;transition:all .2s}
.nav a:hover,.nav a.active{border-color:#00ff88;color:#00ff88;background:#0f1a2b}
.controls{display:flex;align-items:center;gap:12px;padding:8px 20px;background:#0d1321;border-bottom:1px solid #1e293b}
.controls label{color:#5a6a7a;font-size:11px}
.controls select,.controls input{background:#111827;border:1px solid #1e293b;color:#00ff88;padding:4px 8px;border-radius:4px;font-family:inherit;font-size:11px}
.log{padding:12px 20px;white-space:pre-wrap;word-wrap:break-word;line-height:1.6;overflow-x:auto}
.log .ts{color:#5a6a7a}
.log .host{color:#00cc6a}
.log .proc{color:#f0ad4e}
.log .err{color:#ff4444;font-weight:bold}
.log .warn{color:#f0ad4e}
.footer{text-align:center;padding:12px;color:#2a3a4a;font-size:10px;border-top:1px solid #1e293b}
</style></head><body>
HTMLHEAD

# Navigation
cat <<HTMLNAV
<div class="header">
  <span class="title">&#x2630; System Logs</span>
  <div class="nav">
    <a href="/cgi-bin/monit-logs.sh?log=messages&lines=${LINES}" class="$([ "$LOG" = "messages" ] && echo active)">messages</a>
    <a href="/cgi-bin/monit-logs.sh?log=syslog&lines=${LINES}" class="$([ "$LOG" = "syslog" ] && echo active)">syslog</a>
    <a href="/cgi-bin/monit-logs.sh?log=auth.log&lines=${LINES}" class="$([ "$LOG" = "auth.log" ] && echo active)">auth</a>
    <a href="/cgi-bin/monit-logs.sh?log=kern.log&lines=${LINES}" class="$([ "$LOG" = "kern.log" ] && echo active)">kernel</a>
    <a href="/cgi-bin/monit-logs.sh?log=daemon.log&lines=${LINES}" class="$([ "$LOG" = "daemon.log" ] && echo active)">daemon</a>
    <a href="/cgi-bin/monit-logs.sh?log=monit.log&lines=${LINES}" class="$([ "$LOG" = "monit.log" ] && echo active)">monit</a>
    <a href="/cgi-bin/monit-logs.sh?log=transmission&lines=${LINES}" class="$([ "$LOG" = "transmission" ] && echo active)">transmission</a>
    <a href="/cgi-bin/monit-logs.sh?log=samba&lines=${LINES}" class="$([ "$LOG" = "samba" ] && echo active)">samba</a>
    <a href="/cgi-bin/monit-logs.sh?log=minidlna.log&lines=${LINES}" class="$([ "$LOG" = "minidlna.log" ] && echo active)">dlna</a>
    <a href="/cgi-bin/monit-logs.sh?log=etrayz-disk2&lines=${LINES}" class="$([ "$LOG" = "etrayz-disk2" ] && echo active)">disk2</a>
  </div>
  <a href="/cgi-bin/monit-proxy.sh">&#x25C0; Monit</a>
</div>
<div class="controls">
  <label>Lines:</label>
  <select onchange="location.href='/cgi-bin/monit-logs.sh?log=${LOG}&lines='+this.value">
    <option $([ "$LINES" = "50" ] && echo selected) value="50">50</option>
    <option $([ "$LINES" = "100" ] && echo selected) value="100">100</option>
    <option $([ "$LINES" = "200" ] && echo selected) value="200">200</option>
    <option $([ "$LINES" = "500" ] && echo selected) value="500">500</option>
  </select>
  <label>File: ${LOGFILE}</label>
  <label style="margin-left:auto">Auto-refresh: 30s</label>
</div>
HTMLNAV

echo '<div class="log">'

if [ -f "$LOGFILE" ]; then
  # Read log and colorize
  tail -n "$LINES" "$LOGFILE" 2>/dev/null | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/^\([A-Z][a-z]\{2\} [ 0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\)/<span class="ts">\1<\/span>/' \
    -e 's/^\(\[[A-Z]\{2,4\} [A-Z][a-z]\{2\} [ 0-9]\{2\} [0-9:]\{8\}\]\)/<span class="ts">\1<\/span>/' \
    -e 's/ \(etrayz\|localhost\) / <span class="host">\1<\/span> /' \
    -e 's/ \([a-zA-Z][a-zA-Z0-9_.-]*\)\(\[[0-9]*\]\):/ <span class="proc">\1\2<\/span>:/' \
    -e 's/\(error\|Error\|ERROR\|failed\|Failed\|FAILED\)/<span class="err">\1<\/span>/g' \
    -e 's/\(warning\|Warning\|WARNING\)/<span class="warn">\1<\/span>/g'
else
  echo "<span class='err'>Log file not found: ${LOGFILE}</span>"
fi

echo '</div>'

cat <<HTMLFOOT
<div class="footer">EtrayZ NAS &middot; Log Viewer</div>
<script>setTimeout(function(){location.reload()},30000);window.scrollTo(0,document.body.scrollHeight);</script>
</body></html>
HTMLFOOT
