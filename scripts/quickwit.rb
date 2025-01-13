# frozen_string_literal: true

require 'httpx'
require 'optimist'
require 'shellwords'
require 'multi_json'
require 'semantic_logger'

Blur::Script :tldr do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.1'
  Description 'Interact with Quickwit search indices'

  QUICKWIT_BASE_URL = 'http://quickwit.quickwit-prod.svc.cluster.local:7280'
  # QUICKWIT_BASE_URL = 'http://localhost:7280'
  INDEXES = ['dba-v1']

  class Error < StandardError; end
  class RequestError < Error; end
  class InvalidIndexError < Error; end
  class UnexpectedResponseError < Error; end

  # The user requested a list of supported languages
  class LanguageListNeeded < Error; end
  class InvalidURLError < Error; end

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 60)
  end

  # .search <index> <query>
  command!('.search') do |_user, channel, args, _tags|
    index, query = args&.split(' ', 2)

    return channel.say(format("Usage:\x0f .search <index> <query>")) if index&.empty?

    Async do
      result = search(index, query).wait

      if result['num_hits'].zero?
        return channel.say(format('No hits'))
      end

      result['hits'].each do |hit|
        channel.say(format("Title:\x0f #{truncate(hit['title']&.strip, 100)}\x0310 Description:\x0f #{truncate(hit['description']&.strip, 100)}\x0310 Price:\x0f #{hit['price']}"))
      end
    rescue HTTPX::HTTPError => e
      channel.say(format("Error:\x0f #{e}"))
    rescue Error => e
      channel.say(format("Error:\x0f #{e}"))
    end
  rescue Error => e
    channel.say(format("Error:\x0f #{e.message}"))
  end

  def search(index, query)
    raise InvalidIndexError, "Invalid index `#{index}'" unless index_allowed?(index)

    Async do
      logger.info("searching index #{index} using query #{query.inspect}")

      url = "#{QUICKWIT_BASE_URL}/api/v1/#{index}/search"
      params = {
        'query' => query,
        'max_hits' => 3,
      }

      response = @http.get(url, params:)
      response.raise_for_status
      response.json
    end
  end

  # Returns true if the given `index` is allowed to be queried.
  def index_allowed?(index)
    INDEXES.include?(index)
  end

  def truncate(text, length)
    if text.length >= length
      text[..length] + "…"
    else
      text
    end
  end

  def format(message, title = nil)
    if title
      %(\x0310>\x0f\x02 DBA\x02\x0310 (\x0f#{title}\x0310): #{message})
    else
      %(\x0310>\x0f\x02 DBA\x02\x0310: #{message})
    end
  end
end
