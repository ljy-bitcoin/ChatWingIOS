#!/usr/bin/env python3
"""Reproducible dependency-free Xcode project generator. Run after adding Swift files."""
from pathlib import Path
import hashlib,json,plistlib
from xml.etree import ElementTree as ET
R=Path(__file__).resolve().parents[1]
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def q(s): return json.dumps(str(s),ensure_ascii=False)
def arr(xs): return '('+', '.join(xs)+',)' if xs else '()'
def settings(d): return '{ '+ ' '.join(f'{k} = {arr([q(x) for x in v]) if isinstance(v,list) else q(v)};' for k,v in d.items())+' }'
objects={}
def obj(name,body):
 i=uid(name); objects[i]=body; return i
files={}
def file(path,typ=None):
 if path in files:return files[path]
 if typ is None:typ={'.swift':'sourcecode.swift','.plist':'text.plist.xml','.json':'text.json','.xcconfig':'text.xcconfig','.entitlements':'text.plist.entitlements','.md':'net.daringfireball.markdown','.xcassets':'folder.assetcatalog'}.get(Path(path).suffix,'text')
 i=obj('file:'+path,f'isa = PBXFileReference; lastKnownFileType = {q(typ)}; path = {q(path)}; sourceTree = SOURCE_ROOT;')
 files[path]=i;return i
base={'CFBundleDevelopmentRegion':'zh_CN','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundleShortVersionString':'0.1.0','CFBundleVersion':'1','SharedAppGroup':'group.$(BUNDLE_PREFIX)'}
for name in ['App','Broadcast','Keyboard']:
 d=base.copy();d['CFBundlePackageType']='APPL' if name=='App' else 'XPC!'
 d['CFBundleDisplayName']='聊伴' if name!='Broadcast' else '聊伴屏幕识别'
 if name in ['App','Broadcast']:d['SharedKeychainGroup']='$(AppIdentifierPrefix)$(BUNDLE_PREFIX).credentials'
 if name=='App':d.update({'LSRequiresIPhoneOS':True,'UILaunchScreen':{},'UIBackgroundModes':['audio'],'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'UIApplicationSupportsIndirectInputEvents':True})
 elif name=='Broadcast':d['NSExtension']={'NSExtensionPointIdentifier':'com.apple.broadcast-services-upload','NSExtensionPrincipalClass':'$(PRODUCT_MODULE_NAME).SampleHandler','RPBroadcastProcessMode':'RPBroadcastProcessModeSampleBuffer'}
 else:d['NSExtension']={'NSExtensionPointIdentifier':'com.apple.keyboard-service','NSExtensionPrincipalClass':'$(PRODUCT_MODULE_NAME).KeyboardViewController','NSExtensionAttributes':{'IsASCIICapable':False,'PrefersRightToLeft':False,'PrimaryLanguage':'zh-Hans','RequestsOpenAccess':True}}
 (R/f'Config/{name}-Info.plist').write_bytes(plistlib.dumps(d,sort_keys=False))
 ent={'com.apple.security.application-groups':['group.$(BUNDLE_PREFIX)']}
 if name in ['App','Broadcast']:ent['keychain-access-groups']=['$(AppIdentifierPrefix)$(BUNDLE_PREFIX).credentials']
 (R/f'Config/{name}.entitlements').write_bytes(plistlib.dumps(ent,sort_keys=False))
privacy={'NSPrivacyTracking':False,'NSPrivacyTrackingDomains':[],
 'NSPrivacyCollectedDataTypes':[{'NSPrivacyCollectedDataType':'NSPrivacyCollectedDataTypeOtherUserContent','NSPrivacyCollectedDataTypeLinked':False,'NSPrivacyCollectedDataTypeTracking':False,'NSPrivacyCollectedDataTypePurposes':['NSPrivacyCollectedDataTypePurposeAppFunctionality']}],
 'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategorySystemBootTime','NSPrivacyAccessedAPITypeReasons':['35F9.1']}]}
(R/'Resources/PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps(privacy,sort_keys=False))
common=['Shared/Models.swift','Shared/SharedStore.swift']
processing=['Shared/Keychain.swift','Shared/APIClient.swift','Shared/OCRReader.swift','Shared/TextLogic.swift']
targets={
 'ChatWing':{'src':common+processing+[str(p.relative_to(R)) for p in sorted((R/'App').glob('*.swift'))],'folder':'App','bundle':'$(BUNDLE_PREFIX)','product':'application','resources':['Resources/JudgeQuestions.json','Resources/Assets.xcassets','Resources/PrivacyInfo.xcprivacy','LICENSE','NOTICE']},
 'ChatWingBroadcast':{'src':common+processing+['Broadcast/SampleHandler.swift'],'folder':'Broadcast','bundle':'$(BUNDLE_PREFIX).Broadcast','product':'app-extension','resources':['Resources/JudgeQuestions.json','Resources/PrivacyInfo.xcprivacy']},
 'ChatWingKeyboard':{'src':common+['Keyboard/KeyboardViewController.swift'],'folder':'Keyboard','bundle':'$(BUNDLE_PREFIX).Keyboard','product':'app-extension','resources':[]},
 'ChatWingTests':{'src':['Tests/ChatWingTests.swift'],'folder':'Tests','bundle':'$(BUNDLE_PREFIX).Tests','product':'bundle.unit-test','resources':[]}}
products=[]
for name,t in targets.items():
 ext='app' if name=='ChatWing' else 'xctest' if name=='ChatWingTests' else 'appex'
 t['productID']=obj('product:'+name,f'isa = PBXFileReference; explicitFileType = {q("wrapper.application" if ext=="app" else "wrapper.app-extension" if ext=="appex" else "wrapper.cfbundle")}; includeInIndex = 0; path = {q(name+"."+ext)}; sourceTree = BUILT_PRODUCTS_DIR;')
 products.append(t['productID'])
 phases=[]
 for kind,paths in [('Sources',t['src']),('Resources',t['resources']),('Frameworks',[])]:
  builds=[]
  for path in paths:
   f=file(path); builds.append(obj('build:'+name+':'+path,f'isa = PBXBuildFile; fileRef = {f};'))
  phases.append(obj('phase:'+name+':'+kind,f'isa = PBX{kind}BuildPhase; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0;'))
 t['phases']=phases
for name,t in targets.items():
 conf=[]
 for mode in ['Debug','Release']:
  d={'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':t['bundle'],'SWIFT_VERSION':'5.0','SWIFT_STRICT_CONCURRENCY':'minimal',
    'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','TARGETED_DEVICE_FAMILY':'1',
    'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks'],'ENABLE_USER_SCRIPT_SANDBOXING':'YES',
    'CLANG_ENABLE_MODULES':'YES','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else '', 'ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO',
    'DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym'}
  if name=='ChatWingTests':d.update({'GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/ChatWing.app/ChatWing','BUNDLE_LOADER':'$(TEST_HOST)'})
  else:d.update({'INFOPLIST_FILE':f'Config/{t["folder"]}-Info.plist','CODE_SIGN_ENTITLEMENTS':f'Config/{t["folder"]}.entitlements','GENERATE_INFOPLIST_FILE':'NO'})
  if name=='ChatWing':d['ASSETCATALOG_COMPILER_APPICON_NAME']='AppIcon'
  if 'Broadcast' in name or 'Keyboard' in name:d.update({'APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES'})
  conf.append(obj('config:'+name+mode,f'isa = XCBuildConfiguration; baseConfigurationReference = {file("Config/Signing.xcconfig")}; buildSettings = {settings(d)}; name = {mode};'))
 t['config']=obj('configs:'+name,f'isa = XCConfigurationList; buildConfigurations = {arr(conf)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
 deps=[]
 for dep in (['ChatWingBroadcast','ChatWingKeyboard'] if name=='ChatWing' else ['ChatWing'] if name=='ChatWingTests' else []):
  proxy=obj('proxy:'+name+dep,f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target:"+dep)}; remoteInfo = {q(dep)};')
  deps.append(obj('dep:'+name+dep,f'isa = PBXTargetDependency; target = {uid("target:"+dep)}; targetProxy = {proxy};'))
 if name=='ChatWing':
  embedded=[]
  for dep in ['ChatWingBroadcast','ChatWingKeyboard']:
   embedded.append(obj('embed:'+dep,f'isa = PBXBuildFile; fileRef = {targets[dep]["productID"]}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};'))
  t['phases'].append(obj('embedphase',f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = {arr(embedded)}; name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;'))
 obj('target:'+name,f'isa = PBXNativeTarget; buildConfigurationList = {t["config"]}; buildPhases = {arr(t["phases"])}; buildRules = (); dependencies = {arr(deps)}; name = {q(name)}; productName = {q(name)}; productReference = {t["productID"]}; productType = {q("com.apple.product-type."+t["product"])};')
# Add documentation/configuration to the navigator too.
for p in sorted((R/'Config').iterdir()):file(str(p.relative_to(R)))
for name in ['README.md','Docs/Architecture.md','Docs/DeviceChecks.md','Docs/Validation.md','LICENSE','NOTICE']:file(name)
groups=[]
for category in ['App','Broadcast','Keyboard','Shared','Resources','Config','Tests','Docs']:
 children=[i for p,i in files.items() if p.startswith(category+'/')]
 groups.append(obj('group:'+category,f'isa = PBXGroup; children = {arr(children)}; name = {q(category)}; sourceTree = "<group>";'))
productsGroup=obj('products',f'isa = PBXGroup; children = {arr(products)}; name = Products; sourceTree = "<group>";')
root=obj('root',f'isa = PBXGroup; children = {arr(groups+[i for p,i in files.items() if "/" not in p]+[productsGroup])}; sourceTree = "<group>";')
confs=[]
for mode in ['Debug','Release']:
 confs.append(obj('projectconf:'+mode,f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_OBJC_ARC = YES; }}; name = {mode};'))
projectconf=obj('projectconfs',f'isa = XCConfigurationList; buildConfigurations = {arr(confs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
attrs=' '.join(uid('target:'+n)+' = { CreatedOnToolsVersion = 16.0; '+('TestTargetID = '+uid('target:ChatWing')+'; ' if n=='ChatWingTests' else '')+'};' for n in targets)
obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {attrs} }}; }}; buildConfigurationList = {projectconf}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (en, Base, zh_CN,); mainGroup = {root}; productRefGroup = {productsGroup}; projectDirPath = ""; projectRoot = ""; targets = {arr([uid("target:"+n) for n in targets])};')
p=R/'ChatWing.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{\n archiveVersion = 1; classes = {}; objectVersion = 56;\n objects = {\n'+''.join(f'  {i} = {{ {b} }};\n' for i,b in objects.items())+' };\n rootObject = '+uid('project')+';\n}\n')
scheme=ET.Element('Scheme',LastUpgradeVersion='1600',version='1.3')
ba=ET.SubElement(scheme,'BuildAction',parallelizeBuildables='YES',buildImplicitDependencies='YES'); entries=ET.SubElement(ba,'BuildActionEntries')
def ref(parent,n):return ET.SubElement(parent,'BuildableReference',BuildableIdentifier='primary',BlueprintIdentifier=uid('target:'+n),BuildableName=n+('.xctest' if n.endswith('Tests') else '.app'),BlueprintName=n,ReferencedContainer='container:ChatWing.xcodeproj')
entry=ET.SubElement(entries,'BuildActionEntry',buildForTesting='YES',buildForRunning='YES',buildForProfiling='YES',buildForArchiving='YES',buildForAnalyzing='YES');ref(entry,'ChatWing')
ta=ET.SubElement(scheme,'TestAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',shouldUseLaunchSchemeArgsEnv='YES'); testables=ET.SubElement(ta,'Testables');ref(ET.SubElement(testables,'TestableReference',skipped='NO'),'ChatWingTests')
la=ET.SubElement(scheme,'LaunchAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',launchStyle='0',useCustomWorkingDirectory='NO',ignoresPersistentStateOnLaunch='NO',debugDocumentVersioning='YES',debugServiceExtension='internal',allowLocationSimulation='YES');ref(ET.SubElement(la,'BuildableProductRunnable',runnableDebuggingMode='0'),'ChatWing')
pa=ET.SubElement(scheme,'ProfileAction',buildConfiguration='Release',shouldUseLaunchSchemeArgsEnv='YES',savedToolIdentifier='',useCustomWorkingDirectory='NO',debugDocumentVersioning='YES');ref(ET.SubElement(pa,'BuildableProductRunnable',runnableDebuggingMode='0'),'ChatWing')
ET.SubElement(scheme,'AnalyzeAction',buildConfiguration='Debug');ET.SubElement(scheme,'ArchiveAction',buildConfiguration='Release',revealArchiveInOrganizer='YES')
sp=p/'xcshareddata/xcschemes';sp.mkdir(parents=True,exist_ok=True);ET.indent(scheme)
ET.ElementTree(scheme).write(sp/'ChatWing.xcscheme',encoding='utf-8',xml_declaration=True)
print('Generated ChatWing.xcodeproj: 4 targets, no package dependencies.')
