"""Pair a device or revoke it. Admin credential stays in a hidden prompt."""
import argparse
import getpass
import json
import urllib.request
from urllib.parse import urlparse


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

opener = urllib.request.build_opener(NoRedirects)

parser = argparse.ArgumentParser()
parser.add_argument('endpoint')
parser.add_argument('--revoke', metavar='DEVICE_ID')
args = parser.parse_args()
url = urlparse(args.endpoint)
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
    parser.error('Use the HTTPS worker origin, without a path')
key = getpass.getpass('Admin key: ')
path = '/admin/revoke' if args.revoke else '/admin/invites'
request = urllib.request.Request(args.endpoint.rstrip('/') + path,
    data=json.dumps({'deviceID': args.revoke} if args.revoke else {}).encode(),
    headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'}, method='POST')
with opener.open(request, timeout=15) as response:
    result = json.load(response)
if args.revoke:
    print('Device revoked.')
else:
    print('Device pairing code (one use, expires in 20 minutes):')
    print(result['code'])
