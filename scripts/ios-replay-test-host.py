"""Generate a minimal foreground UIKit test host for real simulator screenshot tests.

SPM's unhosted test process is not an active customer application. Keep production
foreground/privacy checks intact and execute the same SDK tests inside a real app.
No Xcode project generator or third-party build dependencies are required.
"""
import hashlib
import plistlib
import sys
from pathlib import Path
from xml.etree.ElementTree import Element, SubElement, ElementTree

root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
project = out/'ReplayQA.xcodeproj'
project.mkdir(exist_ok=True)
(out/'App.swift').write_text('''import UIKit
@main final class ReplayQAApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .white
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
''')
objects = {}
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def obj(key_name, isa, **fields):
    key = uid(key_name)
    objects[key] = dict(isa=isa, **fields)
    return key
def source(path):
    ref = obj(str(path), 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=str(path), sourceTree='<absolute>')
    build = obj('build:'+str(path), 'PBXBuildFile', fileRef=ref)
    return ref, build
app_ref, app_source = source(out/'App.swift')
tests = [source(p) for p in sorted((root/'Tests/SignaloryxTests').glob('*.swift'))]
assert tests, 'No SDK tests found'
app_product = obj('app-product', 'PBXFileReference', explicitFileType='wrapper.application', path='ReplayQAHost.app', sourceTree='BUILT_PRODUCTS_DIR')
test_product = obj('test-product', 'PBXFileReference', explicitFileType='wrapper.cfbundle', path='ReplayQATests.xctest', sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products', 'PBXGroup', children=[app_product, test_product], name='Products', sourceTree='<group>')
group = obj('root-group', 'PBXGroup', children=[app_ref, *[r for r, _ in tests], products], sourceTree='<group>')
package = obj('package', 'XCLocalSwiftPackageReference', relativePath=str(root))
dependency = obj('sdk', 'XCSwiftPackageProductDependency', package=package, productName='Signaloryx')
sdk_build = obj('sdk-build', 'PBXBuildFile', productRef=dependency)
def phase(name, isa, files): return obj(name, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)
def configs(name, values):
    refs = []
    for mode in ('Debug', 'Release'):
        settings = dict(values)
        settings.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode == 'Debug' else '-O')
        refs.append(obj(name+mode, 'XCBuildConfiguration', name=mode, buildSettings=settings))
    return obj(name+'config-list', 'XCConfigurationList', buildConfigurations=refs, defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')
common = dict(SDKROOT='iphoneos', IPHONEOS_DEPLOYMENT_TARGET='15.0', SWIFT_VERSION='5.0', ENABLE_TESTABILITY='YES',
              CODE_SIGNING_ALLOWED='NO', TARGETED_DEVICE_FAMILY='1,2', GENERATE_INFOPLIST_FILE='YES',
              ARCHS='$(ARCHS_STANDARD)', ONLY_ACTIVE_ARCH='YES')
app_config = configs('app', dict(common, PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER='com.signaloryx.replay-qa-host'))
test_config = configs('tests', dict(common, PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER='com.signaloryx.replay-qa-tests',
    TEST_HOST='$(BUILT_PRODUCTS_DIR)/ReplayQAHost.app/ReplayQAHost', BUNDLE_LOADER='$(TEST_HOST)'))
app_target = obj('app-target', 'PBXNativeTarget', name='ReplayQAHost', productName='ReplayQAHost', productReference=app_product,
    productType='com.apple.product-type.application', buildConfigurationList=app_config, dependencies=[], buildRules=[],
    buildPhases=[phase('app-sources', 'PBXSourcesBuildPhase', [app_source]), phase('app-frameworks', 'PBXFrameworksBuildPhase', [])])
proxy = obj('proxy', 'PBXContainerItemProxy', containerPortal=uid('project'), proxyType=1, remoteGlobalIDString=app_target, remoteInfo='ReplayQAHost')
target_dep = obj('host-dependency', 'PBXTargetDependency', target=app_target, targetProxy=proxy)
test_target = obj('test-target', 'PBXNativeTarget', name='ReplayQATests', productName='ReplayQATests', productReference=test_product,
    productType='com.apple.product-type.bundle.unit-test', buildConfigurationList=test_config, dependencies=[target_dep], buildRules=[],
    packageProductDependencies=[dependency], buildPhases=[phase('test-sources', 'PBXSourcesBuildPhase', [b for _, b in tests]),
    phase('test-frameworks', 'PBXFrameworksBuildPhase', [sdk_build])])
project_ref = obj('project', 'PBXProject', attributes={'LastUpgradeCheck': '1600', 'TargetAttributes': {test_target: {'TestTargetID': app_target}}},
    buildConfigurationList=configs('project', common), compatibilityVersion='Xcode 14.0', developmentRegion='en', knownRegions=['en', 'Base'],
    mainGroup=group, productRefGroup=products, projectDirPath='', projectRoot='', targets=[app_target, test_target], packageReferences=[package])
with (project/'project.pbxproj').open('wb') as stream:
    plistlib.dump(dict(archiveVersion='1', classes={}, objectVersion='56', objects=objects, rootObject=project_ref), stream)
scheme = Element('Scheme', LastUpgradeVersion='1600', version='1.3')
build = SubElement(scheme, 'BuildAction', parallelizeBuildables='YES', buildImplicitDependencies='YES')
entries = SubElement(build, 'BuildActionEntries')
entry = SubElement(entries, 'BuildActionEntry', buildForTesting='YES', buildForRunning='YES', buildForProfiling='NO', buildForArchiving='NO', buildForAnalyzing='YES')
def reference(parent, target, name, product):
    SubElement(parent, 'BuildableReference', BuildableIdentifier='primary', BlueprintIdentifier=target,
               BuildableName=product, BlueprintName=name, ReferencedContainer='container:ReplayQA.xcodeproj')
reference(entry, test_target, 'ReplayQATests', 'ReplayQATests.xctest')
test_action = SubElement(scheme, 'TestAction', buildConfiguration='Debug', selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',
    selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB', shouldUseLaunchSchemeArgsEnv='YES')
testables = SubElement(test_action, 'Testables')
testable = SubElement(testables, 'TestableReference', skipped='NO', parallelizable='NO')
reference(testable, test_target, 'ReplayQATests', 'ReplayQATests.xctest')
schemes = project/'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
ElementTree(scheme).write(schemes/'ReplayQA.xcscheme', encoding='utf-8', xml_declaration=True)
print('Generated foreground iOS test host:', project)
