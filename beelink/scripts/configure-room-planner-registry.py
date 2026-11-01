#!/usr/bin/env python3
"""Verify a GHCR pull credential and save only its SOPS-encrypted Secret."""
import argparse
import base64
import getpass
import json
from pathlib import Path
import subprocess
import urllib.error
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--username', default='breuerfelix')
    parser.add_argument('--token-file', type=Path, help='Existing local token file; token never appears in arguments')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    source = json.loads((root / 'beelink/images/room-planner/source.json').read_text())
    token = args.token_file.read_text().strip() if args.token_file else getpass.getpass('GHCR read:packages token: ').strip()
    if not token:
        raise SystemExit('Empty credential; no changes made.')
    auth = base64.b64encode(f'{args.username}:{token}'.encode()).decode()
    query = urllib.parse.urlencode({'service': 'ghcr.io', 'scope': 'repository:breuerfelix/screeps-room-planner:pull'})
    request = urllib.request.Request('https://ghcr.io/token?' + query, headers={'Authorization': 'Basic ' + auth})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            bearer = json.load(response)['token']
        digest = source['image'].split('@', 1)[1]
        request = urllib.request.Request(
            'https://ghcr.io/v2/breuerfelix/screeps-room-planner/manifests/' + digest,
            headers={'Authorization': 'Bearer ' + bearer, 'Accept': 'application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json'},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.headers['Docker-Content-Digest'] != digest:
                raise SystemExit('Registry digest differs; no changes made.')
    except urllib.error.HTTPError as error:
        raise SystemExit(f'GHCR rejected access (HTTP {error.code}); no changes made.') from None
    except (urllib.error.URLError, TimeoutError):
        raise SystemExit('GHCR connection failed; no changes made.') from None
    config = json.dumps({'auths': {'ghcr.io': {'auth': auth}}})
    secret = {
        'apiVersion': 'v1', 'kind': 'Secret',
        'metadata': {'name': 'ghcr', 'namespace': 'room-planner'},
        'type': 'kubernetes.io/dockerconfigjson',
        'stringData': {'.dockerconfigjson': config},
    }
    relative = 'beelink/cluster/apps/room-planner/ghcr.sops.yaml'
    result = subprocess.run(
        ['sops', '--encrypt', '--config', 'beelink/.sops.yaml', '--input-type', 'json', '--output-type', 'yaml', '--filename-override', relative, '/dev/stdin'],
        cwd=root, input=json.dumps(secret), text=True, capture_output=True,
    )
    if result.returncode:
        raise SystemExit('SOPS encryption failed; no plaintext or encrypted credential file written.')
    (root / relative).write_text(result.stdout)
    kustomization = root / 'beelink/cluster/apps/room-planner/kustomization.yaml'
    text = kustomization.read_text()
    if '  - ghcr.sops.yaml\n' not in text:
        text = text.replace('# Add ghcr.sops.yaml with scripts/configure-room-planner-registry.py before unsuspending.\n', '')
        kustomization.write_text(text + '  - ghcr.sops.yaml\n')
    print('Pinned image access verified; SOPS-encrypted ghcr Secret saved and added to Kustomize.')
    print('No commit, push, cluster changes, or suspension changes performed.')


if __name__ == '__main__':
    main()
