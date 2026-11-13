#!/usr/bin/env python3
"""One-time, owner-approved cleanup. Delete only unchanged, reachable branch tips."""
import json
import os
import subprocess
import urllib.error
import urllib.parse
import urllib.request

repo = os.environ['GH_REPO']
assert repo == 'AaronJny/VoiceInk'
source = os.environ['GITHUB_SHA']
heads = {
    'ci/cloud-baseline': 'fb9e35b032cfac0553346de6ddefd8c3145552ac',
    'ci/import-upstream-v2.27': '98f828cfc0f26e7bab7ca74e448fccbf2fe975ba',
    'ci/package-dmg': '784f225195f5165c830d41dd343e7c3e0776d194',
    'ci/package-v2.27': '9055c81a15a9019959ea4fdb86c78e0973569cc8',
    'ci/release-v2.27': '4138bf73075566234e1992eae9c1f851324f0f91',
    'ci/signing-probe': 'ac3cd5623f1bc71e1f334bf47d03d5e0131f4faf',
    'upgrade/v2.27-cloud': 'f455c8d841b4f39c4923aaedcc6a806cea3b10d0',
    'vendor/upstream-v2.27': 'b5d1be9a7c7377dd059f37bb3e0f791b802d4001',
    'upgrade/autolearn-ollama-fix': '22804242519d50165deb8ea76506999984bd4f8c',
}
# Only this explicitly requested cleanup batch, not arbitrary future release branches.
if os.environ.get('GITHUB_REF_NAME') == 'release/v2.27-personal.2':
    heads['release/v2.27-personal.2'] = source

def api(path, method='GET'):
    request = urllib.request.Request('https://api.github.com/repos/' + repo + '/' + path,
        method=method, headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
            'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()
            return json.loads(data) if data else None
    except urllib.error.HTTPError as error:
        if error.code == 404 and method == 'GET':
            return None
        raise

main = api('git/ref/heads/main')
assert main is not None and main['object']['sha'] == source, 'Main moved; stop cleanup and review.'
for branch, expected in heads.items():
    ref = 'heads/' + urllib.parse.quote(branch, safe='/')
    current = api('git/ref/' + ref)
    if current is None:
        print(branch + ': already absent')
        continue
    if current['object']['sha'] != expected:
        print(branch + ': kept, head changed since audit')
        continue
    subprocess.run(['git', 'merge-base', '--is-ancestor', expected, source], check=True)
    api('git/refs/' + ref, method='DELETE')
    assert api('git/ref/' + ref) is None
    print(branch + ': deleted; commit retained in main history ' + expected)
