# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require_relative '../windows_app'

class RemoteTargetTest < Minitest::Test
  # --- parse ---

  def test_parse_host_only
    assert_equal({ username: nil, host: 'host01', port: nil },
                 RemoteTarget.parse('host01'))
  end

  def test_parse_user_and_host
    assert_equal({ username: 'me', host: '192.168.4.3', port: nil },
                 RemoteTarget.parse('me@192.168.4.3'))
  end

  def test_parse_host_and_port
    assert_equal({ username: nil, host: '192.168.4.3', port: '3390' },
                 RemoteTarget.parse('192.168.4.3:3390'))
  end

  def test_parse_user_host_and_port
    assert_equal({ username: 'me', host: 'host01', port: '3390' },
                 RemoteTarget.parse('me@host01:3390'))
  end

  def test_parse_trims_surrounding_whitespace
    assert_equal({ username: 'me', host: 'host01', port: nil },
                 RemoteTarget.parse('  me@host01  '))
  end

  def test_parse_blank_returns_nil
    assert_nil RemoteTarget.parse('')
    assert_nil RemoteTarget.parse('   ')
  end

  def test_parse_at_without_host_returns_nil
    assert_nil RemoteTarget.parse('me@')
  end

  # --- build_uri ---
  #
  # Windows App rejects a minimal two-parameter URI ("The URL is not valid"), so
  # build_uri embeds full address / port / username into the app's full default
  # attribute set. We assert on the substituted segments rather than the whole
  # ~1700-char string.

  def test_build_uri_starts_with_rdp_scheme
    uri = RemoteTarget.build_uri(username: nil, host: 'host01', port: nil)
    assert uri.start_with?('rdp://'), uri
  end

  def test_build_uri_includes_default_params
    # A representative default attribute proves the full set is present.
    uri = RemoteTarget.build_uri(username: nil, host: 'host01', port: nil)
    assert_includes uri, 'audiomode=i%3A0'
  end

  def test_build_uri_includes_full_address
    uri = RemoteTarget.build_uri(username: nil, host: '192.168.4.3', port: nil)
    assert_includes uri, '&full%20address=s%3A192.168.4.3'
  end

  def test_build_uri_includes_port_in_full_address
    uri = RemoteTarget.build_uri(username: nil, host: 'host01', port: '3390')
    assert_includes uri, '&full%20address=s%3Ahost01%3A3390'
  end

  def test_build_uri_includes_username_when_present
    uri = RemoteTarget.build_uri(username: 'me', host: '192.168.4.3', port: nil)
    assert_includes uri, '&username=s%3Ame'
  end

  def test_build_uri_omits_username_when_absent
    uri = RemoteTarget.build_uri(username: nil, host: 'host01', port: nil)
    # NOTE: the default set contains "gatewayusername="; "&username=" is distinct.
    refute_includes uri, '&username='
  end

  # --- uri_for: parse + build in one step (nil for non-targets) ---

  def test_uri_for_builds_from_query
    uri = RemoteTarget.uri_for('me@192.168.4.3')
    assert_includes uri, '&full%20address=s%3A192.168.4.3'
    assert_includes uri, '&username=s%3Ame'
  end

  def test_uri_for_blank_returns_nil
    assert_nil RemoteTarget.uri_for('')
  end
end

# A stand-in WindowsApp so Workflow can be tested without the real binary or the
# OS `open`. Records the URIs it was asked to open.
class FakeApp
  attr_reader :opened, :exported_id, :bookmarks

  def initialize(bookmarks: [], export_uri: 'rdp://full%20address=s%3Ademo')
    @bookmarks = bookmarks
    @export_uri = export_uri
    @opened = []
  end

  def export_uri(id)
    @exported_id = id
    @export_uri
  end

  def open_uri(uri)
    @opened << uri
  end
end

class WindowsAppResolveTest < Minitest::Test
  def around_env
    saved = ENV.fetch('WINDOWS_APP', nil)
    ENV.delete('WINDOWS_APP')
    yield
  ensure
    saved.nil? ? ENV.delete('WINDOWS_APP') : ENV['WINDOWS_APP'] = saved
  end

  def test_env_override_wins
    around_env do
      ENV['WINDOWS_APP'] = '/custom/win'
      assert_equal '/custom/win', WindowsApp.resolve_path
    end
  end

  def test_standard_path_used_when_present
    around_env do
      File.stub(:executable?, ->(p) { p == WindowsApp::STANDARD_PATH }) do
        assert_equal WindowsApp::STANDARD_PATH, WindowsApp.resolve_path
      end
    end
  end

  def test_spotlight_result_used_when_standard_missing
    around_env do
      File.stub(:executable?, false) do
        WindowsApp.stub(:locate_via_spotlight, '/Users/me/Applications/Windows App.app/Contents/MacOS/Windows App') do
          assert_equal '/Users/me/Applications/Windows App.app/Contents/MacOS/Windows App',
                       WindowsApp.resolve_path
        end
      end
    end
  end

  def test_falls_back_to_standard_path_when_nothing_found
    around_env do
      File.stub(:executable?, false) do
        WindowsApp.stub(:locate_via_spotlight, nil) do
          assert_equal WindowsApp::STANDARD_PATH, WindowsApp.resolve_path
        end
      end
    end
  end
end

class WindowsAppOpenTest < Minitest::Test
  def test_open_command_forces_windows_app_and_adds_empty_authority
    # -b <bundle id> sends the URL to Windows App regardless of which app owns
    # the rdp:// scheme; the extra slash gives the URL an empty authority.
    cmd = WindowsApp.new('/x').open_command('rdp://full%20address=s%3Ahost')
    assert_equal ['open', '-b', 'com.microsoft.rdc.macos', 'rdp:///full%20address=s%3Ahost'], cmd
  end
end

class WorkflowTest < Minitest::Test
  BOOKMARKS = [['Prod Web', 'id-1'], ['Dev Box', 'id-2']].freeze

  def items(json)
    JSON.parse(json)['items']
  end

  # --- list ---

  def test_list_filters_bookmarks_by_query
    json = Workflow.new(FakeApp.new(bookmarks: BOOKMARKS)).list('prod')
    titles = items(json).map { |i| i['title'] }
    assert_includes titles, 'Prod Web'
    refute_includes titles, 'Dev Box'
  end

  def test_list_empty_query_returns_all_and_no_connect_item
    json = Workflow.new(FakeApp.new(bookmarks: BOOKMARKS)).list('')
    titles = items(json).map { |i| i['title'] }
    assert_equal ['Prod Web', 'Dev Box'], titles
    refute(titles.any? { |t| t.start_with?('Connect to ') })
  end

  def test_list_appends_adhoc_connect_item
    json = Workflow.new(FakeApp.new(bookmarks: BOOKMARKS)).list('me@192.168.4.3')
    connect = items(json).find { |i| i['title'] == 'Connect to me@192.168.4.3' }
    refute_nil connect
    assert_equal 'adhoc:me@192.168.4.3', connect['arg']
  end

  def test_list_no_matches_and_no_target_shows_not_found
    # A query of only whitespace matches no bookmark and is not a target.
    json = Workflow.new(FakeApp.new(bookmarks: BOOKMARKS)).list('   ')
    titles = items(json).map { |i| i['title'] }
    assert_equal ['No matching desktop found'], titles
  end

  # --- open ---

  def test_open_adhoc_builds_and_opens_uri
    app = FakeApp.new
    Workflow.new(app).open('adhoc:me@192.168.4.3:3390')
    assert_equal 1, app.opened.size
    assert_includes app.opened.first, '&full%20address=s%3A192.168.4.3%3A3390'
    assert_includes app.opened.first, '&username=s%3Ame'
  end

  def test_open_bookmark_exports_then_opens
    app = FakeApp.new(export_uri: 'rdp://full%20address=s%3Ahost')
    Workflow.new(app).open('id-42')
    assert_equal 'id-42', app.exported_id
    assert_equal ['rdp://full%20address=s%3Ahost'], app.opened
  end
end
