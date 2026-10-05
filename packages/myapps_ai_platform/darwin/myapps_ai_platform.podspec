#
# MyApps-AI's bridge to Apple's Foundation Models framework.
# See doc/en-us/on-device-ai.md in the app repository.
#
Pod::Spec.new do |s|
  s.name             = 'myapps_ai_platform'
  s.version          = '0.4.0'
  s.summary          = 'On-device Foundation Models bridge for MyDevice!!!!!.'
  s.description      = <<-DESC
Answers the com.yuanzhe.myapps_ai/genai method channel with Apple's on-device
Foundation Models framework on iOS 26 and macOS 26 or later.
                       DESC
  s.homepage         = 'https://github.com/YuanZhe-99/MyApps-AI'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = { 'yuanzhe' => 'yuanzhe' }
  s.source           = { :path => '.' }
  s.source_files     = 'myapps_ai_platform/Sources/myapps_ai_platform/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  # Weak, so an app built with this plugin still launches on iOS 18 and
  # macOS 15 and earlier, where the framework does not exist. CI checks the
  # built binaries with `otool -l` for LC_LOAD_WEAK_DYLIB.
  s.weak_frameworks = 'FoundationModels'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
