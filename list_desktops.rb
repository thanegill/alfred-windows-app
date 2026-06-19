require './alfred_feedback'
require 'csv'

winApp = '/Applications/Windows App.app/Contents/MacOS/Windows App'

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

def generate_feedback(bookmarks)
  feedback = Feedback.new
  if !bookmarks.empty?
    bookmarks.each do |bookmark|
      feedback.add_item({ title: bookmark[0], subtitle: 'Open desktop', arg: bookmark[1].strip })
    end
  else
    feedback.add_item({ title: 'No matching desktop found', subtitle: "Can't open desktop", arg: '##notfound##', valid: false })
  end
  puts feedback.to_json
end

# An empty query matches every bookmark (include?('') is always true), so when
# Alfred sends no search text we show the full list rather than bailing out.
query = (ARGV[0] || '').downcase
bookmark_list = export_bookmark_list(winApp)
bookmarks = find_bookmarks(bookmark_list, query)
generate_feedback(bookmarks)