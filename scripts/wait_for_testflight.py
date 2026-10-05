"""Wait for Apple's processing and internal TestFlight availability.
Credentials stay on the runner; only build state is logged.
"""
import base64
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.chaimalov.probablygroceries"


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def raw_signature(der):
    # P-256 signatures are short DER SEQUENCEs containing two INTEGERs.
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2:
        raise ValueError("Invalid ES256 signature")
    position = 2
    parts = []
    for _ in range(2):
        if der[position] != 0x02:
            raise ValueError("Invalid ES256 signature integer")
        length = der[position + 1]
        position += 2
        value = int.from_bytes(der[position:position + length], "big")
        parts.append(value.to_bytes(32, "big"))
        position += length
    if position != len(der):
        raise ValueError("Invalid ES256 signature length")
    return b"".join(parts)


def token():
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["APPLE_KEY_ID"], "typ": "JWT"}
    payload = {"iss": os.environ["APPLE_ISSUER_ID"], "iat": now - 5,
               "exp": now + 600, "aud": "appstoreconnect-v1"}
    encoded = ".".join(b64(json.dumps(x, separators=(",", ":")).encode()) for x in (header, payload))
    key_path = Path(os.environ["RUNNER_TEMP"]) / "AuthKey.p8"
    signature = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key_path)],
                               input=encoded.encode(), capture_output=True, check=True).stdout
    return encoded + "." + b64(raw_signature(signature))


def get(path, query=None):
    url = API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, headers={"Authorization": "Bearer " + token()})
    with urllib.request.urlopen(request, timeout=45) as response:
        return json.load(response)


def main():
    version = os.environ["GITHUB_RUN_NUMBER"]
    deadline = time.monotonic() + 900
    app_id = None
    last_state = None
    while time.monotonic() < deadline:
        try:
            if app_id is None:
                apps = get("/v1/apps", {"filter[bundleId]": BUNDLE_ID})["data"]
                if len(apps) != 1:
                    raise RuntimeError("Could not resolve the app by bundle identifier")
                app_id = apps[0]["id"]
            result = get("/v1/builds", {"filter[app]": app_id, "filter[version]": version,
                                       "include": "buildBetaDetail", "limit": "10"})
            builds = result["data"]
            if len(builds) > 1:
                raise RuntimeError("Build number is ambiguous")
            if builds:
                build = builds[0]
                state = build["attributes"]["processingState"]
                details = next((x["attributes"] for x in result.get("included", [])
                                if x["type"] == "buildBetaDetails"), {})
                internal = details.get("internalBuildState", "UNKNOWN")
                current = (state, internal)
                if current != last_state:
                    print(f"Build {version}: processing={state}, internal={internal}", flush=True)
                    last_state = current
                if state in ("FAILED", "INVALID"):
                    raise RuntimeError("Apple rejected build processing")
                if state == "VALID" and internal == "IN_BETA_TESTING":
                    summary = f"Build {version} is processed and available to existing internal TestFlight testers.\n"
                    print(summary, flush=True)
                    if os.environ.get("GITHUB_STEP_SUMMARY"):
                        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as file:
                            file.write(summary)
                    return
            elif last_state != "missing":
                print(f"Waiting for uploaded build {version} to appear in App Store Connect.", flush=True)
                last_state = "missing"
        except urllib.error.HTTPError as error:
            # Don't emit request headers, tokens or raw account responses.
            if error.code not in (404, 429, 500, 502, 503, 504):
                raise RuntimeError(f"App Store Connect status request failed: HTTP {error.code}") from None
            print(f"Apple status endpoint temporarily unavailable: HTTP {error.code}", flush=True)
        except (urllib.error.URLError, TimeoutError):
            print("Apple status request timed out; retrying.", flush=True)
        time.sleep(20)
    raise RuntimeError(f"Build {version} uploaded but not confirmed installable within 15 minutes; latest state={last_state}")


if __name__ == "__main__":
    main()
