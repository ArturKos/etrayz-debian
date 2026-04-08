#!/bin/sh
# CGI file manager — browse, download, upload, delete files
# Dark themed to match EtrayZ dashboard

# Base directory (jail — cannot escape above this)
BASEDIR="/home"

# Parse query string
DIR=""
ACTION=""
if [ -n "$QUERY_STRING" ]; then
  for param in $(echo "$QUERY_STRING" | tr '&' ' '); do
    key=$(echo "$param" | cut -d= -f1)
    val=$(echo "$param" | cut -d= -f2- | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf "%b" 2>/dev/null)
    case "$key" in
      dir) DIR="$val" ;;
      action) ACTION="$val" ;;
      file) FILE="$val" ;;
    esac
  done
fi

# Sanitize path — prevent directory traversal
DIR=$(echo "$DIR" | sed 's|\.\./||g; s|//|/|g; s|^/||')
FULLPATH="${BASEDIR}/${DIR}"
FULLPATH=$(echo "$FULLPATH" | sed 's|//|/|g; s|/$||')

# Ensure we stay within BASEDIR
REALPATH=$(readlink -f "$FULLPATH" 2>/dev/null || echo "$FULLPATH")
case "$REALPATH" in
  ${BASEDIR}*) ;;
  *) FULLPATH="$BASEDIR"; DIR="" ;;
esac

# Handle file download
if [ "$ACTION" = "download" ] && [ -n "$FILE" ]; then
  FILEPATH="${FULLPATH}/${FILE}"
  REALFILE=$(readlink -f "$FILEPATH" 2>/dev/null)
  case "$REALFILE" in ${BASEDIR}*)
    if [ -f "$REALFILE" ]; then
      FSIZE=$(stat -c%s "$REALFILE" 2>/dev/null || echo 0)
      echo "Content-Type: application/octet-stream"
      echo "Content-Disposition: attachment; filename=\"${FILE}\""
      echo "Content-Length: ${FSIZE}"
      echo ""
      cat "$REALFILE"
      exit 0
    fi
  ;; esac
fi

# Handle file/dir deletion
if [ "$ACTION" = "delete" ] && [ -n "$FILE" ]; then
  FILEPATH="${FULLPATH}/${FILE}"
  REALFILE=$(readlink -f "$FILEPATH" 2>/dev/null)
  case "$REALFILE" in ${BASEDIR}*)
    if [ -d "$REALFILE" ]; then
      rm -rf "$REALFILE" 2>/dev/null
    elif [ -f "$REALFILE" ]; then
      rm -f "$REALFILE" 2>/dev/null
    fi
  ;; esac
fi

# Handle mkdir
if [ "$ACTION" = "mkdir" ] && [ -n "$FILE" ]; then
  NEWDIR="${FULLPATH}/${FILE}"
  REALND=$(readlink -f "$(dirname "$NEWDIR")" 2>/dev/null)
  case "$REALND" in ${BASEDIR}*)
    mkdir -p "$NEWDIR" 2>/dev/null
  ;; esac
fi

# Handle file upload (multipart form data)
if [ "$REQUEST_METHOD" = "POST" ] && [ -n "$CONTENT_TYPE" ]; then
  case "$CONTENT_TYPE" in
    *multipart/form-data*)
      BOUNDARY=$(echo "$CONTENT_TYPE" | sed 's/.*boundary=//')
      TMPDIR=$(mktemp -d /tmp/upload.XXXXXX)
      cat > "${TMPDIR}/raw"
      # Extract filename and content
      FNAME=$(sed -n 's/.*filename="\([^"]*\)".*/\1/p' "${TMPDIR}/raw" | head -1)
      if [ -n "$FNAME" ]; then
        # Extract file content (between blank line after headers and boundary)
        sed -n '/^Content-Type/,/'"${BOUNDARY}"'/{/^Content-Type/d;/'"${BOUNDARY}"'/d;p}' "${TMPDIR}/raw" | sed '1d;$d' > "${FULLPATH}/${FNAME}"
      fi
      rm -rf "$TMPDIR"
      ;;
  esac
fi

echo "Content-Type: text/html"
echo ""

# Breadcrumb
CRUMBS="<a href='/cgi-bin/filemgr.sh'>/home</a>"
CRUMB_PATH=""
if [ -n "$DIR" ]; then
  OLD_IFS="$IFS"; IFS="/"; set -- $DIR; IFS="$OLD_IFS"
  for part; do
    [ -z "$part" ] && continue
    CRUMB_PATH="${CRUMB_PATH}/${part}"
    CRUMBS="${CRUMBS} / <a href='/cgi-bin/filemgr.sh?dir=$(echo "$CRUMB_PATH" | sed 's|^/||;s| |%20|g')'>${part}</a>"
  done
fi

cat <<'HEADER'
<!DOCTYPE html><html><head><title>EtrayZ Files</title>
<style>
body{background:#0a0e17;color:#c5cdd9;margin:0;font-family:"Courier New",monospace;font-size:12px}
.header{background:#111827;border-bottom:1px solid #1e293b;padding:12px 20px;display:flex;align-items:center;justify-content:space-between}
.header a{color:#00ff88;text-decoration:none;font-size:13px}
.title{color:#fff;font-size:14px;font-weight:bold;letter-spacing:1px}
.crumbs{padding:10px 20px;background:#0d1321;border-bottom:1px solid #1e293b;font-size:12px}
.crumbs a{color:#00ff88;text-decoration:none}.crumbs a:hover{text-decoration:underline}
.toolbar{padding:8px 20px;background:#111827;border-bottom:1px solid #1e293b;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.toolbar input[type="text"]{background:#0a0e17;border:1px solid #1e293b;color:#c5cdd9;padding:6px 10px;border-radius:4px;font-family:inherit;font-size:11px;width:150px}
.toolbar input[type="file"]{color:#5a6a7a;font-size:11px}
.btn{background:#111827;border:1px solid #1e293b;color:#00ff88;padding:6px 12px;border-radius:4px;cursor:pointer;font-family:inherit;font-size:11px;transition:all .2s;text-decoration:none;display:inline-block}
.btn:hover{border-color:#00ff88;background:#0f1a2b}
.btn-sm{padding:3px 8px;font-size:10px}
.btn-danger{color:#ff4444}.btn-danger:hover{border-color:#ff4444;background:#1a0000}
.filelist{padding:0 20px 20px}
table{width:100%;border-collapse:separate;border-spacing:0 2px}
th{text-align:left;color:#5a6a7a;padding:8px 12px;font-size:10px;text-transform:uppercase;letter-spacing:1px}
td{padding:8px 12px;background:#111827;font-size:12px}
tr:first-child td{border-radius:4px 4px 0 0}
tr:last-child td{border-radius:0 0 4px 4px}
td a{color:#c5cdd9;text-decoration:none}
td a:hover{color:#00ff88}
.icon{margin-right:8px;font-size:14px}
.dir .icon{color:#f0ad4e}
.file .icon{color:#5a6a7a}
.size{color:#5a6a7a;text-align:right}
.date{color:#5a6a7a}
.actions{text-align:right;white-space:nowrap}
.empty{text-align:center;padding:40px;color:#2a3a4a}
.footer{text-align:center;padding:12px;color:#2a3a4a;font-size:10px;border-top:1px solid #1e293b}
.disk-info{padding:6px 20px;font-size:11px;color:#5a6a7a;background:#0d1321;border-bottom:1px solid #1e293b}
</style></head><body>
HEADER

ENCDIR=$(echo "$DIR" | sed 's| |%20|g')

cat <<NAVHTML
<div class="header">
  <span class="title">&#x2750; File Manager</span>
  <a href="/">&#x25C0; Dashboard</a>
</div>
<div class="crumbs">${CRUMBS}</div>
<div class="toolbar">
  <form method="POST" enctype="multipart/form-data" style="display:flex;gap:8px;align-items:center">
    <input type="file" name="upload">
    <button class="btn btn-sm" type="submit">Upload</button>
  </form>
  <form method="GET" style="display:flex;gap:8px;align-items:center">
    <input type="hidden" name="dir" value="${DIR}">
    <input type="hidden" name="action" value="mkdir">
    <input type="text" name="file" placeholder="New folder name">
    <button class="btn btn-sm" type="submit">Create Folder</button>
  </form>
</div>
NAVHTML

# Disk usage info
DFINFO=$(df -h "$FULLPATH" 2>/dev/null | tail -1 | awk '{print $3 " / " $2 " (" $5 " used)"}')
echo "<div class='disk-info'>Disk: ${DFINFO}</div>"

echo '<div class="filelist"><table>'
echo '<tr><th></th><th>Name</th><th>Size</th><th>Modified</th><th></th></tr>'

# Parent dir link
if [ -n "$DIR" ]; then
  PARENT=$(dirname "$DIR")
  [ "$PARENT" = "." ] && PARENT=""
  ENCPARENT=$(echo "$PARENT" | sed 's| |%20|g')
  echo "<tr class='dir'><td class='icon'>&#x1F4C1;</td><td><a href='/cgi-bin/filemgr.sh?dir=${ENCPARENT}'>..</a></td><td></td><td></td><td></td></tr>"
fi

# List directories first, then files
if [ -d "$FULLPATH" ]; then
  # Directories
  ls -1 "$FULLPATH" 2>/dev/null | while read ITEM; do
    ITEMPATH="${FULLPATH}/${ITEM}"
    [ -d "$ITEMPATH" ] || continue
    ENCITEM=$(echo "${DIR}/${ITEM}" | sed 's|^/||;s| |%20|g')
    MTIME=$(stat -c '%y' "$ITEMPATH" 2>/dev/null | cut -d. -f1)
    echo "<tr class='dir'><td><span class='icon'>&#x1F4C1;</span></td>"
    echo "<td><a href='/cgi-bin/filemgr.sh?dir=${ENCITEM}'>${ITEM}</a></td>"
    echo "<td class='size'>--</td><td class='date'>${MTIME}</td>"
    echo "<td class='actions'><a class='btn btn-sm btn-danger' href='/cgi-bin/filemgr.sh?dir=${ENCDIR}&action=delete&file=$(echo "$ITEM" | sed 's| |%20|g')' onclick='return confirm(\"Delete ${ITEM}?\")'>Del</a></td></tr>"
  done
  # Files
  ls -1 "$FULLPATH" 2>/dev/null | while read ITEM; do
    ITEMPATH="${FULLPATH}/${ITEM}"
    [ -f "$ITEMPATH" ] || continue
    FSIZE=$(ls -lh "$ITEMPATH" 2>/dev/null | awk '{print $5}')
    MTIME=$(stat -c '%y' "$ITEMPATH" 2>/dev/null | cut -d. -f1)
    ENCFILE=$(echo "$ITEM" | sed 's| |%20|g')
    echo "<tr class='file'><td><span class='icon'>&#x1F4C4;</span></td>"
    echo "<td>${ITEM}</td>"
    echo "<td class='size'>${FSIZE}</td><td class='date'>${MTIME}</td>"
    echo "<td class='actions'><a class='btn btn-sm' href='/cgi-bin/filemgr.sh?dir=${ENCDIR}&action=download&file=${ENCFILE}'>DL</a> <a class='btn btn-sm btn-danger' href='/cgi-bin/filemgr.sh?dir=${ENCDIR}&action=delete&file=${ENCFILE}' onclick='return confirm(\"Delete ${ITEM}?\")'>Del</a></td></tr>"
  done
fi

echo '</table></div>'

# Count items
NFILES=$(ls -1 "$FULLPATH" 2>/dev/null | wc -l)
echo "<div class='footer'>${NFILES} items &middot; EtrayZ File Manager</div>"
echo '</body></html>'
