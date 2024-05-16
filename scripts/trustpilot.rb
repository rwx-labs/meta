# frozen_string_literal: true

require 'httpx'

Blur::Script :trustpilot do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Adds commands to query trustpilot for business scores'

  # The base URL of the version 1 API endpoint.
  API_BASE_URL = 'https://api.trustpilot.com/v1'

  class Error < StandardError; end

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
    @api_key = @config['api_key'] || ENV.fetch('TRUSTPILOT_API_KEY', nil)

    raise 'missing `api_key` (or `TRUSTPILOT_API_KEY` env var)' unless @api_key
  end

  command!('.tp') do |_user, channel, line, _tags|
    name = line&.strip
    return channel.say(format("Usage: .tp\x0f <business>")) if name.nil? || name.empty?

    Async do
      result = search(name).wait

      channel.say(format_business(result)) if result
    rescue Error => e
      logger.error('error', e)
      channel.say(format("Error: #{e}"))
    rescue HTTPX::HTTPError => e
      logger.error('http error', e)
      channel.say(format("http error #{e.status}"))
    end
  end

  def format_business(details)
    score = details['score']
    trust_score = score['trustScore']
    num_reviews = details['numberOfReviews']
    num_reviews_total = num_reviews['total']
    display_name = details['displayName']
    names = details['name']
    identifying_name = names['identifying']

    format(
      "Score:\x0f #{trust_score}\x0310/\x0f5.0\x0310 Reviews:\x0f #{num_reviews_total}\x0310 - https://dk.trustpilot.com/review/#{identifying_name}", display_name
    )
  end

  def search(name)
    Async do
      find_business_unit(name).wait
    rescue HTTPX::HTTPError => e
      raise Error, 'no results' if e.status == 404

      raise e
    end
  end

  def get_business_unit(business_id)
    Async do
      get("business-units/#{business_id}").wait
    end
  end

  # Finds a business unit from its name.
  #
  # @yield [Bool, Hash] success, response
  def find_business_unit(name)
    Async do
      params = { name: }
      get('business-units/find', params:).wait
    end
  end

  private

  def get(path, params: {})
    url = "#{API_BASE_URL}/#{path}"
    params = {
      'apikey' => @api_key
    }.merge(params)

    Async do
      response = @http.get(url, params:)
      response.raise_for_status
      response.json
    end
  end

  def format(message, subtitle = nil)
    if subtitle
      %{\x0310>\x0f\x02 Trustpilot\x02\x0310 (\x0f#{subtitle}\x0310): #{message}}
    else
      %(\x0310>\x0F\x02 Trustpilot:\x02\x0310 #{message})
    end
  end
end
