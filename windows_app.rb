# frozen_string_literal: true

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

  # Pass valid: false for informational rows that shouldn't action.
  def add_item(title:, subtitle: '', arg: nil, valid: true)
    @items << {
      title: title,
      subtitle: subtitle,
      arg: arg || title,
      autocomplete: title,
      valid: valid,
      icon: { path: 'icon.png' }
    }
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
    username, rest = split_username(query.to_s.strip)
    host, port = split_host_port(rest)
    return nil if host.empty?

    { username: username, host: host, port: port }
  end

  # Split a leading "user@" off, returning [username_or_nil, rest].
  def split_username(text)
    return [nil, text] unless text.include?('@')

    username, rest = text.split('@', 2)
    [username.empty? ? nil : username, rest]
  end

  # Split a trailing ":port" off, returning [host, port_or_nil].
  def split_host_port(text)
    host, _, port = text.rpartition(':')
    return [port, nil] if host.empty? # no ':' present; rpartition put it all in `port`

    [host, port.empty? ? nil : port]
  end

  # Build the rdp:// URI from parsed parts: the app's default attribute set plus
  # the substituted full address (with optional port) and username. Username is
  # omitted when nil so Windows App prompts for credentials.
  def build_uri(username:, host:, port:)
    params = DEFAULT_PARAMS.dup
    params << "full address:s:#{port ? "#{host}:#{port}" : host}"
    params << "username:s:#{username}" if username

    "rdp://#{params.map { |line| encode_param(line) }.join('&')}"
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
  # Where the app installs by default; also the fallback for error messages.
  STANDARD_PATH = '/Applications/Windows App.app/Contents/MacOS/Windows App'
  # Windows App kept Microsoft Remote Desktop's bundle identifier.
  BUNDLE_ID = 'com.microsoft.rdc.macos'

  def initialize(path = self.class.resolve_path)
    @path = path
  end

  # Locate the Windows App executable, preferring speed: the Script Filter runs
  # this on every keystroke, so we avoid subprocesses in the common case.
  #   1. WINDOWS_APP override (e.g. the test stub)
  #   2. the standard /Applications path, if present (a plain stat)
  #   3. a Spotlight lookup by bundle id (handles ~/Applications, renames)
  #   4. the standard path as a last resort, so errors name a real location
  def self.resolve_path
    env = ENV.fetch('WINDOWS_APP', nil)
    return env if env && !env.empty?
    return STANDARD_PATH if File.executable?(STANDARD_PATH)

    locate_via_spotlight || STANDARD_PATH
  end

  # The executable inside the first installed Windows App bundle Spotlight knows
  # about, or nil. Reads CFBundleExecutable so a future rename still resolves.
  def self.locate_via_spotlight
    capture('mdfind', "kMDItemCFBundleIdentifier == '#{BUNDLE_ID}'")
      .each_line
      .map(&:strip)
      .reject(&:empty?)
      .map { |bundle| File.join(bundle, 'Contents', 'MacOS', bundle_executable(bundle)) }
      .find { |exe| File.executable?(exe) }
  end

  def self.bundle_executable(bundle)
    name = capture('defaults', 'read', "#{bundle}/Contents/Info", 'CFBundleExecutable').strip
    name.empty? ? 'Windows App' : name
  end

  # Run a command (no shell, so arguments need no escaping) and return its
  # stdout; stderr is discarded and failures yield ''.
  def self.capture(*command)
    IO.popen(command, err: File::NULL, &:read) || ''
  rescue SystemCallError
    ''
  end

  # Saved bookmarks as CSV rows of [name, id].
  def bookmarks
    CSV.parse(run('--script', 'bookmark', 'list'))
  rescue StandardError => e
    abort "Couldn't list bookmarks from '#{@path}': #{e.inspect}"
  end

  # The rdp:// URI for a saved bookmark id.
  def export_uri(id)
    run('--script', 'bookmark', 'export', id, '--uri')
  rescue StandardError => e
    abort "Couldn't export bookmark #{id.inspect} from '#{@path}': #{e.inspect}"
  end

  # Hand an rdp:// URI to Windows App.
  def open_uri(uri)
    system(*open_command(uri))
  rescue StandardError => e
    abort "Couldn't open #{uri.strip} in Windows App (#{BUNDLE_ID}); is it installed? #{e.inspect}"
  end

  # The `open` invocation. `-b <bundle id>` forces Windows App rather than
  # whatever app is registered for the rdp:// scheme. The extra slash gives the
  # URL an empty authority so the query string isn't parsed as a host.
  def open_command(uri)
    ['open', '-b', BUNDLE_ID, uri.strip.sub('rdp://', 'rdp:///')]
  end

  private

  # Run the Windows App binary with args (no shell) and return its stdout.
  def run(*args)
    IO.popen([@path, *args], &:read)
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
      abort 'No bookmark ID or target received from Alfred, exiting...'
    elsif arg.start_with?('adhoc:')
      @app.open_uri(adhoc_uri(arg))
    else
      @app.open_uri(@app.export_uri(arg))
    end
  end

  private

  # Build the rdp:// URI for an "adhoc:<target>" token. We receive the bare
  # target (not a pre-built URI) so the URI's "&"/"%" characters are produced
  # here rather than passing through Alfred's argument handling, which mangles
  # them.
  def adhoc_uri(arg)
    RemoteTarget.uri_for(arg.delete_prefix('adhoc:')) ||
      abort("Could not parse ad-hoc target from #{arg.inspect}, exiting...")
  end

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

    target = query.strip
    if RemoteTarget.parse(query)
      # Offer a direct ad-hoc connection alongside any matching bookmarks.
      feedback.add_item(title: "Connect to #{target}", subtitle: 'Open ad-hoc desktop',
                        arg: "adhoc:#{target}")
    elsif bookmarks.empty?
      feedback.add_item(title: 'No matching desktop found', subtitle: "Can't open desktop",
                        arg: '##notfound##', valid: false)
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
    abort "Usage: #{$PROGRAM_NAME} {list|open} <arg>"
  end
end
