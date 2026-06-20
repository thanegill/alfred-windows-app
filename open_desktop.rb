require './remote_target'

# Defaults to the real app; set WINDOWS_APP to point at any executable that
# speaks the same `--script bookmark` interface (e.g. test/fake-windows-app).
winApp = ENV.fetch('WINDOWS_APP', '/Applications/Windows App.app/Contents/MacOS/Windows App')

def export_bookmark(query, winApp)
  begin
    bookmark_uri = `'#{winApp}' --script bookmark export #{query} --uri`
  rescue StandardError => e
    warn "Something went wrong while exporting the bookmark with ID #{query} from app #{winApp}."
    warn 'Please see the exception below: '
    warn e.inspect
    exit(1)
  end
  open_rdp_uri(bookmark_uri)
end

def open_rdp_uri(bookmark_uri)
  `open '#{bookmark_uri.strip.gsub('rdp://', 'rdp:///')}'`
rescue StandardError => e
  warn "Something went wrong while while calling \"open #{bookmark_uri.strip}\"."
  warn "Perhaps Windows App is not registered to open 'rdp://' uris?"
  warn 'Please see the exception below: '
  warn e.inspect
  exit(1)
end

if ARGV[0].nil? || ARGV[0].empty?
  warn 'No bookmark ID or target received from Alfred, exiting...'
  exit(1)
elsif ARGV[0].start_with?('adhoc:')
  # Ad-hoc target like "adhoc:me@192.168.4.3:3390": build the rdp:// URI here
  # (rather than receiving a pre-built URI through Alfred) and open it directly,
  # without a bookmark lookup.
  uri = RemoteTarget.uri_for(ARGV[0].delete_prefix('adhoc:'))
  if uri.nil?
    warn "Could not parse ad-hoc target from #{ARGV[0].inspect}, exiting..."
    exit(1)
  end
  open_rdp_uri(uri)
else
  export_bookmark(ARGV[0], winApp)
end
