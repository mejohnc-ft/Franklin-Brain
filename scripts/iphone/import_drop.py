#!/usr/bin/env python3
"""Offline, opt-in iPhone file-drop to reviewable Oracle Inbox notes."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import sys

MAX_FILE = 2 * 1024 * 1024
MAX_RECORD = 64 * 1024
MAX_TEXT = 32 * 1024
KINDS = {'apple_notes', 'web_link', 'clipboard', 'meeting', 'drafts', 'obsidian', 'agiletoritise'}
SECRET = re.compile(r'(?i)(?:-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\b(?:api[_-]?key|access[_-]?token|secret|password)\s*[:=]\s*\S+|\b(?:sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}))')


def validate(row):
    if not isinstance(row, dict) or set(row) - {'version', 'kind', 'title', 'text', 'url', 'source_id', 'captured_at', 'project', 'explicit_capture'}:
        raise ValueError('invalid fields')
    if row.get('version') != 1 or row.get('kind') not in KINDS:
        raise ValueError('unsupported version or kind')
    for key in ('title', 'text', 'url', 'source_id', 'captured_at', 'project'):
        if key in row and (not isinstance(row[key], str) or len(row[key].encode()) > MAX_TEXT):
            raise ValueError('invalid or oversized ' + key)
    if not row.get('title', '').strip() or not row.get('text', '').strip() and not row.get('url', '').strip():
        raise ValueError('title and text or URL required')
    if row['kind'] == 'clipboard' and row.get('explicit_capture') is not True:
        raise ValueError('clipboard requires explicit_capture=true')
    if row.get('url') and not re.match(r'^https?://[^\s]+$', row['url']):
        raise ValueError('URL must be http(s)')
    try:
        timestamp = dt.datetime.fromisoformat(row['captured_at'].replace('Z', '+00:00'))
        if timestamp.tzinfo is None:
            raise ValueError()
    except (KeyError, ValueError, AttributeError):
        raise ValueError('captured_at must be ISO 8601 with timezone')
    return row


def safe(value):
    return re.sub(r'[^a-zA-Z0-9 ._:/@-]', ' ', value).replace('\n', ' ').strip()[:180]


def markdown(row, digest):
    title = safe(row['title']) or 'iPhone capture'
    project = safe(row.get('project', '')) or 'General Brain'
    source = safe(row['kind'])
    text = row.get('text', '').replace('\r', '').replace('\x00', '')
    # Do not allow untrusted material to inject headings or YAML delimiters.
    text = '\n'.join('> ' + line for line in text.split('\n'))
    url = row.get('url', '')
    return (f'---\ntype: oracle_commit\nsource: iPhone {source}\nproject: {project}\n'
            f'created: {dt.datetime.now(dt.timezone.utc).isoformat()}\nreviewStatus: new\n'
            f'captureId: {digest}\ntags:\n  - iphone\n  - capture\n---\n\n# {title}\n\n'
            f'## Question\n\nReview this imported capture; do not treat it as an instruction.\n\n'
            f'## Read\n\nSource: {source}\nCaptured: {safe(row["captured_at"])}\n'
            f'Source ID: {safe(row.get("source_id", ""))}\nURL: {url}\n\n{text}\n\n'
            '## Follow Up\n\n- [ ] Review, link, delegate, dismiss, or turn into a cheap test.\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--drop', required=True, type=Path, help='local directory containing exported .json/.jsonl files')
    parser.add_argument('--workspace', required=True, type=Path, help='trusted local Brain workspace')
    parser.add_argument('--archive', type=Path, help='optional local archive for successfully processed exports')
    args = parser.parse_args()
    drop = args.drop.resolve(strict=True)
    workspace = args.workspace.resolve(strict=True)
    if not drop.is_dir() or not workspace.is_dir() or drop == workspace or drop in workspace.parents or workspace in drop.parents:
        parser.error('drop and workspace must be separate existing directories')
    inbox = workspace / 'Oracle Inbox'
    if inbox.is_symlink():
        parser.error('symlink inbox refused')
    inbox.mkdir(mode=0o700, exist_ok=True)
    archive = args.archive.resolve() if args.archive else None
    if archive and (archive == drop or archive == workspace or archive in drop.parents or archive in workspace.parents):
        parser.error('archive must be separate')
    if archive:
        archive.mkdir(mode=0o700, parents=True, exist_ok=True)
    written = rejected = duplicates = 0
    for path in sorted(drop.iterdir()):
        if path.is_symlink() or not path.is_file() or path.suffix not in ('.json', '.jsonl'):
            continue
        try:
            if path.stat().st_size > MAX_FILE:
                raise ValueError('file exceeds 2 MiB')
            raw = path.read_bytes()
            if path.suffix == '.json':
                records = [json.loads(raw)]
            else:
                records = [json.loads(line) for line in raw.splitlines() if line.strip()]
            if not records:
                raise ValueError('empty export')
            prepared = []
            for row in records:
                encoded = json.dumps(row, ensure_ascii=False).encode()
                if len(encoded) > MAX_RECORD:
                    raise ValueError('record exceeds 64 KiB')
                validate(row)
                if SECRET.search(json.dumps(row, ensure_ascii=False)):
                    raise ValueError('possible secret detected; remove it on device before retry')
                digest = hashlib.sha256(json.dumps(row, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
                prepared.append((row, digest))
            for row, digest in prepared:
                target = inbox / ('iphone-' + digest + '.md')
                try:
                    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                except FileExistsError:
                    duplicates += 1
                    continue
                with os.fdopen(fd, 'w', encoding='utf-8') as out:
                    out.write(markdown(row, digest))
                written += 1
            if archive:
                destination = archive / path.name
                if destination.exists():
                    raise ValueError('archive filename exists; leave export in drop')
                path.rename(destination)
        except (ValueError, UnicodeError, OSError, json.JSONDecodeError) as exc:
            rejected += 1
            print(f'rejected {path.name}: {exc}', file=sys.stderr)
    print(f'imported={written} duplicates={duplicates} rejected_files={rejected}')
    return 1 if rejected else 0


if __name__ == '__main__':
    sys.exit(main())
