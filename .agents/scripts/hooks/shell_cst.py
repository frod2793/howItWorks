"""Parse Bash/Zsh without running it; reject malformed or incomplete CST output."""
import json
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

PARSER = Path(__file__).with_name('shell-parser') / 'bin' / 'tsparse-macos-universal'
_verified = set()
_deadline = None
_NODE_KEYS = {'type', 'start_byte', 'end_byte', 'field', 'named', 'error',
              'has_error', 'missing', 'children'}


def _shell_name(candidate):
    if not isinstance(candidate, str) or not candidate:
        return None
    name = Path(candidate).name
    if name not in ('bash', 'zsh'):
        return None
    resolved = shutil.which(candidate) if '/' not in candidate else candidate
    if resolved and Path(resolved).is_file() and os.access(resolved, os.X_OK):
        return name
    return None


def dialect(tool_input, tool_name=None):
    if not isinstance(tool_input, dict):
        raise ValueError('unsupported shell')
    if tool_name == 'exec_command' and 'shell' in tool_input:
        name = _shell_name(tool_input['shell'])
        if name:
            return name
        raise ValueError('unsupported shell')
    candidates = ([os.environ.get('SHELL')] if tool_name == 'exec_command' else
                  [os.environ.get('CLAUDE_CODE_SHELL'), os.environ.get('SHELL')])
    for candidate in candidates + ['zsh', '/bin/zsh', '/usr/bin/zsh',
                                   'bash', '/bin/bash', '/usr/bin/bash']:
        name = _shell_name(candidate)
        if name:
            return name
    raise ValueError('no supported shell')


def _check_parser():
    package = PARSER.parent.parent
    try:
        manifest = json.loads((package / 'manifest.json').read_text(encoding='utf-8'))
        expected = manifest['package_files']['bin/tsparse-macos-universal']
        if not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected):
            raise ValueError
        if PARSER.is_symlink() or not PARSER.is_file() or not os.access(PARSER, os.X_OK):
            raise ValueError
        key = (str(PARSER), expected)
        if key not in _verified:
            digest = hashlib.sha256()
            with PARSER.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            if digest.hexdigest() != expected:
                raise ValueError
            _verified.add(key)
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
        raise ValueError('native shell parser unavailable') from None


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate CST field')
        result[key] = value
    return result


def _parse_once(raw, shell):
    remaining = _deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError('shell parser time limit exceeded')
    _check_parser()
    remaining = _deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError('shell parser time limit exceeded')
    try:
        result = subprocess.run([str(PARSER), shell], input=raw, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=min(3, remaining), check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise ValueError('native shell parser unavailable') from None
    if result.returncode or not result.stdout or len(result.stdout) > 32 * 1024 * 1024:
        raise ValueError('native shell parser failed')
    try:
        root = json.loads(result.stdout, object_pairs_hook=_unique_object)
    except (ValueError, UnicodeError, RecursionError):
        raise ValueError('invalid CST output') from None
    if not isinstance(root, dict) or root.get('type') != 'program':
        raise ValueError('missing program')
    count = [0]
    def validate(node, depth=0):
        if not isinstance(node, dict) or set(node) != _NODE_KEYS:
            raise ValueError('invalid CST schema')
        count[0] += 1
        start, end = node['start_byte'], node['end_byte']
        if (depth > 128 or count[0] > 100000 or type(start) is not int or
                type(end) is not int or not 0 <= start <= end <= len(raw) or
                not isinstance(node['type'], str) or not node['type'] or
                not (node['field'] is None or isinstance(node['field'], str)) or
                any(type(node[key]) is not bool for key in ('named', 'error', 'has_error', 'missing')) or
                not isinstance(node['children'], list) or
                node['error'] or node['has_error'] or node['missing']):
            raise ValueError('invalid or incomplete CST')
        for child in node['children']:
            if not isinstance(child, dict) or type(child.get('start_byte')) is not int or type(child.get('end_byte')) is not int:
                raise ValueError('invalid CST child')
            if not start <= child['start_byte'] <= child['end_byte'] <= end:
                raise ValueError('CST range outside parent')
            validate(child, depth + 1)
    validate(root)
    if raw[:root['start_byte']].strip() or raw[root['end_byte']:].strip():
        raise ValueError('unparsed shell source')
    return root


def _normalize_continuations(root, raw):
    # Bash/Zsh remove an unquoted backslash-newline before splitting words.
    # The first CST supplies literal regions; the second CST uses these exact bytes.
    positions = []
    for index, byte in enumerate(raw):
        if byte != 10:
            continue
        start = index
        while start and raw[start - 1] == 92:
            start -= 1
        if (index - start) % 2:
            positions.append(index - 1)
    if not positions:
        return raw

    events = []
    stack = [root]
    while stack:
        node = stack.pop()
        kind = node['type']
        if kind == 'heredoc_redirect':
            events.extend(((node['start_byte'], 1, 'redirect'),
                           (node['end_byte'], -1, 'redirect')))
            starts = [child for child in node['children'] if child['type'] == 'heredoc_start']
            bodies = [child for child in node['children'] if child['type'] == 'heredoc_body']
            if len(starts) == len(bodies) == 1:
                delimiter = raw[starts[0]['start_byte']:starts[0]['end_byte']]
                body_kind = ('quoted_body' if any(char in delimiter for char in (39, 34, 92))
                             else 'unquoted_body')
                body = bodies[0]
                events.extend(((body['start_byte'], 1, body_kind),
                               (body['end_byte'], -1, body_kind)))
        elif kind in ('comment', 'raw_string', 'ansi_c_string'):
            events.extend(((node['start_byte'], 1, 'literal'),
                           (node['end_byte'], -1, 'literal')))
        stack.extend(node['children'])

    events.sort(key=lambda event: (event[0], event[1]))  # close before open
    active = {'redirect': 0, 'quoted_body': 0, 'unquoted_body': 0, 'literal': 0}
    removals = []
    cursor = 0
    for position in positions:
        while cursor < len(events) and events[cursor][0] <= position:
            _, delta, kind = events[cursor]
            active[kind] += delta
            cursor += 1
        if active['unquoted_body'] or (active['redirect'] and not active['quoted_body']):
            raise ValueError('ambiguous heredoc continuation')
        if not (active['quoted_body'] or active['literal']):
            removals.append(position)
    if not removals:
        return raw
    chunks = []
    previous = 0
    for position in removals:
        chunks.append(raw[previous:position])
        previous = position + 2
    chunks.append(raw[previous:])
    return b''.join(chunks)


def parse(command, shell):
    global _deadline
    if shell not in ('bash', 'zsh') or not isinstance(command, str):
        raise ValueError('unsupported shell')
    try:
        raw = command.encode('utf-8')
    except UnicodeEncodeError:
        raise ValueError('invalid shell input') from None
    if len(raw) > 1024 * 1024 or b'\0' in raw:
        raise ValueError('invalid shell input')
    if _deadline is None:
        _deadline = time.monotonic() + 10
    first = _parse_once(raw, shell)
    normalized = _normalize_continuations(first, raw)
    if normalized != raw:
        second = _parse_once(normalized, shell)
        if _normalize_continuations(second, normalized) != normalized:
            raise ValueError('continuation changed lexical context')
        return second, normalized
    return first, raw


def source(node, raw):
    return raw[node['start_byte']:node['end_byte']].decode('utf-8')


def children(node, field=None):
    return [child for child in node['children'] if child['named'] and
            (field is None or child['field'] == field)]
