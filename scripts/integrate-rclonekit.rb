#!/usr/bin/env ruby
# scripts/integrate-rclonekit.rb
#
# Adds Frameworks/RcloneKit.xcframework to the main app target with:
#   - Link Binary With Libraries
#   - Embed Frameworks (Embed & Sign)
#   - FRAMEWORK_SEARCH_PATHS = $(SRCROOT)/Frameworks
#
# Idempotent: safe to run multiple times.
#
# Requires: gem install xcodeproj  (already present at version 1.27.0)
#
# Usage: ruby scripts/integrate-rclonekit.rb

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../Rclone GUI.xcodeproj', __dir__)
TARGET_NAME = 'Rclone GUI'
XCFRAMEWORK_REL = 'Frameworks/RcloneKit.xcframework'

abort "ERROR: project not found at #{PROJECT_PATH}" unless File.exist?(PROJECT_PATH)
xcframework_abs = File.expand_path("../#{XCFRAMEWORK_REL}", __dir__)
abort "ERROR: xcframework not found at #{xcframework_abs}" unless File.exist?(xcframework_abs)

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == TARGET_NAME }
abort "ERROR: target '#{TARGET_NAME}' not found" unless target

# 1. Add the xcframework as a file reference in a 'Frameworks' group
frameworks_group = project.main_group['Frameworks'] || project.main_group.new_group('Frameworks', 'Frameworks')

# Remove any prior bad refs (created with double-Frameworks path bug)
frameworks_group.files.dup.each do |f|
    if f.path&.include?('RcloneKit.xcframework')
        f.remove_from_project
    end
end
file_ref = frameworks_group.new_file('RcloneKit.xcframework')
file_ref.source_tree = 'SOURCE_ROOT'
file_ref.path = 'Frameworks/RcloneKit.xcframework'
file_ref.last_known_file_type = 'wrapper.xcframework'
puts '[ok] file reference rewired (path=Frameworks/RcloneKit.xcframework, source_tree=SOURCE_ROOT)'

# 2. Link Binary With Libraries
frameworks_phase = target.frameworks_build_phase
unless frameworks_phase.files_references.include?(file_ref)
    frameworks_phase.add_file_reference(file_ref)
    puts '[ok] linked in Frameworks build phase'
else
    puts '[ok] already linked in Frameworks build phase'
end

# 3. Embed Frameworks (Embed & Sign)
embed_phase = target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :frameworks }
unless embed_phase
    embed_phase = target.new_copy_files_build_phase('Embed Frameworks')
    embed_phase.symbol_dst_subfolder_spec = :frameworks
    puts '[ok] created Embed Frameworks copy phase'
end

embed_build_file = embed_phase.files.find { |bf| bf.file_ref == file_ref }
unless embed_build_file
    embed_build_file = embed_phase.add_file_reference(file_ref)
    puts '[ok] added xcframework to Embed Frameworks phase'
else
    puts '[ok] xcframework already in Embed Frameworks phase'
end
# settings: CodeSignOnCopy + RemoveHeadersOnCopy
embed_build_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }

# 4. Build settings: FRAMEWORK_SEARCH_PATHS
target.build_configurations.each do |config|
    paths = Array(config.build_settings['FRAMEWORK_SEARCH_PATHS']) || []
    paths = [paths] unless paths.is_a?(Array)
    paths = paths.compact
    needed = '$(SRCROOT)/Frameworks'
    inherited = '$(inherited)'
    unless paths.include?(needed)
        paths << inherited unless paths.include?(inherited)
        paths << needed
        config.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths
        puts "[ok] FRAMEWORK_SEARCH_PATHS updated for config '#{config.name}'"
    end
end

# 5. Save
project.save
puts '==> integrate-rclonekit.rb done. Open Xcode and rebuild.'
