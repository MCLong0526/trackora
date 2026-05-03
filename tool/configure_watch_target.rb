#!/usr/bin/env ruby
#
# Configures the iOS + watchOS Xcode targets for App Group sharing.
# Run from the repo root:  ruby tool/configure_watch_target.rb
#
# Idempotent — safe to run multiple times.

require 'xcodeproj'

project_path = File.expand_path('ios/Runner.xcodeproj', __dir__ + '/..')
project = Xcodeproj::Project.open(project_path)

RUNNER = 'Runner'
WATCH = 'TrackoraWatch Watch App'

RUNNER_ENT = 'Runner/Runner.entitlements'
WATCH_ENT  = 'TrackoraWatch Watch App/TrackoraWatch.entitlements'
WATCH_INFO = 'TrackoraWatch Watch App/Info.plist'
COMPANION_BUNDLE = 'com.michaelchia.trackora'

def patch_settings(target, label)
  target.build_configurations.each do |config|
    yield config
    puts "  ✓ #{label} [#{config.name}]"
  end
end

runner = project.targets.find { |t| t.name == RUNNER }
watch  = project.targets.find { |t| t.name == WATCH }

abort 'Runner target missing' unless runner
abort "Watch target '#{WATCH}' missing" unless watch

puts 'Runner: linking Runner.entitlements'
patch_settings(runner, 'CODE_SIGN_ENTITLEMENTS') do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = RUNNER_ENT
end

puts "\nTrackoraWatch Watch App: linking TrackoraWatch.entitlements"
patch_settings(watch, 'CODE_SIGN_ENTITLEMENTS') do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = WATCH_ENT
end

puts "\nTrackoraWatch Watch App: setting WKCompanionAppBundleIdentifier"
patch_settings(watch, 'INFOPLIST_KEY_WKCompanionAppBundleIdentifier') do |config|
  config.build_settings['INFOPLIST_KEY_WKCompanionAppBundleIdentifier'] =
    COMPANION_BUNDLE
end

# If the watch target uses a custom Info.plist, point at it. Otherwise rely on
# generated keys (we already set WKCompanionAppBundleIdentifier above).
puts "\nTrackoraWatch Watch App: lowering WATCHOS_DEPLOYMENT_TARGET"
[watch, *project.targets.select { |t| t.name.start_with?('TrackoraWatch Watch App') }].uniq.each do |target|
  patch_settings(target, 'WATCHOS_DEPLOYMENT_TARGET=10.0 (' + target.name + ')') do |config|
    config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '10.0'
  end
end

puts "\nTrackoraWatch Watch App: ensuring Info.plist key is set"
patch_settings(watch, 'INFOPLIST_KEY_CFBundleDisplayName') do |config|
  config.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] ||= 'Trackora'
end

# Swift 6 "MemberImportVisibility" upcoming feature breaks SwiftUI's transitive
# availability annotations on watchOS — every iOS-tagged API ends up flagged
# as unavailable. Turn it off for the watch target and its tests.
puts "\nTrackoraWatch Watch App: disabling MemberImportVisibility upcoming feature"
[watch, *project.targets.select { |t| t.name.start_with?('TrackoraWatch Watch App') }].uniq.each do |target|
  patch_settings(target, 'SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY=NO (' + target.name + ')') do |config|
    config.build_settings['SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY'] = 'NO'
  end
end


# Flutter's iOS build invokes `xcodebuild -sdk iphoneos`, which forces the
# watch target to compile with the iOS SDK and breaks watchOS-only APIs
# (digitalCrownRotation, etc.). Detach the watch from Runner so `flutter run`
# only builds the iPhone app. The watch app is installed separately via the
# TrackoraWatch scheme in Xcode (works fine for dev). Re-attach before App
# Store submission.
puts "\nRunner: detaching watch from Embed phase + dependencies"
embed_phase = runner.build_phases.find do |p|
  p.respond_to?(:name) && p.name == 'Embed Watch Content'
end
if embed_phase
  before = embed_phase.files.length
  embed_phase.files.delete_if do |f|
    ref = f.file_ref
    ref && ref.path && ref.path.include?('TrackoraWatch Watch App.app')
  end
  puts "  ✓ removed #{before - embed_phase.files.length} watch file(s) from Embed Watch Content"
end

runner.dependencies.delete_if do |dep|
  dep.target == watch
end
puts '  ✓ removed TrackoraWatch from Runner.dependencies'

project.save
puts "\nDone. Saved #{project_path}"
