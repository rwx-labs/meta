# frozen_string_literal: true

require 'oj'
require 'httpx'
require 'semantic_logger'

Blur::Script :google_maps do
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Google Maps API interface'

  API_BASE_URL = 'https://maps.googleapis.com'
  DEFAULT_LANGUAGE = 'en'

  class Error < StandardError; end
  class ZeroResultsError < Error; end
  class OverQueryLimitError < Error; end
  class RequestDeniedError < Error; end
  class InvalidRequestError < Error; end

  # https://developers.google.com/places/web-service/search#PlaceSearchResults
  class Place
    # @return [String] place id.
    attr_reader :id
    # @return [String] place name, if any.
    attr_reader :name
    # @return [Boolean] is the place open now?
    attr_accessor :open_now
    # @return [Boolean] is the place always open?
    attr_accessor :always_open
    # @return [String] place url.
    attr_accessor :url
    # @return [String] place icon.
    attr_accessor :icon
    # @return [Array] list of photos.
    attr_accessor :photos
    # @return [Number] price level of the place, on a scale of 0 to 4.
    attr_accessor :price_level
    # @return [Float] the place's rating, from 0 to 5.0.
    attr_accessor :rating
    # @return [String] formatted address.
    attr_accessor :formatted_address
    # @return [Hash] location geometry.
    attr_accessor :geometry
    # @return [Hash] list of opening periods.
    attr_accessor :opening_hours

    # Constructs a new Place iwth a +place_id+ and a +name+.
    def initialize(id, name)
      @id = id
      @name = name
      @opening_hours = Array.new(7)
    end

    # @returns [Boolean] true if the place is currently open.
    def open?
      @open_now
    end

    # @returns [Boolean] true if the place is closed.
    def closed?
      !open?
    end

    def open_and_close_time(instant = Time.now)
      weekday = instant.wday
      periods = @opening_hours[weekday]

      if periods['open']
        parsed = DateTime.strptime(periods['open']['time'], '%H%M')
        open_time = Time.new(instant.year, instant.month, instant.day, parsed.hour,
                             parsed.minute, instant.sec, instant.utc_offset)
      end

      if periods['close']
        parsed = DateTime.strptime(periods['close']['time'], '%H%M')
        close_time = Time.new(instant.year, instant.month, instant.day, parsed.hour,
                              parsed.minute, instant.sec, instant.utc_offset)
      end

      [open_time, close_time]
    end

    def open_at?(datetime)
      open_datetime, close_datetime = open_and_close_time(datetime)

      datetime >= open_datetime && datetime < close_datetime if open_datetime && close_datetime
    end

    def always_open?
      @always_open
    end

    def closing_time(date = Date.today)
      weekday = date.wday
      periods = @opening_hours[weekday]

      return unless periods && periods['close']

      parsed = DateTime.strptime(periods['close']['time'], '%H%M')
      parsed.strftime('%H:%M')
    end

    def opening_time(date = Date.today)
      weekday = date.wday
      periods = @opening_hours[weekday]

      return unless periods && periods['open']

      parsed = DateTime.strptime(periods['open']['time'], '%H%M')
      parsed.strftime('%H:%M')
    end

    # Creates a new place from a given `json` hash.
    def self.from_json(json)
      name = json['name']
      place_id = json['place_id']

      Place.new(place_id, name).tap do |place|
        place.icon = json['icon']
        place.photos = json['photos']
        place.price_level = json['price_level']
        place.rating = json['rating']
        place.formatted_address = json['formatted_address']
        place.geometry = json['geometry']
        place.url = json['url']

        if (opening_hours = json['opening_hours'])
          place.open_now = opening_hours['open_now']

          if (periods = opening_hours['periods'])
            # If the place only have a single opening period, it might be always
            # open.
            if periods.length == 1
              period = periods.first

              # If the day is 0 and the time is '0000', the place is always
              # open.
              if period['open']['day'].zero? &&
                 period['open']['time'] == '0000' &&
                 !period.key?('close')

                place.always_open = true
                next
              end
            end

            # Fill an array with periods for each day of the week.
            periods.each do |period|
              day = (period.key?('open') && period['open']['day']) ||
                    (period.key?('close') && period['close']['day'])

              place.opening_hours[day] = period
            end
          end
        end
      end
    end
  end

  def initialize
    @api_key = @config['api_key'] || ENV.fetch('GOOGLE_MAPS_API_KEY', nil)
    raise "`api_key' (or GOOGLE_MAPS_API_KEY env) not set" unless @api_key

    @http = HTTPX.with(:persistence).with_timeout(total_timeout: 30)
    @lang = @config.fetch('lang', DEFAULT_LANGUAGE)
  end

  def get(path, params: {}, **kwargs)
    request_url = "#{API_BASE_URL}#{path}"
    params = {
      'key' => @api_key
    }.merge(params)

    Async do
      response = @http.get(request_url, params:, **kwargs)
      response.raise_for_status
      json = response.json
      # logger.debug("get #{path}", json:)
      json
    end
  end

  # Searches for places with the given `query`.
  #
  # @yields success, result
  def search_places(query, params: {})
    params = {
      'query' => query
    }.merge(params)

    Async do
      response = get('/maps/api/place/textsearch/json', params:).wait
      response['results'].map(&Place.method(:from_json))
    end
  end

  def get_place_details(place)
    params = {
      'placeid' => place.id
    }

    Async do
      response = get('/maps/api/place/details/json', params:).wait

      Place.from_json(response['result'])
    end
  end

  private

  ERRORS = {
    'ZERO_RESULTS' => ZeroResultsError,
    'OVER_QUERY_LIMIT' => OverQueryLimitError,
    'REQUEST_DENIED' => RequestDeniedError,
    'INVALID_REQUEST' => InvalidRequestError
  }.freeze

  def status_to_error(status)
    ERRORS[status]
  end
end
