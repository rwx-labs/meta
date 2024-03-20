# frozen_string_literal: true

require 'httpx'
require 'oj'
require 'multi_json'
require 'dotiw'

Blur::Script :tvmaze do
  include Blur::Commands
  include SemanticLogger::Loggable
  include DOTIW::Methods

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'TVMaze integration'

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  command! '.next' do |_user, channel, args, _tags|
    return channel.say(format('Usage:\x0f .next <query>')) if args.nil? || args.to_s.empty?

    Async do
      episode = next_episode_of_show(args).wait

      if episode
        channel.say(episode)
      else
        channel.say('Something went wrong')
      end
    rescue HTTPX::HTTPError => e
      logger.error('http error', e)
      channel.say(format('No results')) if e.status == 404
    end
  end

  # Search for a single show.
  def single_search(query, params = {}, parent: Async::Task.current)
    parent.async do
      params = { 'q' => query }.merge(params)
      response = @http.get('https://api.tvmaze.com/singlesearch/shows', params:)
      response.raise_for_status
      response.json
    end
  end

  def next_episode_of_show(show, parent: Async::Task.current)
    parent.async do |task|
      params = { 'embed' => 'nextepisode' }
      result = single_search(show, params, parent: task).wait
      embedded = result['_embedded']
      next_episode = embedded['nextepisode'] if embedded

      if embedded && next_episode
        name = result['name']
        air_date = DateTime.parse(next_episode['airstamp'])
        formatted_date = distance_of_time_in_words(Time.now, air_date)
        season = next_episode['season']
        number = next_episode['number']
        episode_name = next_episode['name'] || 'TBA'

        next format("Next episode “\x0f#{episode_name}\x0310” (\x0f#{season}x#{number}\x0310) airs in\x0f #{formatted_date}", name)
      end

      if result
        name = result['name']

        next format("\x0f#{name}\x0310 is currently marked as\x0f #{result['status']}\x0310 and there is no next episode")
      end

      format('No results')
    end
  end

  private

  def format(message, title = nil)
    if title
      %(\x0310>\x0f\x02 TVmaze\x02\x0310 (\x0f#{title}\x0310): #{message})
    else
      %(\x0310>\x0f\x02 TVmaze\x02\x0310: #{message})
    end
  end
end
