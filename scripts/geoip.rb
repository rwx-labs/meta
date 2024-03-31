# frozen_string_literal: true

require 'oj'
require 'httpx'

Blur::Script :geoip do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Get a geographical location summary of an IP-address'

  def initialize
    @api_key = @config['api_key'] || ENV.fetch('GEOIP_API_KEY', nil)

    raise "`api_key' not set" unless @api_key

    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  command!('.geoip') do |_user, channel, args, _tags|
    return send_usage_information(channel) unless args

    addr = args&.strip

    Async do
      result = lookup(addr).wait

      if result['statusCode'] == 'OK'
        channel.say(format_response(result))
      else
        channel.say(format('No result'))
      end
    rescue HTTPX::Error => e
      channel.say(format("http error #{e.status}"))
    end
  end

  # Look up the location of an IP address.
  def lookup(address, precision: 'city')
    endpoint = precision == 'city' ? 'ip-city' : 'ip-country'
    params = {
      'ip' => address,
      'key' => @api_key,
      'format' => 'json'
    }

    Async do
      response = @http.get("https://api.ipinfodb.com/v3/#{endpoint}/", params:)
      response.raise_for_status
      response.json
    end
  end

  def send_usage_information(channel)
    channel.say(format("Usage:\x0F .geoip <hostname>"))
  end

  def format_response(result)
    line = String.new

    line << "Country:\x0F #{result['countryName'].capitalize}\x0310 " unless result['countryName'].empty?
    line << "Region:\x0F #{result['regionName'].capitalize}\x0310 " unless result['regionName'].empty?
    line << "City:\x0F #{result['cityName'].capitalize}\x0310 " unless result['cityName'].empty?

    ip = result['ipAddress']

    if ip
      format(line, result['ipAddress'])
    else
      format(line)
    end
  end

  private

  def format(message, addr = nil)
    if addr
      %(\x0310>\x0F\x02 GeoIP\x02\x0310 (\x0F#{addr}\x0310): #{message})
    else
      %(\x0310>\x0F\x02 GeoIP\x02\x0310: #{message})
    end
  end
end
