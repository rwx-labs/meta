# frozen_string_literal: true

require 'httpx'
require 'nokogiri'
require 'active_support'
require 'active_support/core_ext/array/conversions'

Blur::Script :howlongtobeat do
  include Blur::Commands

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Adds commands to query howlongtobeat.com for game length estimations'

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
            'genre' => ''
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
      }
    }
    headers = {
      'referer' => 'https://howlongtobeat.com',
      'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/116.0'
    }

    parent.async do
      response = @http.post('https://howlongtobeat.com/api/search/5683ebd079f1c360', json: payload, headers:)
      return unless response.status == 200

      data = response.json
      return unless data && data['count'].positive?

      data['data']
    end
  end
end
