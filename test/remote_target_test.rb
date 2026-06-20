require 'minitest/autorun'
require_relative '../remote_target'

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
    # Note: the default set contains "gatewayusername="; "&username=" is distinct.
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
