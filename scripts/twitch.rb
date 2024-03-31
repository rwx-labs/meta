# frozen_string_literal: true

require 'httpx'
require 'active_support/core_ext/numeric/conversions'

Blur::Script :twitch do
  include Blur::URLHandling
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Twitch.tv integration'

  class RequestError < StandardError; end
  class UnauthenticatedError < StandardError; end

  BASE_URL = 'https://api.twitch.tv'
  CHANNEL_URL_PATTERN = %r{^/(?<channel>[a-zA-Z0-9_]{4,25})/?$}
  CLIP_URL_PATTERN = %r{^/(?<channel>[^/]+)/clip/(?<clip_id>[^/]*)}
  VIDEO_URL_PATTERN = %r{^/videos/(?<video_id>[0-9]+)/?}

  def initialize
    @client_id = @config['client_id'] || ENV.fetch('TWITCH_CLIENT_ID', nil)
    @client_secret = @config['client_secret'] || ENV.fetch('TWITCH_CLIENT_SECRET', nil)

    raise "`client_id' (or env TWITCH_CLIENT_ID) is missing" unless @client_id
    raise "`client_secret' (or env TWITCH_CLIENT_SECRET) is missing" unless @client_secret

    @http = HTTPX.plugin(:persistent).with_timeout(total_timeout: 30)
    @access_token = cache['access_token']
  end

  register_url!('twitch.tv', 'www.twitch.tv') do |_user, channel, url|
    case url.path
    when CLIP_URL_PATTERN
      clip_id = Regexp.last_match('clip_id')
      describe_twitch_clip!(channel, clip_id)
    when VIDEO_URL_PATTERN
      video_id = Regexp.last_match('video_id')
      describe_twitch_video!(channel, video_id)
    when CHANNEL_URL_PATTERN
      channel_name = Regexp.last_match('channel')
      describe_twitch_stream!(channel, channel_name)
    end
  end

  register_url!('clips.twitch.tv') do |_user, channel, url|
    clip_id = File.basename(url.path)
    describe_twitch_clip!(channel, clip_id)
  end

  # @note This method is blocking and needs to run inside a thread.
  def describe_twitch_stream!(recipient, channel_name)
    Async do |task|
      stream = get_stream_by_user_login(channel_name, parent: task).wait

      if !stream.nil? && (stream = stream['data']&.first)
        title = stream['title']
        user_login = stream['user_login']
        game_name = stream['game_name']
        viewer_count = stream['viewer_count'].to_i.to_fs(:delimited)

        recipient.say(format("#{user_login}:\x0f #{title}\x0310 - Game:\x0f #{game_name}\x0310 Viewers:\x0f #{viewer_count}\x0310"))
      else
        recipient.say("\x0310> #{channel_name} - Twitch")
      end
    end
  end

  # @note This method is blocking and needs to run inside a thread.
  def describe_twitch_clip!(recipient, clip_id)
    Async do |task|
      clip = get_clip_by_id(clip_id, parent: task).wait

      if (clip = clip['data']&.first)
        title = clip['title']
        creator_name = clip['creator_name']
        broadcaster_name = clip['broadcaster_name']
        view_count = clip['view_count'].to_i.to_fs(:delimited)
        recipient.say(format("“\x0f#{title}\x0310” is a clip of\x0f #{broadcaster_name}\x0310 clipped by\x0f #{creator_name}\x0310 with\x0f #{view_count}\x0310 views"))
      else
        recipient.say(format('No results'))
      end
    end
  end

  # @note This method is blocking and needs to run inside a thread.
  def describe_twitch_video!(recipient, video_id)
    Async do |task|
      video = get_video_by_id(video_id, parent: task).wait

      logger.debug('video:', video)

      if (video = video['data']&.first)
        title = video['title']
        user_login = video['user_login']
        view_count = video['view_count'].to_i.to_fs(:delimited)

        recipient.say(format("“\x0f#{title}\x0310” is a video by\x0f #{user_login}\x0310 with\x0f #{view_count}\x0310 views"))
      else
        recipient.say(format('No results'))
      end
    end
  end

  # Returns stream data for a given +user_login+.
  def get_stream_by_user_login(user_login, parent: Async::Task.current, **kwargs)
    params = { 'user_login' => user_login }
    headers = request_headers

    parent.async do |task|
      get('/helix/streams', params:, headers:, parent: task, **kwargs).wait
    end
  end

  def get_stream_by_user_id(user_id, parent: Async::Task.current, **kwargs)
    params = { 'user_id' => user_id }
    headers = request_headers

    parent.async do |task|
      get('/helix/streams', params:, headers:, parent: task, **kwargs).wait
    end
  end

  # Returns a game by its unique game id.
  def get_game_by_id(game_id, parent: Async::Task.current, **kwargs)
    params = { 'id' => game_id }
    headers = request_headers

    parent.async do |task|
      get('/helix/games', params:, headers:, parent: task, **kwargs).wait
    end
  end

  def get_user_by_name(login_name, parent: Async::Task.current, **kwargs)
    params = { 'login' => login_name }
    headers = request_headers

    parent.async do |task|
      get('/helix/users', params:, headers:, parent: task, **kwargs).wait
    end
  end

  def get_clip_by_id(clip_id, parent: Async::Task.current, **kwargs)
    params = { 'id' => clip_id }
    headers = request_headers
    logger.debug("requesting clip with id #{clip_id}")

    parent.async do |task|
      get('/helix/clips', params:, headers:, parent: task, **kwargs).wait
    end
  end

  def get_video_by_id(video_id, parent: Async::Task.current, **kwargs)
    parent.async do |task|
      params = { 'id' => video_id }
      headers = request_headers

      get('/helix/videos', params:, headers:, parent: task, **kwargs).wait
    end
  end

  def refresh_access_token!(http: nil, parent: Async::Task.current)
    url = 'https://id.twitch.tv/oauth2/token'
    params = {
      'client_id' => @client_id,
      'client_secret' => @client_secret,
      'grant_type' => 'client_credentials'
    }

    logger.debug('refreshing access token')

    parent.async do
      response = (http || @http).post(url, params:)
      return unless response.status == 200

      json = response.json
      return unless json['access_token']

      @access_token = json['access_token']
      cache['access_token'] = @access_token
      cache.save
      logger.debug('refreshed access token')
    end
  end

  # Sends a GET request to the API endpoint with given +args+.
  def get(path, http: nil, headers: request_headers, parent: Async::Task.current, **kwargs)
    url = BASE_URL + path # :D~
    retries = 0

    parent.async do
      response = (http.nil? ? @http : http).get(url, headers:, **kwargs)

      case response.status
      when 200
        json = response.json
        json if json.key?('data')
      when 401
        raise UnauthenticatedError, response.body
      else
        puts response.body
        raise RequestError, "unexpected response code #{response.status}"
      end
    rescue UnauthenticatedError
      logger.debug('request requires authorization, refreshing access token')

      if retries < 1
        refresh_access_token!.wait
        headers['Authorization'] = "Bearer #{@access_token}" if @access_token
        retries += 1
        retry
      end
    end
  end

  private

  def format(message)
    %(\x0310>\x0F\x02 Twitch:\x02\x0310 #{message})
  end

  def request_headers
    headers = {
      'Client-ID' => @client_id,
      'Accept' => 'application/vnd.twitchtv.v5+json'
    }

    headers['Authorization'] = "Bearer #{@access_token}" if @access_token
    headers
  end
end
