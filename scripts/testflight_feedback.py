"""Prints what testers sent through TestFlight (screenshot notes and crash notes) for a look without
App Store Connect. Tester names and emails are never printed. Run by .github/workflows/feedback.yml."""
import base64, io, json, os, sys, time, urllib.request, urllib.error

import jwt  # PyJWT

APP_ID = "6835495515"
BASE = "https://api.appstoreconnect.apple.com"


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})


def get(path):
    req = urllib.request.Request(path if path.startswith("http") else BASE + path, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        print("HTTP", e.code, path.split("?")[0], e.read().decode()[:600])
        return None


def picture(url, name):
    try:
        from PIL import Image
        data = urllib.request.urlopen(url, timeout=60).read()
        im = Image.open(io.BytesIO(data)).convert("RGB")
        im.thumbnail((700, 700))
        out = io.BytesIO()
        im.save(out, "JPEG", quality=60)
        b = base64.b64encode(out.getvalue()).decode()
        print("PICTURE-BEGIN " + name)
        for i in range(0, len(b), 4000):
            print("PICTURE " + b[i:i + 4000])
        print("PICTURE-END")
    except Exception as e:  # a picture that cannot be fetched must not hide the words
        print("picture not fetched:", type(e).__name__)


SAFE = ("comment", "createdDate", "deviceModel", "osVersion", "appPlatform", "buildBundleId", "locale", "timeZone",
        "architecture", "connectionType", "batteryPercentage", "screenWidthInPoints", "screenHeightInPoints",
        "appUptimeInMilliseconds", "diskBytesAvailable", "devicePlatform", "deviceFamily", "pairedAppleWatch")

for kind in ("betaFeedbackScreenshotSubmissions", "betaFeedbackCrashSubmissions"):
    page = get(f"/v1/apps/{APP_ID}/{kind}?limit=50&sort=-createdDate&include=build")
    n = 0
    while page:
        builds = {b["id"]: b.get("attributes", {}).get("version") for b in page.get("included", []) if b.get("type") == "builds"}
        for item in page.get("data", []):
            n += 1
            a = item.get("attributes", {})
            build = builds.get(((item.get("relationships", {}).get("build", {}) or {}).get("data") or {}).get("id"))
            print(f"FEEDBACK-BEGIN {kind} {n} build={build}")
            for k in SAFE:
                if a.get(k) not in (None, ""):
                    print(f"  {k}: {a[k]}")
            for i, shot in enumerate(a.get("screenshots") or []):
                if shot.get("url"):
                    picture(shot["url"], f"feedback-{kind[12:16]}-{n}-{i + 1}")
            print("FEEDBACK-END")
        nxt = (page.get("links") or {}).get("next")
        page = get(nxt) if nxt and n < 200 else None
    print(f"{kind}: {n} item(s)")
