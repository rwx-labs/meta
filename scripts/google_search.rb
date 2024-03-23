# frozen_string_literal: true

require 'httpx'
require 'nokogiri'
require 'htmlentities'
require 'semantic_logger'

Blur::Script :google_search do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '2.0'
  Description 'Google search integration'

  # An instance of a google search result.
  class Result
    attr_accessor :url, :title, :filter

    def filter?
      @block
    end

    # Creates a result from a HTML element.
    def self.from_element(element)
      result = Result.new

      # Find the first link with a `h3` child.
      header_link = element.css('a').find do |e|
        e.children.find { |e2| e2.name == 'h3' }
      end

      # Parse the header link
      if header_link
        header_title = header_link.at('h3')

        return nil unless header_title

        result.title = header_title.text
        header_link_href = header_link[:href]

        # If google tries to track the url, strip out the real url.
        if header_link_href&.start_with?('/url')
          header_link_uri = URI.parse(header_link_href)
          result.url = CGI.parse(header_link_uri.query)['q'][0]
        else
          result.url = header_link_href
        end
      end

      result
    end
  end

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
    @decoder = HTMLEntities.new
  end

  command!('.g') do |_user, channel, args, _tags|
    return channel.say(format("Usage:\x0F .g <query>")) unless args

    Async do
      results = search(args).wait
      result = results&.first

      if result
        logger.debug(result)
        channel.say(format("#{@decoder.decode(result.title)}\x0F - #{result.url}"))
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
    params = { 'q' => query, 'hl' => 'en' }
    request_url = 'https://www.google.dk/search'

    Async do
      response = @http.get(request_url, params:, headers:)
      response.raise_for_status

      body = response.body.to_s
      document = Nokogiri::HTML(body)

      return [] unless document

      search_results_from_document(document)
    end
  end

  def search_results_from_document(document)
    body = document.at('div#search div#rso')
    return [] unless body

    body.css('div.g').map do |div|
      Result.from_element(div)
    end.compact
  end

  def format(message)
    %(\x0310>\x0F \x02Google:\x02\x0310 #{message})
  end

  # Default request headers.
  def headers
    {
      'User-Agent' => 'Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0',
      'Accept-Language' => 'en-US,en;q=0.8,da;q=0.6',
      'Accept-Charset' => 'utf-8'
    }
  end
end
