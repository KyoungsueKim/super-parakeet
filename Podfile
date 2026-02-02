ios_min_version = '15.5'
platform :ios, ios_min_version

target 'super-parakeet' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for super-parakeet
  pod "Alamofire"
  pod 'Google-Mobile-Ads-SDK'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = ios_min_version
    end
  end
end
