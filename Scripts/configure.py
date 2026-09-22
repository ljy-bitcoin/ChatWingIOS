#!/usr/bin/env python3
"""Configure bundle IDs and signing in one place. No external packages required."""
import argparse
import pathlib
import re

p = argparse.ArgumentParser()
p.add_argument('--bundle-id', required=True, help='e.g. com.yourname.chatwing')
p.add_argument('--team', required=True, help='10-character Apple Developer Team ID')
a = p.parse_args()
if not re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z][A-Za-z0-9-]*){2,}', a.bundle_id):
    p.error('Bundle ID must use at least three reverse-domain components.')
if not re.fullmatch(r'[A-Z0-9]{10}', a.team):
    p.error('Team ID must be exactly 10 uppercase letters/digits.')
root = pathlib.Path(__file__).resolve().parents[1]
(root / 'Config/Signing.xcconfig').write_text(
    f'BUNDLE_PREFIX = {a.bundle_id}\nDEVELOPMENT_TEAM = {a.team}\nCODE_SIGN_STYLE = Automatic\n'
)
print(f'Configured app: {a.bundle_id}')
print(f'App Group: group.{a.bundle_id}')
print(f'Keychain group: <AppIdentifierPrefix>{a.bundle_id}.credentials')
print('Open ChatWing.xcodeproj, choose your Team for all targets, and register the App Group.')
