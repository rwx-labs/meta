# frozen_string_literal: true

require 'httpx'
require 'nokogiri'
require 'htmlentities'
require 'semantic_logger'

Blur::Script :google_search do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '3.0'
  Description 'Google search integration'

  # An instance of a google search result.
  class Result
    attr_accessor :url, :title

    def initialize(title, url)
      @title = title
      @url = url
    end
  end

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  command!('.g') do |_user, channel, args, _tags|
    return channel.say(format("Usage:\x0F .g <query>")) unless args

    Async do
      results = search(args).wait
      result = results&.first

      if result
        logger.debug(result)
        channel.say(format("#{result.title}\x0F - #{result.url}"))
      else
        channel.say(format('No results'))
      end
    rescue HTTPX::HTTPError => e
      logger.error('http error', e)
      channel.say(format("http error #{e.status}"))
    rescue StandardError => e
      logger.error('google search error', e)
      channel.say(format("error: #{e}"))
    end
  end

  # Searches on google for +query+.
  def search(query, _options = {})
    params = { 'q' => query, 'format' => 'json' }
    request_url = 'https://searx.sev.monster/search'

    Async do
      response = @http.post(request_url, form: params, headers:)
      response.raise_for_status

      json = response.json

      return [] unless json
      return [] unless json.key?('results')

      search_results_from_json(json)
    end
  end

  def search_results_from_json(json)
    results = json['results']
    results.map { |result| Result.new(result['title'], result['url']) }
  end

  def format(message)
    %(\x0310>\x0F \x02Google:\x02\x0310 #{message})
  end

  # Default request headers.
  def headers
    {
      'DNT' => '1',
      'User-Agent' => 'Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0',
      'Accept-Language' => 'en-US,en;q=0.5',
      'Accept-Encoding' => 'gzip, deflate',
    }
  end
end
