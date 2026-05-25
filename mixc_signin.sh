#!/usr/bin/env bash
set -euo pipefail

# Sensitive config captured from the working iOS H5 request.
MALL_NO="<YOURPARAM>"
IMEI="<YOURPARAM>"
DEVICE_PARAMS="<YOURPARAM>"
TOKEN="<YOURPARAM>"
PARAMS="<YOURPARAM>"
COOKIE="<YOURPARAM>"

# Non-sensitive constants
URL="https://app.mixcapp.com/mixc/gateway"
APP_ID="68a91a5bac6a4f3e91bf4b42856785c6"
PLATFORM="h5"
APP_VERSION="4.0.12"
OS_VERSION="16.6.1"
ACTION="mixc.app.memberSign.sign"
API_VERSION="1.0"
SIGN_SECRET="P@Gkbu0shTNHjhM!7F"
SWIMLANE="s1"
USER_AGENT="Mozilla/5.0 (iPhone; CPU iPhone OS 16_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 crland/4.4.0 grayscale/0 /MIXCAPP/4.0.12 AnalysysAgent/Hybrid"

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

read -r post_body referer < <(python3 - <<'PY' "$ACTION" "$API_VERSION" "$APP_ID" "$APP_VERSION" "$DEVICE_PARAMS" "$IMEI" "$MALL_NO" "$OS_VERSION" "$PARAMS" "$PLATFORM" "$TOKEN" "$SIGN_SECRET" "$SWIMLANE"
import hashlib
import sys
import time
import urllib.parse
from datetime import datetime

action, api_version, app_id, app_version, device_params, imei, mall_no, os_version, params, platform, token, secret, swimlane = sys.argv[1:]
now_ms = int(time.time() * 1000)
ts = str(now_ms)
t = str(now_ms + 25)
date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

# The working capture signs all form fields except sign, sorted by key, with URL-decoded values.
fields_for_sign = {
    "X-Mixc-Swimlane": swimlane,
    "action": action,
    "apiVersion": api_version,
    "appId": app_id,
    "appVersion": app_version,
    "date": date,
    "deviceParams": urllib.parse.unquote(device_params),
    "imei": imei,
    "mallNo": mall_no,
    "osVersion": os_version,
    "params": urllib.parse.unquote(params),
    "platform": platform,
    "t": t,
    "timestamp": ts,
    "token": token,
}
sign_src = "&".join(f"{key}={fields_for_sign[key]}" for key in sorted(fields_for_sign)) + f"&{secret}"
sign = hashlib.md5(sign_src.encode("utf-8")).hexdigest()

# Send the body like the captured request: deviceParams/params are already percent-encoded;
# do not pass them through curl --data-urlencode again or % becomes %25.
body_parts = [
    ("mallNo", mall_no),
    ("appId", app_id),
    ("platform", platform),
    ("imei", imei),
    ("appVersion", app_version),
    ("osVersion", os_version),
    ("action", action),
    ("apiVersion", api_version),
    ("timestamp", ts),
    ("deviceParams", device_params),
    ("X-Mixc-Swimlane", swimlane),
    ("t", t),
    ("date", urllib.parse.quote(date)),
    ("token", token),
    ("params", params),
    ("sign", sign),
]
post_body = "&".join(f"{key}={value}" for key, value in body_parts)
referer = f"https://app.mixcapp.com/m/m-{mall_no}/signIn?appVersion={app_version}&mallNo={mall_no}&timestamp={ts}&showWebNavigation=true&hideNativeNavigation=true"
print(post_body, referer)
PY
)

http_code="$({
  curl --location "$URL" \
    --header 'Host: app.mixcapp.com' \
    --header 'Accept: application/json, text/plain, */*' \
    --header 'Accept-Language: zh-CN,zh-Hans;q=0.9' \
    --header 'Origin: https://app.mixcapp.com' \
    --header "User-Agent: ${USER_AGENT}" \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --header 'Sec-Fetch-Site: same-origin' \
    --header 'Sec-Fetch-Mode: cors' \
    --header 'Sec-Fetch-Dest: empty' \
    --header "Referer: ${referer}" \
    --header "Cookie: ${COOKIE}" \
    --data-raw "${post_body}" \
    --compressed \
    --silent --show-error \
    --max-time 60 \
    --output "$body_file" \
    --write-out '%{http_code}'
} 2>&1)" || {
  echo "一点万象自动签到请求失败：${http_code}"
  exit 1
}

python3 - <<'PY' "$http_code" "$body_file"
import json
import pathlib
import sys

http_code, body_path = sys.argv[1:]
body = pathlib.Path(body_path).read_text(errors="replace")

try:
    data = json.loads(body)
except Exception:
    preview = body[:1000].replace("\n", " ")
    print(f"一点万象自动签到响应不是 JSON：HTTP {http_code}，body={preview}")
    sys.exit(1)

compact = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
if not str(http_code).startswith("2"):
    print(f"一点万象自动签到 HTTP {http_code}：{compact}")
    sys.exit(1)

if data.get("code") == 0 or data.get("success") is True:
    point = None
    try:
        point = data.get("data", {}).get("point")
    except Exception:
        pass
    suffix = f"，point={point}" if point is not None else ""
    print(f"一点万象自动签到成功{suffix}：{compact}")
    sys.exit(0)

message = str(data.get("message", ""))
if "已签到" in message or "不可重复签到" in message:
    print(f"一点万象今日已签到：{compact}")
    sys.exit(0)

if "请求频繁" in message:
    print(f"一点万象请求频繁，接口签名已通过但需稍后重试：{compact}")
    sys.exit(0)

print(f"一点万象自动签到失败：{compact}")
sys.exit(1)
PY
