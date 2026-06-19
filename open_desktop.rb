winApp = '/Applications/Windows App.app/Contents/MacOS/Windows App'

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

if !ARGV[0].empty?
  query = ARGV[0]
  export_bookmark(query, winApp)
else
  warn 'No bookmark ID received from Alfred, exiting...'
  exit(1)
end
