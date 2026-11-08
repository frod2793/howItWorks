#!/bin/bash
# Explicit launch request only. Success means launched, never Editor identity/ready.
set -u
command -v python3 >/dev/null 2>&1 || { echo 'open-unity-editor requires Python 3' >&2; exit 4; }
exec python3 - "$@" <<'PY'
import argparse
import json
import math
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import unicodedata
from xml.parsers.expat import ExpatError

parser = argparse.ArgumentParser(description='Open the exact project/version; never install or terminate an Editor.')
parser.add_argument('--project-root', required=True)
parser.add_argument('--unity-app', help='Exact installed Unity.app for native fallback')
parser.add_argument('--skip-cli', action='store_true', help='Use only after a previous CLI attempt failed')
parser.add_argument('--cli-timeout', type=float, default=180, help='CLI timeout seconds; timeout never retries via app')
args = parser.parse_args()

try:
    if sys.platform != 'darwin': raise ValueError('native Editor fallback supports macOS only; Windows not_run')
    if not math.isfinite(args.cli_timeout) or args.cli_timeout <= 0: raise ValueError('--cli-timeout must be positive and finite')
    supplied = Path(args.project_root)
    if not supplied.is_absolute(): raise ValueError('--project-root must be an absolute project path')
    root = supplied.resolve(strict=True)
    if not root.is_dir(): raise ValueError('project root is not a directory')
    version_file = root / 'ProjectSettings/ProjectVersion.txt'
    versions = re.findall(r'^m_EditorVersion:\s*(\S+)\s*$', version_file.read_text(), re.MULTILINE)
    if len(versions) != 1 or not re.fullmatch(r'\d+\.\d+\.\d+[abfp]\d+', versions[0]):
        raise ValueError('ProjectVersion.txt must contain one exact m_EditorVersion')
    version = versions[0]

    def prevent_duplicate():
        lock = root / 'Temp/UnityLockfile'
        if lock.exists() or lock.is_symlink(): raise ValueError('project UnityLockfile exists; verify the owning Editor and recover manually; no launch, deletion or termination performed')
        process = shutil.which('ps')
        if not process: raise ValueError('cannot inspect existing Editor processes: ps unavailable')
        listing = subprocess.run([process, '-axo', 'command='], capture_output=True, text=True)
        if listing.returncode: raise ValueError('cannot inspect existing Editor processes')
        for command in listing.stdout.splitlines():
            if '.app/Contents/MacOS/Unity' not in command: continue
            # ps flattens argv. Quoted paths are explicit; for unquoted paths
            # inspect every possible option boundary so "project -game" is not
            # truncated. Ambiguous matches conservatively prevent another launch.
            match = re.search(r'(?i)(?:^|\s)-projectpath\s+(.+)$', command)
            if not match: continue
            value = match.group(1)
            quoted = re.match(r"([\"'])(.*?)\1(?=\s|$)", value)
            if quoted:
                candidates = [quoted.group(2)]
            else:
                candidates = [value[:i] for m in re.finditer(r'(?i)\s+(?=-[a-z])', value)
                              for i in range(m.start(), m.end())] + [value]
            for candidate_text in candidates:
                candidate = Path(unicodedata.normalize('NFC', candidate_text.rstrip('/')))
                if candidate.is_absolute():
                    try: same = candidate.samefile(root)
                    except OSError: same = candidate.resolve() == root
                    if same: raise ValueError('Unity process may target this project or its flattened argv is ambiguous; no additional launch performed')

    prevent_duplicate()
    cli = shutil.which('unity')
    home_cli = Path.home() / '.unity/bin/unity'
    if not cli and home_cli.is_file() and os.access(home_cli, os.X_OK): cli = str(home_cli)
    via = None
    if cli and not args.skip_cli:
        try:
            result = subprocess.run([cli, 'open', str(root), '--editor-version', version], stdin=subprocess.DEVNULL, timeout=args.cli_timeout)
            if result.returncode == 0: via = 'cli'
        except subprocess.TimeoutExpired:
            raise ValueError('Unity CLI timed out; partial launch unknown, no app retry. Check project identity before another launch')
        except OSError as error:
            print('Unity CLI unavailable: '+str(error), file=sys.stderr)
    if via is None:
        # A failed CLI might already have started an Editor; check again before retrying.
        # ponytail: snapshot checks are not atomic; use Hub/OS launch arbitration if needed.
        prevent_duplicate()
        if args.unity_app:
            supplied_app = Path(args.unity_app)
        else:
            locations = [Path('/Applications/Unity/Hub/Editor')]
            hub = Path.home() / 'Library/Application Support/UnityHub/secondaryInstallPath.json'
            if hub.exists() or hub.is_symlink():
                try:
                    content = hub.read_text(encoding='utf-8').strip()
                    secondary = json.loads(content) if content else ''
                except (OSError, UnicodeError, json.JSONDecodeError, RecursionError) as error:
                    raise ValueError('cannot read or parse Hub secondaryInstallPath JSON; specify --unity-app') from error
                if secondary != '':
                    if not isinstance(secondary, str) or not Path(secondary).is_absolute():
                        raise ValueError('invalid Hub secondaryInstallPath; specify --unity-app')
                    locations.insert(0, Path(secondary))
            apps = {p.resolve() for location in locations for p in [location / version / 'Unity.app'] if p.is_dir()}
            if len(apps) != 1: raise ValueError('exact Unity.app missing or ambiguous; specify --unity-app')
            supplied_app = apps.pop()
        if not supplied_app.is_absolute(): raise ValueError('--unity-app must be an absolute app path')
        app = supplied_app.resolve(strict=True)
        if app.name != 'Unity.app' or not app.is_dir(): raise ValueError('fallback must be an installed Unity.app')
        try:
            plist_path = app / 'Contents/Info.plist'
            if not plist_path.is_file(): raise ValueError('Unity.app Info.plist must be a regular file')
            with plist_path.open('rb') as stream: metadata = plistlib.load(stream)
        except (OSError, ValueError, AttributeError, TypeError, LookupError, RecursionError, plistlib.InvalidFileException, ExpatError) as error:
            raise ValueError('cannot read or parse Unity.app Info.plist') from error
        if not isinstance(metadata, dict): raise ValueError('Unity.app Info.plist must contain a dictionary')
        installed_version = metadata.get('CFBundleVersion')
        if not installed_version:
            installed_version = str(metadata.get('CFBundleShortVersionString', '')).removeprefix('Unity version ')
        if installed_version != version: raise ValueError('Unity.app version does not exactly match ProjectVersion.txt')
        executable = app / 'Contents/MacOS/Unity'
        if metadata.get('CFBundleExecutable') != 'Unity' or not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError('Unity.app executable metadata/file is invalid')
        opener = shutil.which('open')
        if not opener: raise ValueError('macOS open command unavailable')
        result = subprocess.run([opener, '-gna', str(app), '--args', '-projectPath', str(root)], stdin=subprocess.DEVNULL)
        if result.returncode: raise ValueError('native Unity.app launch failed; no retry performed')
        via = 'app'
    print('launched_via='+via)
    print('identity=unverified')
    print('project_path='+str(root))
    print('editor_version='+version)
except (OSError, ValueError, RuntimeError, plistlib.InvalidFileException) as error:
    print('open-unity-editor: '+str(error), file=sys.stderr)
    sys.exit(4)
PY
