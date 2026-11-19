#!/usr/bin/env bash
# Theo dõi build ios-scanner (matrix macos-26 / macos-15) → tải IPA của job xong trước.
set -uo pipefail

REPO="sontm8101982-coder/ios-scanner"
T=$(cat /home/miso/gh_token.txt)
API="https://api.github.com/repos/$REPO"
OUT="/home/miso/projects/ios-scanner/dist"
mkdir -p "$OUT"

latest_run() {
  curl -s -H "Authorization: token $T" "$API/actions/runs?per_page=10" -o /tmp/sw_runs.json
  python3 -c "
import json
d = json.load(open('/tmp/sw_runs.json'))
for r in d.get('workflow_runs', []):
    if r['path'].endswith('build.yml') and r['status'] in ('queued','in_progress'):
        print(r['id']); break
else:
    for r in d.get('workflow_runs', []):
        if r['path'].endswith('build.yml'):
            print(r['id']); break
"
}

RUN_ID=$(latest_run)
[ -z "$RUN_ID" ] && { echo "Không tìm thấy run build.yml nào"; exit 1; }
echo "RUN_ID=$RUN_ID"

for i in $(seq 1 120); do        # 120 * 30s = 60 phút
  curl -s -H "Authorization: token $T" "$API/actions/runs/$RUN_ID" -o /tmp/sw_run.json
  STATUS=$(python3 -c "import json;print(json.load(open('/tmp/sw_run.json'))['status'])" 2>/dev/null)
  [ "$STATUS" = "completed" ] && break
  sleep 30
done
CONCLUSION=$(python3 -c "import json;print(json.load(open('/tmp/sw_run.json')).get('conclusion'))")
echo "RUN $RUN_ID => $STATUS / $CONCLUSION"

curl -s -H "Authorization: token $T" "$API/actions/runs/$RUN_ID/jobs" -o /tmp/sw_jobs.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/sw_jobs.json'))
for job in d.get('jobs', []):
    print(f"JOB {job['name']}: {job['status']}/{job.get('conclusion')}")
    for step in job.get('steps', []):
        if step.get('conclusion') not in (None, 'success', 'skipped'):
            print(f"   FAIL STEP: {step['name']} -> {step.get('conclusion')}")
PY

curl -s -H "Authorization: token $T" "$API/actions/runs/$RUN_ID/artifacts" -o /tmp/sw_arts.json
ART_ID=$(python3 -c "
import json
d = json.load(open('/tmp/sw_arts.json'))
arts = [a for a in d.get('artifacts', []) if a['name'].startswith('IOScanner-unsigned')]
print(arts[0]['id'] if arts else '')
")
if [ -z "$ART_ID" ]; then
  echo "KHÔNG có artifact IPA. Tải build log về $OUT/build.log"
  LOG_ID=$(python3 -c "
import json
d = json.load(open('/tmp/sw_arts.json'))
arts = [a for a in d.get('artifacts', []) if a['name'].startswith('build-log')]
print(arts[0]['id'] if arts else '')
")
  if [ -n "$LOG_ID" ]; then
    curl -sL -H "Authorization: token $T" "$API/actions/artifacts/$LOG_ID/zip" -o "$OUT/buildlog.zip"
    cd "$OUT" && unzip -oq buildlog.zip && ls -la *.log 2>/dev/null | head -3
  fi
  exit 1
fi

curl -sL -H "Authorization: token $T" "$API/actions/artifacts/$ART_ID/zip" -o "$OUT/ipa.zip"
cd "$OUT" && rm -rf Payload && unzip -oq ipa.zip
echo "=== IPA sẵn sàng ==="
ls -la "$OUT"/*.ipa
echo "app: $OUT/Payload/IOScanner.app"
