Pod::Spec.new do |s|
  s.name             = 'Clickzin_iOS_Tracking'
  s.version          = '0.2.0'
  s.summary          = 'Tracking SDK'
  s.description      = <<-DESC
                       Tracking SDK
                       DESC
  s.homepage         = 'https://github.com/skingithub/clickzin_iOS_tracking.git'
  s.license          = 'MIT'
  s.source           = { :git => 'https://github.com/skingithub/clickzin_iOS_tracking.git', :tag => s.version.to_s }
  s.platform         = :ios, '12.0'
  s.source_files     = 'Clickzin_iOS_tracking/**/*.{swift}'
  s.author = "skingithub"
  s.swift_version    = '5.0'
end