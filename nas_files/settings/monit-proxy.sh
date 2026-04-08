#!/bin/sh
# CGI proxy for monit web UI — injects dark theme CSS
# Fetches from localhost:2812 and reskins to match dashboard

MONIT_PATH=""
if [ -n "$QUERY_STRING" ]; then
  MONIT_PATH="$QUERY_STRING"
fi

PAGE=$(wget -q -O - "http://localhost:2812/${MONIT_PATH}" 2>/dev/null)

if [ -z "$PAGE" ]; then
  echo "Content-Type: text/html"
  echo ""
  echo "<html><body style='background:#0a0e17;color:#c5cdd9;font-family:monospace;display:flex;align-items:center;justify-content:center;height:100vh'>"
  echo "<div>Monit is not running</div></body></html>"
  exit 0
fi

echo "Content-Type: text/html"
echo ""

# Write dark CSS injection
cat <<'CSSEOF'
<!DOCTYPE html><html><head><title>EtrayZ Monit</title>
<style>
body{background:#0a0e17!important;color:#c5cdd9!important;margin:0!important;font-family:"Courier New",monospace!important}
body,p,div,td,th,tr,form,ol,ul,li,input,textarea,select,a,h2,h3,b,small,font,i{font-family:"Courier New",monospace!important;color:#c5cdd9!important}
a{color:#00ff88!important;text-decoration:none!important}
a:hover{text-decoration:underline!important}
small a{color:#5a6a7a!important}
h2,h3,h2 b,h3 b{color:#fff!important}
tr[bgcolor="#6F6F6F"] td,tr[bgcolor="#6F6F6F"]{background:#1e293b!important}
tr[bgcolor="#DDDDDD"] td,tr[bgcolor="#DDDDDD"],td[bgcolor="#DDDDDD"]{background:#111827!important}
td[bgcolor="#DDDDDD"] a,td[bgcolor="#DDDDDD"] small,td[bgcolor="#DDDDDD"] font{color:#5a6a7a!important}
tr[bgcolor="#BBDDFF"] td,tr[bgcolor="#BBDDFF"],td[bgcolor="#EFF7FF"]{background:#0a0e17!important}
tr[bgcolor="#EFEFEF"] td,tr[bgcolor="#EFEFEF"]{background:#111827!important}
tr td{background:#0d1321!important}
table{border-collapse:separate!important;border-spacing:0 2px!important}
td{padding:8px 12px!important;border:none!important}
font[color="#00ff00"]{color:#00ff88!important}
font[color="#ff8800"]{color:#f0ad4e!important}
font[color="#ff0000"]{color:#ff4444!important}
.foot,.foot a{color:#2a3a4a!important}
center>table{max-width:900px;margin:0 auto}
input[type="submit"],input[type="button"]{background:#111827!important;color:#00ff88!important;border:1px solid #1e293b!important;padding:8px 16px!important;cursor:pointer!important;border-radius:4px!important;font-family:"Courier New",monospace!important}
input[type="submit"]:hover,input[type="button"]:hover{border-color:#00ff88!important;background:#0f1a2b!important}
img[width="1"]{display:none!important}
body[bgcolor]{background:#0a0e17!important}
</style></head><body>
CSSEOF

# Extract body content and rewrite links
echo "$PAGE" | sed \
  -e "s|.*<body[^>]*>||" \
  -e "s|</body>.*||" \
  -e "s|href='\([a-zA-Z_][a-zA-Z0-9_]*\)'|href='/cgi-bin/monit-proxy.sh?\1'|g" \
  -e "s|href=\"\([a-zA-Z_][a-zA-Z0-9_]*\)\"|href=\"/cgi-bin/monit-proxy.sh?\1\"|g" \
  -e "s|action='\([a-zA-Z_][a-zA-Z0-9_]*\)'|action='/cgi-bin/monit-proxy.sh?\1'|g" \
  -e "s|href='/cgi-bin/monit-proxy.sh?http|href='http|g" \
  -e "s|CONTENT=60|CONTENT=0|" \
  -e "s|href='\.'|href='/cgi-bin/monit-proxy.sh'|g" \
  -e "s|src=\"_pixel\"|src=\"\"|g" \
  -e "s|src='_pixel'|src=''|g"

echo '<div style="text-align:center;margin:20px"><a href="/cgi-bin/monit-logs.sh" style="color:#00ff88;font-size:13px;text-decoration:none;border:1px solid #1e293b;padding:8px 16px;border-radius:4px;background:#111827">&#x2630; System Logs</a> <a href="/" style="color:#5a6a7a;font-size:13px;text-decoration:none;border:1px solid #1e293b;padding:8px 16px;border-radius:4px;background:#111827">&#x25C0; Dashboard</a></div>'
echo "<script>setTimeout(function(){location.reload()},60000)</script>"
echo "</body></html>"
