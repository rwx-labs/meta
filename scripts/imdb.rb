# frozen_string_literal: true

require 'mk/imdb'
require 'nokogiri'
require 'httpx'
require 'semantic_logger'

Blur::Script :imdb do
  include Blur::Commands
  include Blur::URLHandling
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Search for and display information about IMDb titles'

  # A regex that matches and extracts the IMDb title ID from a URI path
  TITLE_PATTERN = %r{^/title/(tt[0-9]{4,25})/?$}

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  command!('.imdb') do |_, channel, args, _tags|
    return send_usage_information(channel) unless args

    title = args&.strip

    Async do
      result = search(title).wait
      title_id = extract_title_id_from_url(result)
      describe_title_to!(channel, title_id).wait
    rescue StandardError => e
      logger.error("could not find or get details for title #{title.inspect}", e)
      channel.say(format("Error: #{e}"))
    end
  end

  register_url!('imdb.com', 'www.imdb.com') do |_, channel, url|
    Async do
      describe_title_to!(channel, Regexp.last_match(1)).wait if url.path =~ TITLE_PATTERN
    rescue StandardError => e
      logger.error('could not get details about linked title', e)
      channel.say(format("Error: #{e}"))
    end
  end

  # Searches for a given IMDb title using google search
  #
  # @yield [success, result] success and a search result
  # @yieldparam success [bool] true if a result was found
  # @yieldparam url [String] the url to the IMDb title page
  def search(title)
    Async do
      query = "#{title} site:www.imdb.com/title/"
      result = script(:google_search).search(query).wait&.first

      return unless result&.url&.to_s =~ %r{^https?://www\.imdb\.com/title/(tt[\d]+)}

      result.url.to_s
    end
  end

  def describe_title_to!(recipient, title_id)
    Async do
      movie = get_movie_information(title_id).wait
      recipient.say(format_title_response(movie))
    end
  end

  def get_movie_information(movie_id)
    Async do
      response = @http.get("https://www.imdb.com/title/#{movie_id}/reference", headers: request_headers)
      response.raise_for_status

      document = Nokogiri::HTML(response.body.read)

      MK::IMDb::Movie.new(document)
    end
  end

  def format_title_response(title)
    output = String.new
    output << "\x0F#{title.title}\x0310"
    output << " (\x0F#{title.year.strip}\x0310)" if title.year
    output << " Plot:\x0f #{title.plot}\x0310"

    output << " Rating:\x0F #{title.rating || '?'}\x0310/\x0F10\x0310"

    output << " Casts:\x0F " << title.casts[0..2].join("\x0310,\x0F ")
    output << "\x0310,\x0F …" if title.casts.count > 3

    output << "\x0310 Genre#{title.genres.count > 1 ? 's' : ''}:\x0F " << title.genres[0..2].join("\x0310,\x0F ")
    output << "\x0310,\x0F …" if title.genres.count > 3

    output << "\x0310 URL:\x0F https://www.imdb.com/title/#{title.id}/"

    format(output)
  end

  def send_usage_information(channel)
    channel.say(format('Usage: .imdb <movie title>'))
  end

  def extract_title_id_from_url(url)
    Regexp.last_match(1) if url.to_s =~ %r{^https?://www\.imdb\.com/title/(tt[\d]+)}
  end

  private

  def request_headers
    {
      'User-Agent' => 'Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0'
    }
  end

  def format(message)
    %(\x0310>\x0F \x02IMDb:\x02\x0310 #{message})
  end
end
