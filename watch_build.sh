#!/usr/bin/env bash
# Poll CI ios-scanner → tải artifact IPA khi build xong.
set -uo pipefail

REPO="sontm8101982-coder/ios-scanner"
RUN_ID="44546308732"
T=$(cat /home/miso/gh_token.txt)
API="https://api.github.com/repos/$REPO"
OUT="/home/miso/projects/ios-scanner/dist"
mkdir -p "$OUT"

for i in $(seq 1 90); do          # 90 * 30s = 45 phút
  curl -s -H "Authorization: token $T" "$API/actions/runs/$RUN_ID" -o /tmp/scan_run.json
  STATUS=$(python3 -c "import json;print(json.load(open('/tmp/scan_run.json'))['status'])" 2>/dev/null)
  if [ "$STATUS" = "completed" ]; then break; fi
  sleep 30
done

CONCLUSION=$(python3 -c "import json;print(json.load(open('/tmp/scan_run.json')).get('conclusion'))")
echo "RUN $RUN_ID => $STATUS / $CONCLUSION"

if [ "$CONCLUSION" != "success" ]; then
  echo "--- log lỗi (bước fail) ---"
  curl -s -H "Authorization: token $T" "$API/actions/runs/$RUN_ID/jobs" -o /tmp/scan_jobs.json
  python3 - <<'PY'
import json
d = json.load(open('/tmp/scan_jobs.json'))
for job in d.get('jobs', []):
    print(f"JOB {job['name']}: {job['status']}/{job.get('conclusion')}")
    for step in job.get('steps', []):
        if step.get('conclusion') not in (None, 'success', 'skipped'):
            print(f"   FAIL STEP: {step['name']} -> {step.get('conclusion')}")
PY
  exit 1
fi

echo "--- tải artifact ---"
curl -s -H "Authorization: token $T" "$API/actions/runs/$RUN_ID/artifacts" -o /tmp/scan_arts.json
ART_ID=$(python3 -c "
import json
d = json.load(open('/tmp/scan_arts.json'))
arts = d.get('artifacts', [])
print(arts[0]['id'] if arts else '')
")
[ -z "$ART_ID" ] && { echo "KHÔNG có artifact"; exit 1; }

curl -sL -H "Authorization: token $T" "$API/actions/artifacts/$ART_ID/zip" -o "$OUT/ipa.zip"
cd "$OUT" && rm -rf Payload IOScanner.app && unzip -oq ipa.zip
echo "=== IPA sẵn sàng ==="
ls -la "$OUT"/*.ipa
ls -d "$OUT"/Payload/IOScanner.app
