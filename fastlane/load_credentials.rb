# Loads WhisPaste's local, never-committed Fastlane credentials
# (~/.config/whispaste-ios-credentials/fastlane.env) into ENV before Appfile
# or Fastfile read any ENV.fetch(...) value.
#
# Required by both Appfile and Fastfile (in that order of definition, but
# Fastlane's own load order between the two isn't guaranteed, hence a shared,
# idempotent loader both can `require_relative` unconditionally).
#
# Silent no-op if the file is missing — ENV.fetch(...) in Appfile/Fastfile
# then raises its own clear "key not found" error rather than this loader
# guessing at a fallback.
credentials_file = File.expand_path('~/.config/whispaste-ios-credentials/fastlane.env')
if File.exist?(credentials_file)
  File.readlines(credentials_file).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')

    key, value = line.split('=', 2)
    ENV[key] = value if key && value
  end
end
