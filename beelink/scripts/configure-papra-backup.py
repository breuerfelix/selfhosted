#!/usr/bin/env python3
"""Run as root on Beelink after Flux creates Papra's backup ServiceAccount."""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    if os.geteuid() != 0 or not os.path.ismount('/data'):
        raise SystemExit('Run as root on Beelink with the data SSD mounted at /data')
    secret = json.loads(subprocess.check_output([
        'k3s', 'kubectl', '-n', 'papra', 'get', 'secret',
        'restic-backup-token', '-o', 'json',
    ]))['data']
    config = {
        'apiVersion': 'v1', 'kind': 'Config',
        'clusters': [{'name': 'beelink', 'cluster': {
            'server': 'https://192.168.178.13:6443',
            'certificate-authority-data': secret['ca.crt'],
        }}],
        'users': [{'name': 'restic-papra', 'user': {
            'token': base64.b64decode(secret['token']).decode(),
        }}],
        'contexts': [{'name': 'papra', 'context': {
            'cluster': 'beelink', 'user': 'restic-papra', 'namespace': 'papra',
        }}],
        'current-context': 'papra',
    }
    directory = Path('/data/restic-backup')
    directory.mkdir(mode=0o700, exist_ok=True)
    directory.chmod(0o700)
    fd, temporary = tempfile.mkstemp(dir=directory)
    try:
        with os.fdopen(fd, 'w') as handle:
            json.dump(config, handle)
        os.replace(temporary, directory / 'papra.kubeconfig')
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print('Scoped Papra backup kubeconfig installed with mode 0600; no credentials printed.')


if __name__ == '__main__':
    main()
