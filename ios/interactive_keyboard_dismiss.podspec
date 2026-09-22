Pod::Spec.new do |s|
  s.name             = 'interactive_keyboard_dismiss'
  s.version          = '0.1.0'
  s.summary          = 'Interactive, finger-tracking keyboard dismissal for Flutter scroll views.'
  s.description      = <<-DESC
Moves the real iOS keyboard with the user's finger when a Flutter scroll view is
dragged into it, then dismisses or restores it with a spring on release.
                       DESC
  s.homepage         = 'https://github.com/Manish1Pandey/interactive_keyboard_dismiss'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Manish Kumar Panday'
  s.source           = { :path => '.' }
  s.source_files     = 'interactive_keyboard_dismiss/Sources/interactive_keyboard_dismiss/**/*.swift'
  s.resource_bundles = { 'interactive_keyboard_dismiss_privacy' => ['interactive_keyboard_dismiss/Sources/interactive_keyboard_dismiss/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
