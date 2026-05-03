#!/usr/bin/env ruby
#
# Configures the iOS WidgetKit target for Trackora.
# Run from the repo root:  ruby tool/configure_widget_target.rb
#
# Idempotent - safe to run multiple times.

require 'xcodeproj'

project_path = File.expand_path('ios/Runner.xcodeproj', __dir__ + '/..')
project = Xcodeproj::Project.open(project_path)

RUNNER = 'Runner'
WIDGET = 'TrackoraWidget'

WIDGET_BUNDLE = 'com.michaelchia.trackora.TrackoraWidget'
WIDGET_ENT = 'TrackoraWidget/TrackoraWidget.entitlements'
WIDGET_INFO = 'TrackoraWidget/Info.plist'
WIDGET_SWIFT = 'TrackoraWidget.swift'
WIDGET_INTENT_SWIFT = 'QuickAddExpenseIntent.swift'

runner = project.targets.find { |target| target.name == RUNNER }
abort 'Runner target missing' unless runner

team = runner.build_configurations
             .map { |config| config.build_settings['DEVELOPMENT_TEAM'] }
             .compact
             .first

widget = project.targets.find { |target| target.name == WIDGET }
unless widget
  widget = project.new_target(:app_extension, WIDGET, :ios, '14.0')
  puts "Created #{WIDGET} target"
end

main_group = project.main_group
widget_group = main_group.children.find { |child| child.display_name == WIDGET }
widget_group ||= main_group.new_group(WIDGET, WIDGET)

def ensure_file(group, path, file_type)
  file = group.children.find { |child| child.respond_to?(:path) && child.path == path }
  file ||= group.new_file(path)
  file.last_known_file_type = file_type
  file
end

swift_ref = ensure_file(widget_group, WIDGET_SWIFT, 'sourcecode.swift')
intent_ref = ensure_file(widget_group, WIDGET_INTENT_SWIFT, 'sourcecode.swift')
ensure_file(widget_group, 'Info.plist', 'text.plist.xml')
ensure_file(widget_group, 'TrackoraWidget.entitlements', 'text.plist.entitlements')

[swift_ref, intent_ref].each do |ref|
  next if widget.source_build_phase.files_references.include?(ref)
  widget.source_build_phase.add_file_reference(ref)
  puts "Linked #{ref.path} to #{WIDGET} sources"
end

widget.frameworks_build_phase.files_references.each do |ref|
  next unless ref.display_name == 'Foundation.framework'

  ref.source_tree = 'SDKROOT'
  ref.path = 'System/Library/Frameworks/Foundation.framework'
end

if widget.product_reference
  widget.product_reference.path = "#{WIDGET}.appex"
  widget.product_reference.explicit_file_type = 'wrapper.app-extension'
end

widget.build_configurations.each do |config|
  settings = config.build_settings
  settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  settings['CODE_SIGN_ENTITLEMENTS'] = WIDGET_ENT
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['CURRENT_PROJECT_VERSION'] ||= '1'
  settings['DEVELOPMENT_TEAM'] = team if team
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['INFOPLIST_FILE'] = WIDGET_INFO
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
  settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks',
  ]
  settings['MARKETING_VERSION'] ||= '1.0'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = WIDGET_BUNDLE
  settings['PRODUCT_BUNDLE_PACKAGE_TYPE'] = 'XPC!'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SDKROOT'] = 'iphoneos'
  settings['SKIP_INSTALL'] = 'YES'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  puts "  ✓ #{WIDGET} [#{config.name}]"
end

embed_phase = runner.copy_files_build_phases.find do |phase|
  phase.name == 'Embed App Extensions'
end
embed_phase ||= runner.new_copy_files_build_phase('Embed App Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_phase.dst_path = ''

unless embed_phase.files_references.include?(widget.product_reference)
  build_file = embed_phase.add_file_reference(widget.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts "Embedded #{WIDGET}.appex in Runner"
end

runner.add_dependency(widget) unless runner.dependencies.any? { |dep| dep.target == widget }

# Break the Flutter + WidgetKit dependency cycle.
#
# Flutter ships a "Thin Binary" run-script phase that mutates Runner.app
# (it processes Info.plist among other things). When Xcode also has a
# Copy-Files phase that drops TrackoraWidget.appex into Runner.app/PlugIns
# *after* Thin Binary, both phases end up writing into the same Runner.app
# directory and Xcode flags a build cycle:
#
#   Thin Binary → Runner.app/Info.plist
#   Copy        → Runner.app/PlugIns/TrackoraWidget.appex
#   CodeSign    ← reads Runner.app
#
# Moving "Embed App Extensions" to run BEFORE "Thin Binary" puts the
# appex in place first, then Thin Binary runs cleanly. This is the
# Flutter + extension community fix; idempotent.
phases = runner.build_phases
embed_idx = phases.index(embed_phase)
thin_idx = phases.index do |phase|
  phase.respond_to?(:name) && phase.name == 'Thin Binary'
end
if embed_idx && thin_idx && embed_idx > thin_idx
  phases.delete_at(embed_idx)
  phases.insert(thin_idx, embed_phase)
  puts 'Reordered: Embed App Extensions now runs before Thin Binary'
end

attributes = project.root_object.attributes
attributes['TargetAttributes'] ||= {}
attributes['TargetAttributes'][widget.uuid] ||= {}
attributes['TargetAttributes'][widget.uuid]['CreatedOnToolsVersion'] ||= '15.0'

project.save
puts "Done. Saved #{project_path}"
