# frozen_string_literal: true

Blur::Script :openweathermap do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Client interface to the open weather map service with user commands'

  KELVIN = 273.15 # °K

  class Error < StandardError; end
  class GeocodeError < Error; end

  def initialize
    @app_id = @config['app_id'] || ENV.fetch('OPENWEATHERMAP_APP_ID', nil)

    raise "`app_id' (or OPENWEATHERMAP_APP_ID env var) is not set" unless @app_id

    @http = HTTPX.with(:persistence).with_timeout(total_timeout: 30)
  end

  # Right now in Viborg, it's 16 degrees celcius and partly cloudy, tonight it's
  # predicted to be xx with a chance of showers.
  command!('.w') do |_user, channel, args, _tags|
    # account = tags['account']
    # latitude, longitude = account_location(account) if account
    location = args&.strip

    return channel.say(format("Usage: .w\x0f <location>")) if location.empty?

    Async do
      weather = current_weather_at(location).wait
      channel.say(format_weather(weather))
    rescue Error => e
      logger.error('error', e)
      channel.say(format("Error: #{e}"))
    rescue HTTPX::HTTPError => e
      logger.error('http error', e)
      channel.say(format("http error #{e.status}"))
    end
  end

  def current_weather_at(location, parent: Async::Task.current)
    parent.async do |_task|
      result = geocode(location).wait&.first
      raise GeocodeError, 'could not geocode location' unless result

      latitude = result['lat']
      longitude = result['lon']
      current_weather(latitude, longitude).wait
    end
  end

  def account_location(account)
    location = script(:user_settings).get(account, 'profile.location')
    coords = location&.split(',')

    return unless coords && coords.length == 2

    lat, long = coords.map(&:strip)

    [lat, long]
  end

  def format_weather(weather)
    temp = weather['main']['temp'].to_f - KELVIN
    wind_speed = weather['wind']['speed'].to_f
    wind_gust = weather['wind']['gust'].to_f
    feels_like = weather['main']['feels_like'].to_f - KELVIN

    result = String.new
    result << "Right now in\x0f " << weather['name'] << "\x0310"
    result << " it's\x0f " << temp.round(1).to_s << " °C\x0310"
    result << " (feels like\x0f " << feels_like.round(1).to_s << " °C\x0310)"

    if (w = weather['weather']) && w.any?
      weather_string = w.map { |weather| "\x0f#{weather['description']}\x0310" }.join ' and '
      result << ' with ' << weather_string
    end

    result << ". Wind:\x0f " << wind_speed.round(1).to_s << " m/s\x0310, gusts:\x0f " << wind_gust.round(1).to_s << " m/s\x0310"

    format(result)
  end

  def current_weather(latitude, longitude)
    Async do
      params = {
        'lat' => latitude,
        'lon' => longitude,
        'appid' => @app_id
      }

      response = @http.get('https://api.openweathermap.org/data/2.5/weather', params:)
      response.raise_for_status
      response.json
    end
  end

  def geocode(query, limit = 5)
    Async do
      params = {
        'q' => query,
        'limit' => limit,
        'appid' => @app_id
      }

      response = @http.get('http://api.openweathermap.org/geo/1.0/direct', params:)
      response.raise_for_status
      response.json
    end
  end

  private

  def format(message)
    "\x0310> #{message}"
  end
end
