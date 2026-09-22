#!/usr/bin/env python3
"""Check Xcode references, target membership, signing groups, resources and plist structure.
Optional: --swift-syntax requires tree-sitter and tree-sitter-swift (not an SDK compiler).
"""
import argparse
import json
import plistlib
import re
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]

def parse_pbx(text):
    tokens = re.findall(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text)
    tokens = [x for x in tokens if not x.startswith(('//','/*'))]
    cursor = 0
    def take(expected=None):
        nonlocal cursor
        value=tokens[cursor]; cursor+=1
        if expected is not None: assert value==expected, (value,expected)
        return value
    def value():
        token=take()
        if token=='{':
            result={}
            while tokens[cursor]!='}':
                key=value();take('=');item=value();take(';')
                assert key not in result, f'Duplicate key {key}'
                result[key]=item
            take('}');return result
        if token=='(':
            result=[]
            while tokens[cursor]!=')':
                result.append(value())
                if tokens[cursor]==',':take(',')
                else:assert tokens[cursor]==')'
            take(')');return result
        return json.loads(token) if token.startswith('"') else token
    result=value();assert cursor==len(tokens);return result

def main():
    args=argparse.ArgumentParser()
    args.add_argument('--swift-syntax',action='store_true')
    options=args.parse_args()
    project=parse_pbx((ROOT/'ChatWing.xcodeproj/project.pbxproj').read_text())
    objects=project['objects']
    assert project['rootObject'] in objects
    targets={v['name']:v for v in objects.values() if v['isa']=='PBXNativeTarget'}
    assert set(targets)=={'ChatWing','ChatWingBroadcast','ChatWingKeyboard','ChatWingTests'}
    refs=0
    def check(v):
        nonlocal refs
        if isinstance(v,dict):
            for x in v.values():check(x)
        elif isinstance(v,list):
            for x in v:check(x)
        elif re.fullmatch(r'[A-F0-9]{24}',v):
            assert v in objects,f'Unresolved PBX reference: {v}';refs+=1
    for v in objects.values():check(v)
    for v in objects.values():
        if v['isa']=='PBXFileReference' and v['sourceTree']=='SOURCE_ROOT':
            assert (ROOT/v['path']).exists(),f'Missing {v["path"]}'
    def members(name,kind):
        paths=[]
        for phase in targets[name]['buildPhases']:
            p=objects[phase]
            if p['isa']!=kind:continue
            for build in p['files']: paths.append(objects[objects[build]['fileRef']]['path'])
        return paths
    assert set(members('ChatWingKeyboard','PBXSourcesBuildPhase'))=={'Shared/Models.swift','Shared/SharedStore.swift','Keyboard/KeyboardViewController.swift'}
    assert set(members('ChatWing','PBXCopyFilesBuildPhase'))=={'ChatWingBroadcast.appex','ChatWingKeyboard.appex'}
    for name in ['ChatWing','ChatWingBroadcast']:
        assert 'Resources/JudgeQuestions.json' in members(name,'PBXResourcesBuildPhase')
    compiled=set()
    for name in targets:
        src=members(name,'PBXSourcesBuildPhase');assert len(src)==len(set(src))
        compiled.update(src)
    assert compiled=={str(p.relative_to(ROOT)) for p in ROOT.rglob('*.swift')},'Uncompiled Swift source'
    for name in ['App','Broadcast','Keyboard']:
        info=plistlib.loads((ROOT/f'Config/{name}-Info.plist').read_bytes())
        ent=plistlib.loads((ROOT/f'Config/{name}.entitlements').read_bytes())
        assert info['SharedAppGroup']==ent['com.apple.security.application-groups'][0]=='group.$(BUNDLE_PREFIX)'
        if name!='Keyboard':assert info['SharedKeychainGroup']==ent['keychain-access-groups'][0]
        else:assert 'keychain-access-groups' not in ent
    binfo=plistlib.loads((ROOT/'Config/Broadcast-Info.plist').read_bytes())
    assert binfo['NSExtension']['RPBroadcastProcessMode']=='RPBroadcastProcessModeSampleBuffer'
    schema=ElementTree.parse(ROOT/'ChatWing.xcodeproj/xcshareddata/xcschemes/ChatWing.xcscheme')
    for item in schema.findall('.//BuildableReference'):
        assert item.attrib['BlueprintIdentifier'] in objects
    questions=json.loads((ROOT/'Resources/JudgeQuestions.json').read_text())
    assert set(questions)=={'literal_question','true_intent','danger_level','should_reply_now','best_action','she_needs','tension_resolved'}
    assert len(questions['danger_level']['criteria'])==10
    for p in ROOT.rglob('*.plist'):plistlib.loads(p.read_bytes())
    for p in ROOT.rglob('*.xcprivacy'):plistlib.loads(p.read_bytes())
    for p in ROOT.rglob('*.json'):json.loads(p.read_text())
    print(f'PASS: {len(targets)} targets, {len(compiled)} Swift files, {refs} PBX references; plists, groups, resources and scheme valid.')
    if options.swift_syntax:
        import tree_sitter_swift
        from tree_sitter import Language, Parser
        parser=Parser(Language(tree_sitter_swift.language()))
        for path in sorted(ROOT.rglob('*.swift')):
            tree=parser.parse(path.read_bytes())
            assert not tree.root_node.has_error,f'Swift syntax error in {path}'
        print(f'PASS: Swift grammar parsed all {len(compiled)} files; SDK type-check/build still requires Xcode.')

if __name__=='__main__':main()
