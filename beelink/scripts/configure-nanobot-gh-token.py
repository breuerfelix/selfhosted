#!/usr/bin/env python3
"""Prompt for GH_TOKEN, encrypt it with SOPS, and wire it into Nanobot via Flux."""

import argparse
import getpass
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import warnings


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    if not shutil.which('sops'):
        raise SystemExit('Install sops first; no changes made.')

    root = Path(__file__).resolve().parents[2]
    directory = root / 'beelink/cluster/apps/nanobot'
    deployment = directory / 'app.yaml'
    kustomization = directory / 'kustomization.yaml'
    secret_path = directory / 'gh-token.sops.yaml'
    app = deployment.read_text()
    resources = kustomization.read_text()
    reference = (
        '            - name: GH_TOKEN\n'
        '              valueFrom:\n'
        '                secretKeyRef:\n'
        '                  name: nanobot-github\n'
        '                  key: GH_TOKEN\n'
    )
    if reference not in app:
        if 'name: GH_TOKEN' in app or app.count('          env:\n') != 1:
            raise SystemExit('Unexpected Nanobot env configuration; no changes made.')
        app = app.replace('          env:\n', '          env:\n' + reference, 1)
    resource = '  - gh-token.sops.yaml'
    if resource not in resources.splitlines():
        resources = resources.rstrip() + '\n' + resource + '\n'

    try:
        # Refuse getpass's echoed-stdin fallback when no terminal is available.
        with warnings.catch_warnings():
            warnings.simplefilter('error', getpass.GetPassWarning)
            token = getpass.getpass('Paste GH_TOKEN (hidden): ').strip()
    except (EOFError, getpass.GetPassWarning):
        raise SystemExit('Run in an interactive terminal; no changes made.') from None
    except KeyboardInterrupt:
        raise SystemExit('\nCancelled; no changes made.') from None
    if not token or any(character.isspace() for character in token):
        raise SystemExit('Token must be nonempty and contain no whitespace; no changes made.')

    secret = {
        'apiVersion': 'v1',
        'kind': 'Secret',
        'metadata': {'name': 'nanobot-github', 'namespace': 'nanobot'},
        'type': 'Opaque',
        'stringData': {'GH_TOKEN': token},
    }
    result = subprocess.run(
        [
            'sops', '--encrypt', '--config', '.sops.yaml',
            '--input-type', 'json', '--output-type', 'yaml',
            '--filename-override', str(secret_path.relative_to(root)), '/dev/stdin',
        ],
        cwd=root, input=json.dumps(secret), text=True, capture_output=True,
    )
    if result.returncode:
        raise SystemExit('SOPS encryption failed; no changes made.')

    # Only ciphertext reaches disk. Replace atomically to preserve an existing secret.
    with tempfile.NamedTemporaryFile(mode='w', dir=directory, delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(result.stdout)
            output.close()
            temporary.replace(secret_path)
        finally:
            temporary.unlink(missing_ok=True)
    if app != deployment.read_text():
        deployment.write_text(app)
    if resources != kustomization.read_text():
        kustomization.write_text(resources)

    print('SOPS-encrypted Secret saved; Nanobot now references its GH_TOKEN key.')
    print('Review, commit, and push these files to main for Flux to deploy:')
    for path in (secret_path, deployment, kustomization):
        print(f'  {path.relative_to(root)}')
    print('After Flux reconciles, restart Nanobot when rotating an existing token:')
    print('  kubectl -n nanobot rollout restart deployment/nanobot')
    print('  kubectl -n nanobot rollout status deployment/nanobot --timeout=300s')


if __name__ == '__main__':
    main()
