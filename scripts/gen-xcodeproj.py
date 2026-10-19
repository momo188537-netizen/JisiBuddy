# 生成 JisiBuddy.xcodeproj（机器上没有 xcodegen 时手写的生成器）。
# 用法：python3 scripts/gen-xcodeproj.py . [DEVELOPMENT_TEAM]
# 注意：会覆盖 Xcode 里对工程做的改动。
import hashlib, os, sys

root = sys.argv[1]
TEAM = sys.argv[2] if len(sys.argv) > 2 else ""

def i(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

P = {k: i(k) for k in [
    "project", "mainGroup", "productsGroup", "appProduct", "widgetProduct",
    "appGroupFolder", "widgetGroupFolder", "configGroup",
    "appTarget", "widgetTarget",
    "appSources", "appFrameworks", "appResources", "appEmbed",
    "widgetSources", "widgetFrameworks", "widgetResources",
    "projDebug", "projRelease", "projConfigList",
    "appDebug", "appRelease", "appConfigList",
    "widgetDebug", "widgetRelease", "widgetConfigList",
    "pkgRef", "appPkgDep", "widgetPkgDep", "appPkgBuild", "widgetPkgBuild",
    "embedBuildFile", "targetDep", "containerProxy",
    "cfgAppEnt", "cfgWidgetEnt", "cfgWidgetPlist",
]}

def settings(d):
    out = []
    for k, v in d.items():
        if isinstance(v, list):
            out.append(f"\t\t\t\t{k} = (\n" + "".join(f'\t\t\t\t\t"{x}",\n' for x in v) + "\t\t\t\t);")
        else:
            out.append(f'\t\t\t\t{k} = "{v}";')
    return "\n".join(out)

common_proj = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "DEVELOPMENT_TEAM": TEAM,
}
proj_debug = dict(common_proj, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
proj_release = dict(common_proj, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})
app = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_ENTITLEMENTS": "Config/JisiApp.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "2",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "鸡丝",
    "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "0.1",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.zixu.jisibuddy",
    "PRODUCT_NAME": "JisiBuddy",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1",
}
widget = {
    "CODE_SIGN_ENTITLEMENTS": "Config/JisiWidgets.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "2",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/JisiWidgets-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "鸡丝",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "MARKETING_VERSION": "0.1",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.zixu.jisibuddy.widgets",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1",
}

def config(id, name, d):
    return f"""\t\t{id} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{settings(d)}
\t\t\t}};
\t\t\tname = {name};
\t\t}};
"""

def configlist(id, debug, release):
    return f"""\t\t{id} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug} /* Debug */,
\t\t\t\t{release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
"""

def phase(id, isa, files=(), extra=""):
    f = "".join(f"\t\t\t\t{x},\n" for x in files)
    return f"""\t\t{id} = {{
\t\t\tisa = {isa};
\t\t\tbuildActionMask = 2147483647;
{extra}\t\t\tfiles = (
{f}\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""

out = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXBuildFile section */
\t\t{P['appPkgBuild']} /* JisiKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {P['appPkgDep']} /* JisiKit */; }};
\t\t{P['widgetPkgBuild']} /* JisiKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {P['widgetPkgDep']} /* JisiKit */; }};
\t\t{P['embedBuildFile']} /* JisiWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {P['widgetProduct']} /* JisiWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t{P['containerProxy']} = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {P['project']} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {P['widgetTarget']};
\t\t\tremoteInfo = JisiWidgets;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
{phase(P['appEmbed'], 'PBXCopyFilesBuildPhase', [P['embedBuildFile'] + ' /* JisiWidgets.appex in Embed Foundation Extensions */'], chr(9)*3 + 'dstPath = "";' + chr(10) + chr(9)*3 + 'dstSubfolderSpec = 13;' + chr(10) + chr(9)*3 + 'name = "Embed Foundation Extensions";' + chr(10))}/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
\t\t{P['appProduct']} /* JisiBuddy.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = JisiBuddy.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{P['widgetProduct']} /* JisiWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = JisiWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{P['cfgAppEnt']} /* JisiApp.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = JisiApp.entitlements; sourceTree = "<group>"; }};
\t\t{P['cfgWidgetEnt']} /* JisiWidgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = JisiWidgets.entitlements; sourceTree = "<group>"; }};
\t\t{P['cfgWidgetPlist']} /* JisiWidgets-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "JisiWidgets-Info.plist"; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
\t\t{P['appGroupFolder']} /* JisiApp */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = JisiApp; sourceTree = "<group>"; }};
\t\t{P['widgetGroupFolder']} /* JisiWidgets */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = JisiWidgets; sourceTree = "<group>"; }};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase(P['appFrameworks'], 'PBXFrameworksBuildPhase', [P['appPkgBuild'] + ' /* JisiKit in Frameworks */'])}{phase(P['widgetFrameworks'], 'PBXFrameworksBuildPhase', [P['widgetPkgBuild'] + ' /* JisiKit in Frameworks */'])}/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{P['mainGroup']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{P['appGroupFolder']} /* JisiApp */,
\t\t\t\t{P['widgetGroupFolder']} /* JisiWidgets */,
\t\t\t\t{P['configGroup']} /* Config */,
\t\t\t\t{P['productsGroup']} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{P['configGroup']} /* Config */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{P['cfgAppEnt']} /* JisiApp.entitlements */,
\t\t\t\t{P['cfgWidgetEnt']} /* JisiWidgets.entitlements */,
\t\t\t\t{P['cfgWidgetPlist']} /* JisiWidgets-Info.plist */,
\t\t\t);
\t\t\tpath = Config;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{P['productsGroup']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{P['appProduct']} /* JisiBuddy.app */,
\t\t\t\t{P['widgetProduct']} /* JisiWidgets.appex */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{P['appTarget']} /* JisiApp */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {P['appConfigList']};
\t\t\tbuildPhases = (
\t\t\t\t{P['appSources']} /* Sources */,
\t\t\t\t{P['appFrameworks']} /* Frameworks */,
\t\t\t\t{P['appResources']} /* Resources */,
\t\t\t\t{P['appEmbed']} /* Embed Foundation Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{P['targetDep']} /* PBXTargetDependency */,
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{P['appGroupFolder']} /* JisiApp */,
\t\t\t);
\t\t\tname = JisiApp;
\t\t\tpackageProductDependencies = (
\t\t\t\t{P['appPkgDep']} /* JisiKit */,
\t\t\t);
\t\t\tproductName = JisiApp;
\t\t\tproductReference = {P['appProduct']} /* JisiBuddy.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{P['widgetTarget']} /* JisiWidgets */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {P['widgetConfigList']};
\t\t\tbuildPhases = (
\t\t\t\t{P['widgetSources']} /* Sources */,
\t\t\t\t{P['widgetFrameworks']} /* Frameworks */,
\t\t\t\t{P['widgetResources']} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{P['widgetGroupFolder']} /* JisiWidgets */,
\t\t\t);
\t\t\tname = JisiWidgets;
\t\t\tpackageProductDependencies = (
\t\t\t\t{P['widgetPkgDep']} /* JisiKit */,
\t\t\t);
\t\t\tproductName = JisiWidgets;
\t\t\tproductReference = {P['widgetProduct']} /* JisiWidgets.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{P['project']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{P['appTarget']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t\t{P['widgetTarget']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {P['projConfigList']};
\t\t\tdevelopmentRegion = "zh-Hans";
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\t"zh-Hans",
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {P['mainGroup']};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpackageReferences = (
\t\t\t\t{P['pkgRef']} /* XCLocalSwiftPackageReference "JisiKit" */,
\t\t\t);
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {P['productsGroup']} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{P['appTarget']} /* JisiApp */,
\t\t\t\t{P['widgetTarget']} /* JisiWidgets */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase(P['appResources'], 'PBXResourcesBuildPhase')}{phase(P['widgetResources'], 'PBXResourcesBuildPhase')}/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase(P['appSources'], 'PBXSourcesBuildPhase')}{phase(P['widgetSources'], 'PBXSourcesBuildPhase')}/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{P['targetDep']} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {P['widgetTarget']} /* JisiWidgets */;
\t\t\ttargetProxy = {P['containerProxy']} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{config(P['projDebug'], 'Debug', proj_debug)}{config(P['projRelease'], 'Release', proj_release)}{config(P['appDebug'], 'Debug', app)}{config(P['appRelease'], 'Release', app)}{config(P['widgetDebug'], 'Debug', widget)}{config(P['widgetRelease'], 'Release', widget)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{configlist(P['projConfigList'], P['projDebug'], P['projRelease'])}{configlist(P['appConfigList'], P['appDebug'], P['appRelease'])}{configlist(P['widgetConfigList'], P['widgetDebug'], P['widgetRelease'])}/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
\t\t{P['pkgRef']} /* XCLocalSwiftPackageReference "JisiKit" */ = {{
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = JisiKit;
\t\t}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{P['appPkgDep']} /* JisiKit */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = JisiKit;
\t\t}};
\t\t{P['widgetPkgDep']} /* JisiKit */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = JisiKit;
\t\t}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {P['project']} /* Project object */;
}}
"""

proj = os.path.join(root, "JisiBuddy.xcodeproj")
os.makedirs(os.path.join(proj, "xcshareddata", "xcschemes"), exist_ok=True)
open(os.path.join(proj, "project.pbxproj"), "w").write(out)

def ref(tid, name, product):
    return f"""<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{tid}" BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:JisiBuddy.xcodeproj">
         </BuildableReference>"""

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
         {ref(P['appTarget'], 'JisiApp', 'JisiBuddy.app')}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref(P['appTarget'], 'JisiApp', 'JisiBuddy.app')}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
open(os.path.join(proj, "xcshareddata", "xcschemes", "JisiApp.xcscheme"), "w").write(scheme)
print("written", proj)
