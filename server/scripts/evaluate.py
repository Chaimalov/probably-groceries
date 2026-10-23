"""Evaluate the deployed service against the small Hebrew acceptance corpus.

This makes paid provider calls using a device token entered at a hidden prompt.
It does not read or upload the user's shopping history.
"""
import argparse
import getpass
import json
from pathlib import Path
import urllib.request
from urllib.parse import urlparse
import uuid


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

opener = urllib.request.build_opener(NoRedirects)

parser = argparse.ArgumentParser()
parser.add_argument('endpoint')
args = parser.parse_args()
origin = urlparse(args.endpoint)
if origin.scheme != 'https' or not origin.hostname or origin.username or origin.password or origin.query or origin.fragment or origin.path not in ('', '/'):
    parser.error('Use the HTTPS worker origin')
token = getpass.getpass('Enrolled device token: ')
cases = json.loads((Path(__file__).parent.parent / 'test/identity-corpus.json').read_text())
results = []
for case in cases:
    source, target = str(uuid.uuid4()), str(uuid.uuid4())
    payload = {'source': {'id': source, 'name': case['source']},
        'candidates': [{'id': target, 'name': case['target']}]}
    request = urllib.request.Request(args.endpoint.rstrip('/') + '/v1/match',
        data=json.dumps(payload).encode(), method='POST',
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
    with opener.open(request, timeout=20) as response:
        result = json.load(response)
    accepted = result['decision'] == 'same'
    passed = accepted == case['same']
    results.append({**case, 'passed': passed, 'result': result})
    print(('PASS' if passed else 'FAIL'), case['source'], '/', case['target'], result['decision'])
Path('evaluation-results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
