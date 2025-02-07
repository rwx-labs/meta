# frozen_string_literal: true

require 'uri'

require 'httpx'
require 'nokogiri'
require 'active_support'
require 'active_support/core_ext/array/conversions'

Blur::Script :howlongtobeat do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Adds commands to query howlongtobeat.com for game length estimations'

  # The base URL of HowLongToBeat.com.
  BASE_URL = URI('https://howlongtobeat.com')

  # Contains the completion times for a game title.
  class Game
    # @return [String] the game title
    attr_accessor :title

    # @return [Hash<String, String>] the average completion times for multiple
    #   categories.
    attr_accessor :completion_times

    def initialize(title)
      @title = title
    end

    def self.from_element(element)
      details = element.at('.search_list_details')
      details_block = element.at('.search_list_details_block')

      title = details.at('h3 > a')&.text

      Game.new(title).tap do |game|
        tidbits = details_block.css('div .search_list_tidbit')

        # The tidbits are in alternating rows so we just get the text values of
        # the elements and convert them to a hash.
        tidbits = Hash[*tidbits.map { |tidbit| tidbit.text.strip }]

        game.completion_times = tidbits
      end
    end
  end

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  command!('.hltb') do |_user, channel, line, _tags|
    Async do |task|
      if (results = search(line, parent: task).wait)
        result = results.first

        completion_times = {}
        completion_times['Main Story'] = seconds_to_hours(result['comp_main'])
        completion_times['Main + Extra'] = seconds_to_hours(result['comp_plus'])
        completion_times['Completionist'] = seconds_to_hours(result['comp_100'])

        completion_times = completion_times.map do |category, time|
          "#{category}:\x0f #{time}\x0310"
        end

        channel.say(format(completion_times.join(' | '), result['game_name']))
      else
        channel.say(format('Could not find any results'))
      end
    end
  end

  def format(message, title = nil)
    if title
      %%\x0310>\x0f\x02 HLTB\x02\x0310 (\x0f#{title}\x0310): #{message}%
    else
      %(\x0310>\x0f\x02 HLTB\x02\x0310: #{message})
    end
  end

  def seconds_to_hours(seconds)
    minutes = seconds.to_f / 60
    hours = minutes / 60

    "#{hours.round} hours"
  end

  # Requests the latests scripts from the site and tries to extract the API
  # endpoint for search as they constantly change it.
  def update_api_endpoint(parent: Async::Task.current)
    logger.debug('updating api endpoint')

    parent.async do |subtask|
      response = @http.get(BASE_URL, headers: request_headers)
      response.raise_for_status

      body = response.body.to_s
      document = Nokogiri::HTML(body)

      break unless document

      scripts = document.css('script[src]')
      scripts_with_urls = nodes_with_absolute_url_attrs(scripts, 'src')
      scripts_with_urls.each do |(_element, url)|
        filename = File.basename(url.path)

        next unless filename.start_with?('_app-') && filename.end_with?('.js')

        logger.debug("requesting script #{url}")

        if (endpoint = extract_api_endpoint(url, parent: subtask).wait)
          @search_endpoint = endpoint
          logger.debug("using search api endpoint #{@search_endpoint}")
        end
      end
    end
  end

  def nodes_with_absolute_url_attrs(list, attribute = 'href')
    list.map do |element|
      value = element[attribute]
      next unless value

      if value.start_with?('/')
        url = BASE_URL.dup
        url.path = value

        [element, url]
      else
        [element, URI(value)]
      end
    end
  end

  # Extracts the search API endpoint from the given javascript URL.
  def extract_api_endpoint(url, parent: Async::Task.current)
    parent.async do |_subtask|
      response = @http.get(url, headers: request_headers)
      response.raise_for_status

      body = response.body.to_s

      if body =~ /fetch\("([^"]+)"\.concat\("([^"]+)"\)\.concat\("([^"]+)"\)/
        search_endpoint = "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{Regexp.last_match(3)}"
        search_endpoint
      end
    end
  end

  # Searches for and returns a list of games matching the query.
  def search(query, parent: Async::Task.current)
    # We use the original payload because the API is very finicky about the
    # parameters.
    payload = {
      'searchType' => 'games',
      'searchTerms' => query&.split,
      'searchPage' => 1,
      'size' => 20,
      'searchOptions' => {
        'games' => {
          'userId' => 0,
          'platform' => '',
          'sortCategory' => 'popular',
          'rangeCategory' => 'main',
          'rangeTime' => {
            'min' => nil,
            'max' => nil
          },
          'gameplay' => {
            'perspective' => '',
            'flow' => '',
            'genre' => '',
            'difficulty' => ''
          },
          'rangeYear' => {
            'min' => '',
            'max' => ''
          },
          'modifier' => ''
        },
        'users' => {
          'sortCategory' => 'postcount'
        },
        'lists' => {
          'sortCategory' => 'follows'
        },
        'filter' => '',
        'sort' => 0,
        'randomizer' => 0
      },
      useCache: true
    }
    headers = request_headers.merge({ 'referer' => 'https://howlongtobeat.com' })

    update_api_endpoint.wait

    logger.debug('searching for title', title: query)

    parent.async do
      request_url = BASE_URL.dup.tap do |url|
        url.path = @search_endpoint
      end
      response = @http.post(request_url, json: payload, headers:)
      next unless response.status == 200

      data = response.json
      next unless data && data['count'].positive?

      data['data']
    end
  end

  private

  def request_headers
    {
      'user-agent' => 'Mozilla/5.0 (X11; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0'
    }
  end
end
