#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint clipshot.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'clipshot'
  s.version          = '0.1.1'
  s.summary          = 'Extract still image frames from local video files.'
  s.description      = <<-DESC
Clipshot extracts JPEG or PNG thumbnail files from local videos on iOS.
                       DESC
  s.homepage         = 'https://prabhatpandey.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Prabhat Pandey' => 'prabhatsdp@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks = 'AVFoundation', 'UIKit'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'clipshot_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
