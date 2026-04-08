#!/bin/sh
# CGI photo gallery — browse and view images from /home/public/Pictures
# Dark themed, thumbnail grid with lightbox viewer

BASEDIR="/home/public/Pictures"
THUMBDIR="/var/lib/etrayz/thumbs"
mkdir -p "$THUMBDIR" 2>/dev/null

# Parse query string
DIR=""
IMG=""
if [ -n "$QUERY_STRING" ]; then
  for param in $(echo "$QUERY_STRING" | tr '&' ' '); do
    key=$(echo "$param" | cut -d= -f1)
    val=$(echo "$param" | cut -d= -f2- | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf "%b" 2>/dev/null)
    case "$key" in
      dir) DIR="$val" ;;
      img) IMG="$val" ;;
      thumb) THUMB="$val" ;;
    esac
  done
fi

# Sanitize
DIR=$(echo "$DIR" | sed 's|\.\./||g; s|//|/|g; s|^/||')
FULLPATH="${BASEDIR}/${DIR}"
FULLPATH=$(echo "$FULLPATH" | sed 's|//|/|g; s|/$||')
REALPATH=$(readlink -f "$FULLPATH" 2>/dev/null || echo "$FULLPATH")
case "$REALPATH" in ${BASEDIR}*) ;; *) FULLPATH="$BASEDIR"; DIR="" ;; esac

# Serve thumbnail
if [ -n "$THUMB" ]; then
  IMGPATH="${FULLPATH}/${THUMB}"
  REALIMG=$(readlink -f "$IMGPATH" 2>/dev/null)
  case "$REALIMG" in ${BASEDIR}*)
    if [ -f "$REALIMG" ]; then
      # Create hash for thumb filename
      HASH=$(echo "$REALIMG" | md5sum | cut -c1-16)
      THUMBFILE="${THUMBDIR}/${HASH}.jpg"
      # Generate thumbnail if missing or older than source
      if [ ! -f "$THUMBFILE" ] || [ "$REALIMG" -nt "$THUMBFILE" ]; then
        # Use djpeg+cjpeg for JPEG, or just serve original scaled via browser
        if command -v convert >/dev/null 2>&1; then
          convert "$REALIMG" -thumbnail 200x200 -quality 60 "$THUMBFILE" 2>/dev/null
        else
          # No ImageMagick — serve original with browser scaling
          echo "Content-Type: $(file -bi "$REALIMG" 2>/dev/null || echo 'image/jpeg')"
          echo ""
          cat "$REALIMG"
          exit 0
        fi
      fi
      if [ -f "$THUMBFILE" ]; then
        echo "Content-Type: image/jpeg"
        echo ""
        cat "$THUMBFILE"
        exit 0
      fi
    fi
  ;; esac
  echo "Status: 404"
  echo ""
  exit 0
fi

# Serve full image
if [ -n "$IMG" ]; then
  IMGPATH="${FULLPATH}/${IMG}"
  REALIMG=$(readlink -f "$IMGPATH" 2>/dev/null)
  case "$REALIMG" in ${BASEDIR}*)
    if [ -f "$REALIMG" ]; then
      MIME=$(file -bi "$REALIMG" 2>/dev/null | cut -d';' -f1)
      [ -z "$MIME" ] && MIME="image/jpeg"
      FSIZE=$(stat -c%s "$REALIMG" 2>/dev/null)
      echo "Content-Type: ${MIME}"
      echo "Content-Length: ${FSIZE}"
      echo ""
      cat "$REALIMG"
      exit 0
    fi
  ;; esac
  echo "Status: 404"
  echo ""
  exit 0
fi

echo "Content-Type: text/html"
echo ""

# Breadcrumbs
CRUMBS="<a href='/cgi-bin/gallery.sh'>Pictures</a>"
CRUMB_PATH=""
if [ -n "$DIR" ]; then
  OLD_IFS="$IFS"; IFS="/"; set -- $DIR; IFS="$OLD_IFS"
  for part; do
    [ -z "$part" ] && continue
    CRUMB_PATH="${CRUMB_PATH}/${part}"
    CRUMBS="${CRUMBS} / <a href='/cgi-bin/gallery.sh?dir=$(echo "$CRUMB_PATH" | sed 's|^/||;s| |%20|g')'>${part}</a>"
  done
fi

ENCDIR=$(echo "$DIR" | sed 's| |%20|g')

cat <<'HEADER'
<!DOCTYPE html><html><head><title>EtrayZ Gallery</title>
<style>
body{background:#0a0e17;color:#c5cdd9;margin:0;font-family:"Courier New",monospace;font-size:12px}
.header{background:#111827;border-bottom:1px solid #1e293b;padding:12px 20px;display:flex;align-items:center;justify-content:space-between}
.header a{color:#00ff88;text-decoration:none;font-size:13px}
.title{color:#fff;font-size:14px;font-weight:bold;letter-spacing:1px}
.crumbs{padding:10px 20px;background:#0d1321;border-bottom:1px solid #1e293b;font-size:12px}
.crumbs a{color:#00ff88;text-decoration:none}.crumbs a:hover{text-decoration:underline}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:12px;padding:20px}
.card{background:#111827;border:1px solid #1e293b;border-radius:8px;overflow:hidden;transition:all .2s;cursor:pointer}
.card:hover{border-color:#00ff88;transform:translateY(-2px)}
.card img{width:100%;height:140px;object-fit:cover;display:block;background:#0d1321}
.card-name{padding:8px;font-size:11px;color:#c5cdd9;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.folder{display:flex;align-items:center;justify-content:center;height:140px;font-size:48px;color:#f0ad4e;background:#0d1321}
.folder-name{color:#f0ad4e}
.empty{text-align:center;padding:60px;color:#2a3a4a;font-size:14px}
.footer{text-align:center;padding:12px;color:#2a3a4a;font-size:10px;border-top:1px solid #1e293b}
.count{padding:6px 20px;font-size:11px;color:#5a6a7a;background:#0d1321;border-bottom:1px solid #1e293b}
/* Lightbox */
.lb{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.95);z-index:100;align-items:center;justify-content:center;cursor:pointer}
.lb.active{display:flex}
.lb img{max-width:95%;max-height:90vh;object-fit:contain;border-radius:4px}
.lb-name{position:fixed;bottom:20px;left:0;width:100%;text-align:center;color:#5a6a7a;font-size:12px}
.lb-close{position:fixed;top:15px;right:20px;color:#5a6a7a;font-size:24px;cursor:pointer}
.lb-nav{position:fixed;top:50%;font-size:36px;color:#5a6a7a;cursor:pointer;padding:20px;user-select:none}
.lb-nav:hover{color:#00ff88}
.lb-prev{left:10px}.lb-next{right:10px}
</style></head><body>
HEADER

cat <<NAVHTML
<div class="header">
  <span class="title">&#x1F5BC; Photo Gallery</span>
  <a href="/">&#x25C0; Dashboard</a>
</div>
<div class="crumbs">${CRUMBS}</div>
NAVHTML

# Count items
NDIRS=0; NIMGS=0
if [ -d "$FULLPATH" ]; then
  for item in "$FULLPATH"/*/; do [ -d "$item" ] && NDIRS=$((NDIRS+1)); done
  for item in "$FULLPATH"/*; do
    [ -f "$item" ] || continue
    case "$(echo "$item" | tr 'A-Z' 'a-z')" in *.jpg|*.jpeg|*.png|*.gif|*.bmp|*.webp) NIMGS=$((NIMGS+1));; esac
  done
fi
echo "<div class='count'>${NDIRS} folders, ${NIMGS} images</div>"

echo '<div class="grid">'

# Show folders
if [ -d "$FULLPATH" ]; then
  ls -1 "$FULLPATH" 2>/dev/null | while read ITEM; do
    [ -d "${FULLPATH}/${ITEM}" ] || continue
    ENCITEM=$(echo "${DIR}/${ITEM}" | sed 's|^/||;s| |%20|g')
    echo "<a href='/cgi-bin/gallery.sh?dir=${ENCITEM}' style='text-decoration:none'><div class='card'><div class='folder'>&#x1F4C1;</div><div class='card-name folder-name'>${ITEM}</div></div></a>"
  done

  # Show images
  IDX=0
  ls -1 "$FULLPATH" 2>/dev/null | while read ITEM; do
    [ -f "${FULLPATH}/${ITEM}" ] || continue
    case "$(echo "$ITEM" | tr 'A-Z' 'a-z')" in
      *.jpg|*.jpeg|*.png|*.gif|*.bmp|*.webp) ;;
      *) continue ;;
    esac
    ENCFILE=$(echo "$ITEM" | sed 's| |%20|g')
    echo "<div class='card' onclick='openLb(${IDX})' data-img='/cgi-bin/gallery.sh?dir=${ENCDIR}&img=${ENCFILE}' data-name='${ITEM}'>"
    echo "<img src='/cgi-bin/gallery.sh?dir=${ENCDIR}&thumb=${ENCFILE}' loading='lazy' alt='${ITEM}'>"
    echo "<div class='card-name'>${ITEM}</div></div>"
    IDX=$((IDX+1))
  done
fi

echo '</div>'

if [ $NDIRS -eq 0 ] && [ $NIMGS -eq 0 ]; then
  echo "<div class='empty'>No images found.<br>Add photos to /home/public/Pictures via Samba or SCP.</div>"
fi

cat <<'FOOTER'
<div class="footer">EtrayZ Photo Gallery</div>
<div class="lb" id="lb" onclick="closeLb(event)">
  <span class="lb-close" onclick="closeLb()">&times;</span>
  <span class="lb-nav lb-prev" onclick="event.stopPropagation();navLb(-1)">&#x25C0;</span>
  <img id="lb-img" src="">
  <span class="lb-nav lb-next" onclick="event.stopPropagation();navLb(1)">&#x25B6;</span>
  <div class="lb-name" id="lb-name"></div>
</div>
<script>
var cards=document.querySelectorAll('.card[data-img]');
var cur=0;
function openLb(i){cur=i;var c=cards[i];document.getElementById('lb-img').src=c.getAttribute('data-img');document.getElementById('lb-name').textContent=c.getAttribute('data-name');document.getElementById('lb').className='lb active';}
function closeLb(e){if(e&&e.target.tagName==='IMG')return;document.getElementById('lb').className='lb';}
function navLb(d){cur=((cur+d)%cards.length+cards.length)%cards.length;openLb(cur);}
document.onkeydown=function(e){var lb=document.getElementById('lb');if(lb.className!=='lb active')return;if(e.keyCode===27)closeLb();if(e.keyCode===37)navLb(-1);if(e.keyCode===39)navLb(1);};
</script>
</body></html>
FOOTER
