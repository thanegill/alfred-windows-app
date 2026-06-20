require './alfred_feedback'
require './remote_target'
require 'csv'

# Defaults to the real app; set WINDOWS_APP to point at any executable that
# speaks the same `--script bookmark` interface (e.g. test/fake-windows-app).
winApp = ENV.fetch('WINDOWS_APP', '/Applications/Windows App.app/Contents/MacOS/Windows App')

def export_bookmark_list(winApp)
  raw_bookmarks = `'#{winApp}' --script bookmark list`
  CSV.parse(raw_bookmarks)
rescue StandardError => e
  warn "Something went wrong while exporting the bookmark list from app '#{winApp}'."
  warn 'Please see the exception below: '
  warn e.inspect
  exit(1)
end

def find_bookmarks(bookmark_list, query)
  bookmark_list.find_all { |bookmark| bookmark[0].downcase.include?(query) }
end

# `query` is the raw (non-downcased) search text so an ad-hoc connect target
# keeps the username's original case. `bookmarks` are the matching saved
# bookmarks (already filtered).
def generate_feedback(bookmarks, query)
  feedback = Feedback.new
  bookmarks.each do |bookmark|
    feedback.add_item({ title: bookmark[0], subtitle: 'Open desktop', arg: bookmark[1].strip })
  end

  # When the query parses as [user@]host[:port], offer a direct ad-hoc
  # connection alongside any matching bookmarks. The arg is an "adhoc:" token
  # carrying the raw target; open_desktop.rb builds the rdp:// URI from it. We
  # pass the target rather than a pre-built URI so the URI's "&"/"%" characters
  # never travel through Alfred's argument handling, which mangles them.
  target = query.strip
  feedback.add_item({ title: "Connect to #{target}", subtitle: 'Open ad-hoc desktop', arg: "adhoc:#{target}" }) if RemoteTarget.parse(query)

  if bookmarks.empty? && RemoteTarget.parse(query).nil?
    feedback.add_item({ title: 'No matching desktop found', subtitle: "Can't open desktop", arg: '##notfound##', valid: false })
  end

  puts feedback.to_json
end

# An empty query matches every bookmark (include?('') is always true), so when
# Alfred sends no search text we show the full list rather than bailing out.
query = ARGV[0] || ''
bookmark_list = export_bookmark_list(winApp)
bookmarks = find_bookmarks(bookmark_list, query.downcase)
generate_feedback(bookmarks, query)