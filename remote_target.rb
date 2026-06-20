require 'cgi'

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
