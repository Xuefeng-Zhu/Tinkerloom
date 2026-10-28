Pod::Spec.new do |s|
  s.name           = 'TinkerloomDevice'
  s.version        = '0.1.0'
  s.summary        = 'Consent-scoped Tinkerloom device controls'
  s.description    = 'Fixed torch, window brightness and keep-awake controls with native lifecycle restoration.'
  s.author         = 'Tinkerloom contributors'
  s.homepage       = 'https://docs.expo.dev/modules/'
  s.platforms      = {
    :ios => '16.4'
  }
  s.source         = { path: '.' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
