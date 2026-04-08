#!/bin/sh
# CGI web UI for aria2 download manager (XML-RPC, aria2 1.10.x)

RPC="http://localhost:6800/rpc"

xmlrpc() {
  METHOD="$1"; shift
  PARAMS=""
  for p in "$@"; do PARAMS="${PARAMS}${p}"; done
  curl -s -H 'Content-Type: text/xml' -d "<?xml version=\"1.0\"?><methodCall><methodName>${METHOD}</methodName><params>${PARAMS}</params></methodCall>" "$RPC" 2>/dev/null
}

# Simple string param wrapper
strparam() {
  echo "<param><value><string>$1</string></value></param>"
}

# URL-decode helper
urldecode() {
  echo "$1" | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf "%b" 2>/dev/null || echo "$1"
}

# Extract POST field value
postval() {
  echo "$POST_DATA" | sed "s/.*$1=\([^&]*\).*/\1/" | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf "%b" 2>/dev/null
}

# Handle POST actions
if [ "$REQUEST_METHOD" = "POST" ] && [ -n "$CONTENT_LENGTH" ]; then
  POST_DATA=$(dd bs="$CONTENT_LENGTH" count=1 2>/dev/null)
  ACTION=$(echo "$POST_DATA" | sed 's/.*action=\([^&]*\).*/\1/')
  case "$ACTION" in
    add)
      URL=$(postval url)
      HTTP_USER=$(postval http_user)
      HTTP_PASS=$(postval http_pass)
      REFERER=$(postval referer)
      COOKIE=$(postval cookie)
      OUTNAME=$(postval outname)

      if [ -n "$URL" ]; then
        # Build URI param
        URI_PARAM=$(strparam "$URL")

        # Build options struct
        OPTS=""
        [ -n "$HTTP_USER" ] && OPTS="${OPTS}<member><name>http-user</name><value><string>${HTTP_USER}</string></value></member>"
        [ -n "$HTTP_PASS" ] && OPTS="${OPTS}<member><name>http-passwd</name><value><string>${HTTP_PASS}</string></value></member>"
        [ -n "$REFERER" ] && OPTS="${OPTS}<member><name>referer</name><value><string>${REFERER}</string></value></member>"
        [ -n "$OUTNAME" ] && OPTS="${OPTS}<member><name>out</name><value><string>${OUTNAME}</string></value></member>"
        if [ -n "$COOKIE" ]; then
          # Write cookie to temp file for this download
          CFILE="/tmp/aria2_cookie_$$.txt"
          echo "$COOKIE" > "$CFILE"
          OPTS="${OPTS}<member><name>load-cookies</name><value><string>${CFILE}</string></value></member>"
        fi

        if [ -n "$OPTS" ]; then
          xmlrpc aria2.addUri "<param><value><array><data><value><string>${URL}</string></value></data></array></value></param><param><value><struct>${OPTS}</struct></value></param>" > /dev/null
        else
          xmlrpc aria2.addUri "<param><value><array><data><value><string>${URL}</string></value></data></array></value></param>" > /dev/null
        fi
      fi
      ;;
    pause)
      GID=$(echo "$POST_DATA" | sed 's/.*gid=\([^&]*\).*/\1/')
      xmlrpc aria2.pause "$(strparam "$GID")" > /dev/null
      ;;
    unpause)
      GID=$(echo "$POST_DATA" | sed 's/.*gid=\([^&]*\).*/\1/')
      xmlrpc aria2.unpause "$(strparam "$GID")" > /dev/null
      ;;
    remove)
      GID=$(echo "$POST_DATA" | sed 's/.*gid=\([^&]*\).*/\1/')
      xmlrpc aria2.remove "$(strparam "$GID")" > /dev/null 2>&1
      xmlrpc aria2.removeDownloadResult "$(strparam "$GID")" > /dev/null 2>&1
      ;;
    purge)
      xmlrpc aria2.purgeDownloadResult > /dev/null
      ;;
  esac
fi

echo "Content-Type: text/html"
echo ""

# Get downloads
ACTIVE=$(xmlrpc aria2.tellActive)
WAITING=$(xmlrpc aria2.tellWaiting "$(strparam 0)" "$(strparam 20)")
STOPPED=$(xmlrpc aria2.tellStopped "$(strparam 0)" "$(strparam 20)")
GSTATS=$(xmlrpc aria2.getGlobalStat)

# Parse global stats
DL_SPEED=$(echo "$GSTATS" | sed -n 's/.*<name>downloadSpeed<\/name><value><string>\([^<]*\)<.*/\1/p')
UL_SPEED=$(echo "$GSTATS" | sed -n 's/.*<name>uploadSpeed<\/name><value><string>\([^<]*\)<.*/\1/p')
NUM_ACTIVE=$(echo "$GSTATS" | sed -n 's/.*<name>numActive<\/name><value><string>\([^<]*\)<.*/\1/p')

# Human-readable speed
human_speed() {
  local B=$1
  if [ "$B" -ge 1048576 ] 2>/dev/null; then echo "$(( B / 1048576 )).$(( B % 1048576 / 104858 )) MB/s"
  elif [ "$B" -ge 1024 ] 2>/dev/null; then echo "$(( B / 1024 )) KB/s"
  elif [ "$B" -gt 0 ] 2>/dev/null; then echo "${B} B/s"
  else echo "0 B/s"; fi
}

DL_H=$(human_speed "${DL_SPEED:-0}")
UL_H=$(human_speed "${UL_SPEED:-0}")

cat <<'HEADER'
<!DOCTYPE html><html><head><title>EtrayZ Downloads</title>
<style>
body{background:#0a0e17;color:#c5cdd9;margin:0;font-family:"Courier New",monospace;font-size:12px}
.header{background:#111827;border-bottom:1px solid #1e293b;padding:12px 20px;display:flex;align-items:center;justify-content:space-between}
.header a{color:#00ff88;text-decoration:none;font-size:13px}
.title{color:#fff;font-size:14px;font-weight:bold;letter-spacing:1px}
.stats{display:flex;gap:20px;font-size:12px}
.stat-dl{color:#00ff88}.stat-ul{color:#f0ad4e}
.add-form{background:#111827;border-bottom:1px solid #1e293b;padding:12px 20px}
.add-row{display:flex;gap:8px;margin-bottom:0}
.add-form input[type="text"],.add-form input[type="password"]{background:#0a0e17;border:1px solid #1e293b;color:#c5cdd9;padding:8px 12px;border-radius:4px;font-family:inherit;font-size:12px;box-sizing:border-box}
.add-form input[type="text"]:focus,.add-form input[type="password"]:focus{border-color:#00ff88;outline:none}
.add-row input[type="text"]{flex:1}
.btn{background:#111827;border:1px solid #1e293b;color:#00ff88;padding:8px 16px;border-radius:4px;cursor:pointer;font-family:inherit;font-size:12px;transition:all .2s}
.btn:hover{border-color:#00ff88;background:#0f1a2b}
.btn-sm{padding:4px 8px;font-size:10px}
.btn-danger{color:#ff4444;border-color:#ff4444}.btn-danger:hover{background:#1a0000}
.btn-toggle{color:#5a6a7a;font-size:11px;padding:4px 0;background:none;border:none;cursor:pointer;text-decoration:underline}
.btn-toggle:hover{color:#00ff88}
.auth-panel{display:none;margin-top:10px;padding:10px;background:#0d1220;border:1px solid #1e293b;border-radius:4px}
.auth-panel.show{display:block}
.auth-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px}
.auth-grid label{color:#5a6a7a;font-size:10px;text-transform:uppercase;letter-spacing:.5px;margin-bottom:2px;display:block}
.auth-grid input{width:100%}
.auth-full{margin-bottom:8px}
.auth-full label{color:#5a6a7a;font-size:10px;text-transform:uppercase;letter-spacing:.5px;margin-bottom:2px;display:block}
.auth-full input,.auth-full textarea{width:100%;box-sizing:border-box;background:#0a0e17;border:1px solid #1e293b;color:#c5cdd9;padding:8px 12px;border-radius:4px;font-family:inherit;font-size:12px}
.auth-full textarea{height:60px;resize:vertical}
.auth-full input:focus,.auth-full textarea:focus{border-color:#00ff88;outline:none}
.presets{margin-bottom:10px;display:flex;gap:6px;flex-wrap:wrap}
.preset-btn{background:#0a0e17;border:1px solid #1e293b;color:#5a6a7a;padding:3px 8px;border-radius:3px;cursor:pointer;font-size:10px;font-family:inherit}
.preset-btn:hover{border-color:#00ff88;color:#00ff88}
.section-title{padding:12px 20px 6px;color:#5a6a7a;font-size:11px;text-transform:uppercase;letter-spacing:1px}
.downloads{padding:0 20px}
.dl-item{background:#111827;border:1px solid #1e293b;border-radius:6px;padding:12px;margin-bottom:8px}
.dl-name{color:#fff;font-size:12px;word-break:break-all;margin-bottom:6px}
.dl-info{display:flex;gap:12px;font-size:11px;color:#5a6a7a;margin-bottom:6px;flex-wrap:wrap}
.dl-info span{white-space:nowrap}
.dl-bar{background:#0a0e17;border:1px solid #1e293b;border-radius:3px;height:8px;overflow:hidden}
.dl-fill{height:100%;background:linear-gradient(90deg,#00ff88,#00cc6a);border-radius:2px;transition:width .5s}
.dl-fill.paused{background:linear-gradient(90deg,#f0ad4e,#e09a3e)}
.dl-fill.error{background:linear-gradient(90deg,#ff4444,#cc3333)}
.dl-actions{margin-top:8px;display:flex;gap:6px}
.empty{text-align:center;padding:40px;color:#2a3a4a}
.footer{text-align:center;padding:12px;color:#2a3a4a;font-size:10px;border-top:1px solid #1e293b;margin-top:20px}
</style></head><body>
HEADER

cat <<STATSBAR
<div class="header">
  <span class="title">&#x21E9; Downloads</span>
  <div class="stats">
    <span class="stat-dl">&#x25BC; ${DL_H}</span>
    <span class="stat-ul">&#x25B2; ${UL_H}</span>
    <span>Active: ${NUM_ACTIVE:-0}</span>
  </div>
  <a href="/">&#x25C0; Dashboard</a>
</div>
<form class="add-form" method="POST">
  <input type="hidden" name="action" value="add">
  <div class="add-row">
    <input type="text" name="url" placeholder="Paste URL, magnet link, or torrent URL..." id="url-input">
    <button class="btn" type="submit">+ Add</button>
  </div>
  <button type="button" class="btn-toggle" onclick="toggleAuth()">&#x25BC; Authentication &amp; options</button>
  <div class="auth-panel" id="auth-panel">
    <div style="margin-bottom:10px;display:flex;gap:8px;align-items:center">
      <label style="color:#5a6a7a;font-size:10px;text-transform:uppercase;letter-spacing:.5px;white-space:nowrap">Account:</label>
      <select id="acct-select" onchange="applyAccount()" style="flex:1;background:#0a0e17;border:1px solid #1e293b;color:#c5cdd9;padding:6px 10px;border-radius:4px;font-family:inherit;font-size:12px">
        <option value="">-- No account (manual) --</option>
STATSBAR

# Load saved accounts and generate <option> + JS data
ACCT_DIR="/etc/etrayz/aria2-accounts"
ACCT_JS="var savedAccounts={"
ACCT_IDX=0
if [ -d "$ACCT_DIR" ]; then
  for f in "$ACCT_DIR"/*.conf; do
    [ -f "$f" ] || continue
    SVC=""; USR=""; PASS=""; REF=""
    . "$f"
    FNAME=$(basename "$f" .conf)
    COOK=""
    [ -f "$ACCT_DIR/${FNAME}.cookies" ] && COOK=$(cat "$ACCT_DIR/${FNAME}.cookies" 2>/dev/null | sed 's/\\/\\\\/g;s/"/\\"/g' | tr '\n' '\\' | sed 's/\\/\\n/g')
    echo "        <option value=\"acct_${ACCT_IDX}\">$SVC</option>"
    [ "$ACCT_IDX" -gt 0 ] && ACCT_JS="${ACCT_JS},"
    ACCT_JS="${ACCT_JS}\"acct_${ACCT_IDX}\":{\"user\":\"${USR}\",\"pass\":\"${PASS}\",\"ref\":\"${REF}\",\"cookies\":\"${COOK}\"}"
    ACCT_IDX=$((ACCT_IDX + 1))
  done
fi
ACCT_JS="${ACCT_JS}};"

cat <<'FORMREST'
      </select>
      <a href="/settings.html#sec-aria2" style="color:#5a6a7a;font-size:10px;text-decoration:underline" title="Manage accounts in Settings">manage</a>
    </div>
    <div class="auth-grid">
      <div>
        <label>HTTP / FTP Username</label>
        <input type="text" name="http_user" id="f-user" placeholder="username">
      </div>
      <div>
        <label>HTTP / FTP Password</label>
        <input type="password" name="http_pass" id="f-pass" placeholder="password">
      </div>
    </div>
    <div class="auth-full">
      <label>Referer URL <span style="color:#2a3a4a">(some hosters check this)</span></label>
      <input type="text" name="referer" id="f-ref" placeholder="https://example.com/download-page">
    </div>
    <div class="auth-full">
      <label>Output filename <span style="color:#2a3a4a">(optional, override server filename)</span></label>
      <input type="text" name="outname" id="f-out" placeholder="myfile.zip">
    </div>
    <div class="auth-full">
      <label>Cookies <span style="color:#2a3a4a">(Netscape format — export from browser after login)</span></label>
      <textarea name="cookie" id="f-cookie" placeholder="# Netscape HTTP Cookie File
.example.com	TRUE	/	FALSE	0	session_id	abc123
.example.com	TRUE	/	FALSE	0	auth_token	xyz789"></textarea>
    </div>
  </div>
</form>
FORMREST

cat <<ACCTDATA
<script>
${ACCT_JS}
ACCTDATA

cat <<'SCRIPT'
function toggleAuth(){
  var p=document.getElementById('auth-panel');
  p.className=p.className.indexOf('show')>=0?'auth-panel':'auth-panel show';
}
function applyAccount(){
  var sel=document.getElementById('acct-select').value;
  var u=document.getElementById('f-user'),p=document.getElementById('f-pass'),
      r=document.getElementById('f-ref'),c=document.getElementById('f-cookie');
  if(!sel || !savedAccounts[sel]){
    u.value='';p.value='';r.value='';c.value='';return;
  }
  var a=savedAccounts[sel];
  u.value=a.user||'';p.value=a.pass||'';r.value=a.ref||'';
  c.value=(a.cookies||'').replace(/\\n/g,'\n');
}
</script>
SCRIPT

# Parse download items from XML-RPC response
parse_downloads() {
  local XML="$1"
  local LABEL="$2"
  local ITEMS=$(echo "$XML" | sed 's/<\/struct>/\n/g' | grep '<name>gid<' )
  if [ -z "$ITEMS" ]; then return; fi

  echo "<div class='section-title'>${LABEL}</div><div class='downloads'>"

  echo "$XML" | awk '
  BEGIN { RS="</struct>"; FS="\n" }
  /<name>gid</ {
    gid=""; fname=""; status=""; total=0; completed=0; dlspeed=0; ulspeed=0
    n = split($0, lines, "<member>")
    for(i=1; i<=n; i++) {
      if(lines[i] ~ /<name>gid</) { gsub(/.*<string>/, "", lines[i]); gsub(/<.*/, "", lines[i]); gid=lines[i] }
      if(lines[i] ~ /<name>status</) { gsub(/.*<string>/, "", lines[i]); gsub(/<.*/, "", lines[i]); status=lines[i] }
      if(lines[i] ~ /<name>totalLength</) { gsub(/.*<string>/, "", lines[i]); gsub(/<.*/, "", lines[i]); total=lines[i]+0 }
      if(lines[i] ~ /<name>completedLength</) { gsub(/.*<string>/, "", lines[i]); gsub(/<.*/, "", lines[i]); completed=lines[i]+0 }
      if(lines[i] ~ /<name>downloadSpeed</) { gsub(/.*<string>/, "", lines[i]); gsub(/<.*/, "", lines[i]); dlspeed=lines[i]+0 }
      if(lines[i] ~ /<name>uploadSpeed</) { gsub(/.*<string>/, "", lines[i]); gsub(/<.*/, "", lines[i]); ulspeed=lines[i]+0 }
      # Get path from first file
      if(lines[i] ~ /<name>path</ && fname=="") { gsub(/.*<string>/, "", lines[i]); gsub(/<.*/, "", lines[i]); fname=lines[i] }
      if(lines[i] ~ /<name>uris</ && fname=="") {
        uri_part = lines[i]
        if(uri_part ~ /<name>uri</) { gsub(/.*<name>uri<\/name><value><string>/, "", uri_part); gsub(/<.*/, "", uri_part); fname=uri_part }
      }
    }
    if(gid == "") next

    # Basename
    n2 = split(fname, parts, "/"); bname = parts[n2]
    if(bname == "") bname = fname
    if(bname == "") bname = gid

    # Progress
    pct = 0; if(total > 0) pct = int(completed * 100 / total)
    # Size
    if(total > 1073741824) size = int(total/1073741824) "." int((total%1073741824)/107374183) " GB"
    else if(total > 1048576) size = int(total/1048576) " MB"
    else if(total > 1024) size = int(total/1024) " KB"
    else if(total > 0) size = total " B"
    else size = "?"

    # Speed
    if(dlspeed > 1048576) dls = int(dlspeed/1048576) " MB/s"
    else if(dlspeed > 1024) dls = int(dlspeed/1024) " KB/s"
    else if(dlspeed > 0) dls = dlspeed " B/s"
    else dls = ""

    fillclass = "dl-fill"
    if(status == "paused") fillclass = "dl-fill paused"
    if(status == "error") fillclass = "dl-fill error"

    print "<div class=\"dl-item\">"
    print "<div class=\"dl-name\">" bname "</div>"
    print "<div class=\"dl-info\"><span>" size "</span><span>" pct "%</span>"
    if(dls != "") print "<span>" dls "</span>"
    print "<span>" status "</span></div>"
    print "<div class=\"dl-bar\"><div class=\"" fillclass "\" style=\"width:" pct "%\"></div></div>"
    print "<div class=\"dl-actions\">"
    if(status == "active") print "<form method=\"POST\" style=\"display:inline\"><input type=\"hidden\" name=\"action\" value=\"pause\"><input type=\"hidden\" name=\"gid\" value=\"" gid "\"><button class=\"btn btn-sm\">Pause</button></form>"
    if(status == "paused") print "<form method=\"POST\" style=\"display:inline\"><input type=\"hidden\" name=\"action\" value=\"unpause\"><input type=\"hidden\" name=\"gid\" value=\"" gid "\"><button class=\"btn btn-sm\">Resume</button></form>"
    print "<form method=\"POST\" style=\"display:inline\"><input type=\"hidden\" name=\"action\" value=\"remove\"><input type=\"hidden\" name=\"gid\" value=\"" gid "\"><button class=\"btn btn-sm btn-danger\">Remove</button></form>"
    print "</div></div>"
  }'
  echo "</div>"
}

parse_downloads "$ACTIVE" "Active Downloads"
parse_downloads "$WAITING" "Queued"
parse_downloads "$STOPPED" "Completed / Stopped"

# Show empty state if no downloads
TOTAL=$(echo "${ACTIVE}${WAITING}${STOPPED}" | grep -c '<name>gid<')
if [ "$TOTAL" -eq 0 ] 2>/dev/null; then
  echo '<div class="empty">No downloads. Paste a URL above to start.</div>'
fi

cat <<'FOOTER'
<div style="text-align:center;padding:12px">
  <form method="POST" style="display:inline"><input type="hidden" name="action" value="purge"><button class="btn btn-sm">Clear Completed</button></form>
</div>
<div class="footer">aria2 Download Manager &middot; EtrayZ NAS</div>
<script>setTimeout(function(){var p=document.getElementById('auth-panel');if(!p||p.className.indexOf('show')<0)location.reload()},5000)</script>
</body></html>
FOOTER
