#!/usr/bin/env bash
# Tự động retry build iOS trên GitHub Actions khi runner macOS arm64 thiếu capacity
# ("The job was not acquired by Runner of type hosted even after multiple attempts").
# Chạy: ./ci_retry.sh [số_attempt]
set -uo pipefail

REPO="sontm8101982-coder/ios-scanner"
T=$(cat /home/miso/gh_token.txt)
API="https://api.github.com/repos/$REPO"
OUT="/home/miso/projects/ios-scanner/dist"
MAX_ATTEMPTS="${1:-10}"
mkdir -p "$OUT"

log() { echo "[$(date +%H:%M:%S)] $*"; }

run_id() {
  curl -s -H "Authorization: token $T" "$API/actions/runs?per_page=20" -o /tmp/cr_runs.json
  python3 -c "
import json
d = json.load(open('/tmp/cr_runs.json'))
rs = [r for r in d.get('workflow_runs', []) if r['path'].endswith('build.yml')]
print(rs[0]['id'] if rs else '')
"
}

run_field() {   # $1=run_id  $2=status|conclusion
  curl -s -H "Authorization: token $T" "$API/actions/runs/$1" -o /tmp/cr_run.json
  python3 -c "
import json,sys
d = json.load(open('/tmp/cr_run.json'))
print(d.get('$2') or '')
"
}

download() {    # $1=run_id
  curl -s -H "Authorization: token $T" "$API/actions/runs/$1/artifacts" -o /tmp/cr_arts.json
  ART=$(python3 -c "
import json
d = json.load(open('/tmp/cr_arts.json'))
a = [x for x in d.get('artifacts', []) if x['name'].startswith('IOScanner-unsigned')]
print(a[0]['id'] if a else '')
")
  [ -z "$ART" ] && { log "không có artifact IPA"; return 1; }
  curl -sL -H "Authorization: token $T" "$API/actions/artifacts/$ART/zip" -o "$OUT/ipa.zip"
  cd "$OUT" && rm -rf Payload && unzip -oq ipa.zip
  log "IPA: $(ls -la "$OUT"/*.ipa 2>/dev/null | head -1)"
  return 0
}

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  RID=$(run_id)
  [ -z "$RID" ] && { log "không thấy run nào của build.yml"; exit 1; }
  log "attempt $attempt/$MAX_ATTEMPTS — run $RID"

  # chờ run kết thúc (tối đa 35 phút cho 1 lượt)
  for _ in $(seq 1 70); do
    ST=$(run_field "$RID" status)
    [ "$ST" = "completed" ] && break
    sleep 30
  done
  CONCL=$(run_field "$RID" conclusion)
  log "run $RID -> $ST / $CONCL"

  if [ "$CONCL" = "success" ]; then
    if download "$RID"; then
      log "XONG — IPA đã sẵn sàng"
      exit 0
    fi
    log "run success nhưng tải artifact lỗi"
    exit 1
  fi

  # thất bại: thử rerun (ưu tiên rerun job fail; fallback rerun cả run)
  log "rerun run $RID…"
  CODE=$(curl -s -o /tmp/cr_rerun.json -w "%{http_code}" -X POST \
    -H "Authorization: token $T" -H "Accept: application/vnd.github+json" \
    "$API/actions/runs/$RID/rerun-failed-jobs")
  if [ "$CODE" != "201" ]; then
    CODE=$(curl -s -o /tmp/cr_rerun.json -w "%{http_code}" -X POST \
      -H "Authorization: token $T" -H "Accept: application/vnd.github+json" \
      "$API/actions/runs/$RID/rerun")
  fi
  log "rerun http=$CODE"
  if [ "$CODE" != "201" ]; then
    log "không rerun được (http=$CODE) — nghỉ 5 phút rồi tạo run mới bằng dispatch"
    sleep 300
    curl -s -X POST -H "Authorization: token $T" -H "Accept: application/vnd.github+json" \
      "$API/actions/workflows/423956110/dispatches" -d '{"ref":"main"}' -o /dev/null -w "dispatch=%{http_code}\n"
  fi
  sleep 120          # nghỉ trước lượt kế tiếp để capacity hồi
done

log "hết $MAX_ATTEMPTS lượt mà vẫn không lấy được runner macOS"
exit 1
