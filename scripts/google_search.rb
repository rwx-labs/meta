# frozen_string_literal: true

require 'httpx'
require 'nokogiri'
require 'semantic_logger'

Blur::Script :google_search do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '3.0'
  Description 'Google search integration'

  # The base URL of the searxng instance to use.
  SEARXNG_BASE_URL = 'https://searx.dresden.network'
  # List of stylesheet files that we know aren't used for bot detection.
  KNOWN_STYLESHEETS = [
    'searxng.min.css'
  ].freeze

  # An instance of a google search result.
  class Result
    attr_accessor :url, :title, :content, :engines

    def initialize(title, url)
      @title = title
      @url = url
      @engines = []
    end

    def self.from_article_element(element)
      # Extract the title.
      title_link = element.at('h3 a')

      return unless title_link

      title = title_link.text.strip
      url = title_link.attr('href')

      result = Result.new(title, url)
      result.content = element.at('p.content')&.text&.strip
      result.engines = element.css('div.engines span')&.map { |x| x.text.strip }

      result
    end

    # Returns true if the result comes from the given `engine`.
    def engine?(engine)
      @engines.include?(engine)
    end
  end

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  def request_link_token
    Async do
      logger.debug('Requesting base page from instance to look for link tokens')
      response = @http.get(SEARXNG_BASE_URL, headers:)
      response.raise_for_status

      body = response.body.to_s
      document = Nokogiri::HTML(body)

      return unless document

      stylesheets = document.css('head link[type="text/css"]')
      stylesheet_urls = stylesheets.map do |stylesheet|
        URI(stylesheet['href'])
      end
      possible_link_tokens = stylesheet_urls.reject { |url| KNOWN_STYLESHEETS.include?(File.basename(url.path)) }

      request_url = URI(SEARXNG_BASE_URL)
      possible_link_tokens.each do |link_token|
        puts "link token path: #{link_token.path}"
        request_url.path = link_token.path
        logger.debug("requesting link token #{request_url}")
        response = @http.get(request_url, headers:)
        status = response.status
        logger.warn("tried to request link token #{link_token} but response status was #{status}!") if status != 200
      end
    end
  end

  command!('.g') do |_user, channel, args, _tags|
    return
    return channel.say(format("Usage:\x0F .g <query>")) unless args

    Async do
      results = search(args).wait
      logger.debug('results:', results)
      result = results&.find { |x| x.engine?('google') || x.engine?('duckduckgo') }

      if result
        logger.debug(result.inspect)
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

  class Redirected < StandardError; end

  # Searches on google for +query+.
  def search(query, _options = {})
    params = {
      'q' => query,
      'lang' => 'auto',
      'safesearch' => '0',
      'category_general' => '1',
      'time_range' => ''
    }
    request_url = "#{SEARXNG_BASE_URL}/search"

    Async do
      num_retries = 0

      begin
        response = @http.post(request_url, form: params, headers:)
        response.raise_for_status

        if response.status != 200
          logger.debug('response is not 200', headers: response.headers, status: response.status)
        end

        if response.status == 302
          request_link_token.wait
          num_retries += 1
          raise Redirected unless num_retries >= 3
        end

        body = response.body.to_s
        logger.debug('received body', body:)
        document = Nokogiri::HTML(body)

        return [] unless document

        search_results_from_document(document)
      rescue Redirected
        retry
      end
    end
  end

  def search_results_from_document(document)
    document.css('article.result').map do |article|
      Result.from_article_element(article)
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
      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Cache-Control' => 'no-cache',
      'Origin' => 'null',
      'Pragma' => 'no-cache',
      'Priority' => 'u=0, i',
      'Upgrade-Insecure-Requests' => '1',
      'User-Agent' => 'Mozilla/5.0 (X11; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0',
      'Accept-Language' => 'en-US,en;q=0.9,da-DK;q=0.8,da;q=0.7',
      'Accept-Encoding' => 'gzip, deflate'
    }
  end
end
