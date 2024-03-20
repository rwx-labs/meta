# frozen_string_literal: true

require 'rspotify'
require 'active_support/core_ext/array/conversions'

Blur::Script :spotify do
  include Blur::URLHandling

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.3'
  Description 'Fetches information about shared spotify tracks'

  SPOTIFY_URI_PATTERN = /spotify:(?<type>[a-zA-Z]+):(?<id>[a-zA-Z0-9]+)/

  def initialize
    @client_id = @config['client_id'] || ENV.fetch('SPOTIFY_CLIENT_ID', nil)
    @client_secret = @config['client_secret'] || ENV.fetch('SPOTIFY_CLIENT_SECRET', nil)

    raise "missing `client_id` and `client_secret'" unless @client_id &&
                                                           @client_secret

    RSpotify.authenticate(@client_id, @client_secret)
  end

  def message(_user, channel, line, _tags)
    Async do |task|
      links = extract_spotify_scheme_uris(line)

      links.each do |match|
        id = match['id']
        type = match['type']

        handle_spotify_request(channel, type, id, true, parent: task).wait
      end
    end
  end

  def handle_spotify_request(recipient, type, id, include_external_url = false, parent: Async::Task.current)
    parent.async do |task|
      case type
      when 'album' then send_album_details(recipient, id, include_external_url, parent: task).wait
      when 'track' then send_track_details(recipient, id, include_external_url, parent: task).wait
      when 'artist' then send_artist_details(recipient, id, include_external_url, parent: task).wait
      when 'playlist' then send_playlist_details(recipient, id, include_external_url, parent: task).wait
      else
        recipient.say(format('Unsupported Spotify URI'))
      end
    end
  end

  def extract_spotify_scheme_uris(line)
    words = line.to_s.split
    words.map { |word| word.match(SPOTIFY_URI_PATTERN) }.compact
  end

  register_url!('open.spotify.com', 'play.spotify.com') do |_user, channel, url|
    id = File.basename(url.path)
    type = File.basename(File.dirname(url.path))

    Async do
      handle_spotify_request(channel, type, id, false).wait
    end
  end

  # Sends a formatted message to the +recipient+ describing the track with the
  # id +track_id+.
  #
  # @param [#say] recipient the recipient, can be a channel or a user
  # @param [Integer, String] track_id the track id
  # @param [Boolean] include_external_url whether to include the external url
  #   to the track.
  def send_track_details(recipient, track_id, include_external_url = false, parent: Async::Task.current)
    parent.async do
      track = RSpotify::Track.find(track_id)

      album = track&.album&.name
      artists = track.artists.map { |artist| "\x0f#{artist.name}\x0310" }

      message = (+'').tap do |line|
        line << "\x0F#{track.name}\x0310 is a track by #{artists.to_sentence}\x0310"
        line << " from the album \x0F#{album}\x0310" if album
        line << " - #{track.external_urls['spotify']}" if include_external_url
      end
    rescue RestClient::Exception => e
      message = case e.http_code
                when 400 then 'Invalid track ID'
                when 404 then 'Track not found'
                else e.message
                end
    ensure
      recipient.say(format(message))
    end
  end

  # Sends a formatted message to the +recipient+ describing the album with the
  # id +album_id+.
  #
  # @param [#say] recipient the recipient, can be a channel or a user
  # @param [Integer, String] album_id the album id
  # @param [Boolean] include_external_url whether to include the external url
  #   for the album.
  def send_album_details(recipient, album_id, include_external_url = false, parent: Async::Task.current)
    parent.async do
      album = RSpotify::Album.find(album_id)

      artists = album.artists.map { |artist| "\x0f#{artist.name}\x0310" }

      message = (+'').tap do |line|
        line << "\x0F#{album.name}\x0310 is an album by #{artists.to_sentence}"
        line << " - #{album.external_urls['spotify']}" if include_external_url
      end
    rescue RestClient::Exception => e
      message = case e.http_code
                when 400 then 'Invalid album ID'
                when 404 then 'Album not found'
                else e.message
                end
    ensure
      recipient.say(format(message))
    end
  end

  # Sends a formatted message to the +recipient+ describing the artist with the
  # id +artist_id+.
  #
  # @param [#say] recipient the recipient, can be a channel or a user
  # @param [Integer, String] artist_id the artist id
  # @param [Boolean] include_external_url whether to include the external url
  #   for the artist.
  def send_artist_details(recipient, artist_id, include_external_url = false, parent: Async::Task.current)
    parent.async do
      artist = RSpotify::Artist.find(artist_id)
      genres = artist.genres.map { |genre| "\x0f#{genre}\x0310" }

      message = (+'').tap do |line|
        line << "\x0F#{artist.name}\x0310 is"
        line << " a #{genres.to_sentence}" if genres&.any?
        line << ' an' unless genres&.any?
        line << ' artist with '
        line << "\x0f#{artist.followers['total']}\x0310 followers"
        line << " - #{artist.external_urls['spotify']}" if include_external_url
      end
    rescue RestClient::Exception => e
      message = case e.http_code
                when 400 then 'Invalid artist ID'
                when 404 then 'Artist not found'
                else e.message
                end
    end
  ensure
    recipient.say(format(message))
  end

  # Sends a formatted message to the +recipient+ describing the playlist with the
  # id +playlist_id+.
  #
  # @param [#say] recipient the recipient, can be a channel or a user
  # @param [Integer, String] playlist_id the playlist id
  # @param [Boolean] include_external_url whether to include the external url
  #   for the playlist.
  def send_playlist_details(recipient, playlist_id, include_external_url = false, parent: Async::Task.current)
    parent.async do
      playlist = RSpotify::Playlist.find_by_id(playlist_id)
      followers = playlist.followers['total']

      message = (+'').tap do |line|
        line << "\x0F#{playlist.name}\x0310 is"
        line << " a playlist with\x0f"
        line << " #{playlist.tracks.count}\x0310 tracks"
        line << " curated by\x0f #{playlist.owner.display_name}\x0310"
        line << " with \x0f#{followers}\x0310 followers" if followers.positive?
        line << " - #{playlist.external_urls['spotify']}" if include_external_url
      end
    rescue RestClient::Exception => e
      message = case e.http_code
                when 400 then 'Invalid playlist ID'
                when 404 then 'Playlist not found'
                else e.message
                end
    ensure
      recipient.say(format(message))
    end
  end

  def format(message)
    %(\x0310>\x0f\x02 Spotify:\x02\x0310 #{message})
  end

  register!(:message)
end
