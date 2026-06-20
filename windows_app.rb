require 'json'
require 'csv'
require 'cgi'

# Single-file Alfred workflow for Windows App (formerly Microsoft Remote
# Desktop). Alfred invokes it with a subcommand:
#   ruby windows_app.rb list "{query}"   # Script Filter: list/search bookmarks
#   ruby windows_app.rb open "{query}"   # Action: open a bookmark or ad-hoc host
# The dispatch at the bottom only runs when the file is executed directly, so the
# test suite can require it to exercise RemoteTarget in isolation.

# Builds the Script Filter JSON that Alfred expects back from a workflow input.
# https://www.alfredapp.com/help/workflows/inputs/script-filter/json/
class Feedback
  attr_accessor :items

  def initialize
    @items = []
  end

  def add_item(opts = {})
    return if opts[:title].nil?

    item = {
      title: opts[:title],
      subtitle: opts[:subtitle] || '',
      arg: opts[:arg] || opts[:title],
      autocomplete: opts[:autocomplete] || opts[:title],
      # Default to actionable; pass valid: false for informational rows.
      valid: opts.fetch(:valid, true),
      icon: { path: opts.dig(:icon, :name) || 'icon.png' }
    }
    item[:icon][:type] = 'fileicon' if opts.dig(:icon, :type) == 'fileicon'
    item[:type] = 'file' if opts[:type] == 'file'

    @items << item
  end

  # No uid is emitted: Alfred preserves the order items are returned in only
  # when uid is absent, which keeps the bookmarks in the app's own order.
  def to_json(*_args)
    JSON.pretty_generate(items: @items)
  end
end

# Parses an ad-hoc remote target typed into the `rdp` keyword (e.g.
# "me@192.168.4.3:3390") and builds the rdp:// URI Windows App opens. This is
# the same URI shape the app's `--script bookmark export --uri` emits, so the
# result flows through the existing open path unchanged.
module RemoteTarget
  module_function

  # Windows App rejects a minimal "full address + username" URI with "The URL is
  # not valid"; it only accepts the full attribute set its own bookmark export
  # emits. These are those defaults (the app's `--script bookmark export`, minus
  # the per-connection identity fields we substitute: full address, username,
  # domain), as "key:type:value" lines. build_uri appends the substituted fields
  # after these.
  DEFAULT_PARAMS = <<~PARAMS.lines.map(&:chomp).reject(&:empty?).freeze
    administrative session:i:0
    allow font smoothing:i:1
    allowed security protocols:s:*
    allowrelativemousemode:i:0
    alternate shell:s:
    armpath:s:
    audiocapturemode:i:0
    audiomode:i:0
    authentication level:i:2
    authoring tool:s:
    autoreconnection enabled:i:1
    bandwidthautodetect:i:1
    camerastoredirect:s:
    connect to console:i:0
    connection type:i:7
    desktopheight:i:0
    desktopwidth:i:0
    disable cursor setting:i:0
    disable cursor settings:i:0
    disable full window drag:i:1
    disable menu anims:i:1
    disable themes:i:0
    disable wallpaper:i:0
    drivestoredirect:s:*
    dynamic resolution:i:1
    enablecredsspsupport:i:1
    enablerdsaadauth:i:0
    forcehidpioptimizations:i:1
    gatewayaccesstoken:s:
    gatewaybrokeringtype:i:0
    gatewaycertificatelogonauthority:s:
    gatewayhostname:s:
    gatewayusagemethod:i:2
    gatewayusername:s:
    geo:s:
    hubdiscoverygeourl:s:
    loadbalanceinfo:s:
    networkautodetect:i:1
    prompt for credentials on client:i:0
    promptcredentialonce:i:0
    redirectclipboard:i:1
    redirectcomports:i:0
    redirected video capture encoding quality:i:0
    redirectlocation:i:0
    redirectprinters:i:0
    redirectsmartcards:i:0
    redirectwebauthn:i:1
    remoteapplicationappid:s:
    remoteapplicationcmdline:s:
    remoteapplicationmode:i:0
    remoteapplicationname:s:
    remoteapplicationprogram:s:
    resourceprovider:s:
    screen mode id:i:1
    session bpp:i:32
    shell working directory:s:
    smart sizing:i:1
    smartrawprinters:s:
    targetisaadjoined:i:0
    use multimon:i:0
    use redirection server name:i:0
    wvd endpoint pool:s:
  PARAMS

  # Parse "[user@]host[:port]" into its parts, or nil when there is no host.
  def parse(query)
    rest = query.to_s.strip
    return nil if rest.empty?

    username = nil
    if rest.include?('@')
      username, rest = rest.split('@', 2)
      username = nil if username.empty?
    end

    host, _, port = rest.rpartition(':')
    if host.empty? # no ':' present, so rpartition put everything in `port`
      host = port
      port = nil
    end
    port = nil if port && port.empty?

    return nil if host.empty?

    { username: username, host: host, port: port }
  end

  # Build the rdp:// URI from parsed parts: the app's default attribute set plus
  # the substituted full address (with optional port) and username. Username is
  # omitted when nil so Windows App prompts for credentials.
  def build_uri(username:, host:, port:)
    params = DEFAULT_PARAMS.dup
    params << "full address:s:#{port ? "#{host}:#{port}" : host}"
    params << "username:s:#{username}" if username

    'rdp://' + params.map { |line| encode_param(line) }.join('&')
  end

  # Encode one "key:type:value" line as `key=type%3Avalue`, matching the app's
  # export: spaces in the key become %20; the rest is URL-encoded (so the type
  # separator and any value colons become %3A).
  def encode_param(line)
    key, rest = line.split(':', 2)
    "#{key.gsub(' ', '%20')}=#{CGI.escape(rest)}"
  end

  # Convenience: parse a query and build its URI in one step, or nil when the
  # query is not a usable target.
  def uri_for(query)
    parts = parse(query)
    parts && build_uri(**parts)
  end
end

# Adapter over the Windows App binary and the OS `open` command. Set WINDOWS_APP
# to point at any executable that speaks the same `--script bookmark` interface
# (e.g. test/fake-windows-app).
class WindowsApp
  def initialize(path = ENV.fetch('WINDOWS_APP', '/Applications/Windows App.app/Contents/MacOS/Windows App'))
    @path = path
  end

  # Saved bookmarks as CSV rows of [name, id].
  def bookmarks
    CSV.parse(`'#{@path}' --script bookmark list`)
  rescue StandardError => e
    warn "Something went wrong while exporting the bookmark list from app '#{@path}'."
    warn 'Please see the exception below: '
    warn e.inspect
    exit(1)
  end

  # The rdp:// URI for a saved bookmark id.
  def export_uri(id)
    `'#{@path}' --script bookmark export #{id} --uri`
  rescue StandardError => e
    warn "Something went wrong while exporting the bookmark with ID #{id} from app #{@path}."
    warn 'Please see the exception below: '
    warn e.inspect
    exit(1)
  end

  # Hand an rdp:// URI to Windows App. `open` needs an empty authority
  # (rdp:///…) for the query string to route correctly.
  def open_uri(uri)
    `open '#{uri.strip.gsub('rdp://', 'rdp:///')}'`
  rescue StandardError => e
    warn "Something went wrong while calling \"open #{uri.strip}\"."
    warn "Perhaps Windows App is not registered to open 'rdp://' uris?"
    warn 'Please see the exception below: '
    warn e.inspect
    exit(1)
  end
end

# The two Alfred entry points: `list` (Script Filter) and `open` (Action).
class Workflow
  def initialize(app = WindowsApp.new)
    @app = app
  end

  # Return the Script Filter JSON for a search query. An empty query matches
  # every bookmark (include?('') is always true), so the keyword alone lists
  # them all.
  def list(query)
    matches = find_bookmarks(@app.bookmarks, query.downcase)
    build_feedback(matches, query)
  end

  # Open the selected item: an "adhoc:<target>" token or a saved bookmark id.
  def open(arg)
    if arg.nil? || arg.empty?
      warn 'No bookmark ID or target received from Alfred, exiting...'
      exit(1)
    elsif arg.start_with?('adhoc:')
      # Ad-hoc target like "adhoc:me@192.168.4.3:3390": build the rdp:// URI
      # here (rather than receiving a pre-built URI through Alfred) and open it
      # directly, without a bookmark lookup.
      uri = RemoteTarget.uri_for(arg.delete_prefix('adhoc:'))
      if uri.nil?
        warn "Could not parse ad-hoc target from #{arg.inspect}, exiting..."
        exit(1)
      end
      @app.open_uri(uri)
    else
      @app.open_uri(@app.export_uri(arg))
    end
  end

  private

  def find_bookmarks(bookmark_list, query)
    bookmark_list.find_all { |bookmark| bookmark[0].downcase.include?(query) }
  end

  # `query` is the raw (non-downcased) search text so an ad-hoc connect target
  # keeps the username's original case. `bookmarks` are the matching saved
  # bookmarks (already filtered).
  def build_feedback(bookmarks, query)
    feedback = Feedback.new
    bookmarks.each do |bookmark|
      feedback.add_item(title: bookmark[0], subtitle: 'Open desktop', arg: bookmark[1].strip)
    end

    # When the query parses as [user@]host[:port], offer a direct ad-hoc
    # connection alongside any matching bookmarks. The arg is an "adhoc:" token
    # carrying the raw target; #open builds the rdp:// URI from it. We pass the
    # target rather than a pre-built URI so the URI's "&"/"%" characters never
    # travel through Alfred's argument handling, which mangles them.
    target = query.strip
    feedback.add_item(title: "Connect to #{target}", subtitle: 'Open ad-hoc desktop', arg: "adhoc:#{target}") if RemoteTarget.parse(query)

    if bookmarks.empty? && RemoteTarget.parse(query).nil?
      feedback.add_item(title: 'No matching desktop found', subtitle: "Can't open desktop", arg: '##notfound##', valid: false)
    end

    feedback.to_json
  end
end

# --- dispatch (only when run directly, not when required by the tests) ---

if $PROGRAM_NAME == __FILE__
  workflow = Workflow.new
  case ARGV[0]
  when 'list'
    puts workflow.list(ARGV[1] || '')
  when 'open'
    workflow.open(ARGV[1])
  else
    warn "Usage: #{$PROGRAM_NAME} {list|open} <arg>"
    exit(1)
  end
end
