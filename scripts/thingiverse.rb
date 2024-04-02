# frozen_string_literal: true

require 'httpx'
require 'active_support/inflector'
require 'active_support/core_ext/numeric'

Blur::Script :thingiverse do
  include Blur::URLHandling
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Thingiverse search queries and URL handler'

  THING_PATH_PATTERN = %r{^/thing:(?<id>\d+)/?$}i

  # Error messages
  MSG_CONNECTION_ERROR = 'Connection error'
  MSG_THING_NOT_FOUND_ERROR = 'Thing not found'

  def initialize
    @app_token = @config['app_token'] || ENV.fetch('THINGIVERSE_APP_TOKEN', nil)

    raise "`app_token' (or env var THINGIVERSE_APP_TOKEN) not set" unless @app_token

    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  register_url!('thingiverse.com', 'www.thingiverse.com') do |_user, channel, url|
    if url.path =~ THING_PATH_PATTERN
      thing_id = Regexp.last_match('id').to_i

      Async do
        thing = thing_by_id(thing_id).wait

        if thing
          channel.say(format_thing(thing))
        else
          channel.say(format('thing not found'))
        end
      rescue HTTPX::HTTPError => e
        logger.error('http error', e)
        channel.say(format("http error #{e.status}"))
      end
    end
  end

  def format_thing(json)
    creator = json['creator']

    output = String.new
    output << "\x0310> “\x0f#{json['name']}\x0310”"
    output << ' is a'

    output << if json['is_wip']
                "\x0f work in progress\x0310"
              elsif json['is_featured']
                " \x0ffeatured\x0310"
              else
                ' thing'
              end

    output << " created by\x0f #{creator['name']}\x0310"

    like_count = json['like_count']
    download_count = json['download_count']

    output << " with\x0f #{like_count.to_fs(:delimited)}\x0310 #{'likes'.pluralize(like_count)}"
    output << ",\x0f #{download_count.to_fs(:delimited)}\x0310 #{'downloads'.pluralize(download_count)}"

    collect_count = json['collect_count']
    if collect_count.positive?
      output << " and is part of\x0f #{collect_count.to_fs(:delimited)}\x0310 #{'collections'.pluralize(collect_count)}"
    end

    output
  end

  def thing_by_id(id)
    Async do
      url = "https://api.thingiverse.com/things/#{id}/"

      response = @http.get(url, headers: request_headers)
      response.raise_for_status
      response.json
    end
  end

  private

  def format(message)
    %(\x0310>\x0F \x02Thingiverse:\x02\x0310 #{message})
  end

  def request_headers
    {
      'Authorization' => "Bearer #{@app_token}"
    }
  end
end
