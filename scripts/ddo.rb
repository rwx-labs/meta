# frozen_string_literal: true

require 'httpx'

require 'ordnet'

Blur::Script :ordnet do
  include Blur::Commands

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description "Query ordnet.dk's ddo database"

  # Raised when a query returns no results.
  class NoResultError < StandardError; end

  def initialize
    @http = HTTPX.with(:compression)
  end

  command! '.ddo' do |_user, channel, args, _tags|
    return send_usage_information(channel) unless args

    Async do |task|
      result = query(args, parent: task).wait

      return channel.say(format('No result')) unless result

      formatted_query_response = format_query_response(result)
      channel.say(format(formatted_query_response))
    rescue HTTPX::HTTPError => e
      channel.say(format("http error: #{e.status}"))
    end
  end

  # Looks up the given +word+
  def query(word, parent: Async::Task.current)
    parent.async do
      headers = {
      }
      response = @http.get('https://ws.dsl.dk/ddo/query', params: { 'q' => word })
      response.raise_for_status

      query = Ordnet::Query.new(response.body.to_s)
      query if query.success
    end
  end

  def format_query_response(query)
    if query.definitions.any?
      format_definition(query, query.definitions.first)
    else
      format_idiom(query, query.idioms.first)
    end
  end

  def format_definition(query, definition)
    String.new.tap do |line|
      line << query.word
      line << " #{query.phonetic.strip}"
      line << " (\x0F#{query.word_classes}\x0310)" if query.word_classes
      line << " Bøjning:\x0F #{query.inflection}\x0310" if query.inflection
      line << " Oprindelse:\x0F #{query.origin}\x0310" if query.origin
      line << " Definition:\x0F #{definition.definition}\x0310" if definition.definition
      line << " Eksempel:\x0F #{definition.example}\x0310" if definition.example
    end
  end

  def format_idiom(query, definition)
    String.new.tap do |line|
      line << query.word
      line << " #{query.phonetic.strip}"
      line << " (\x0Fidiom, #{query.word_classes}\x0310)" if query.word_classes
      line << " Bøjning:\x0F #{query.inflection}\x0310" if query.inflection
      line << " Oprindelse:\x0F #{query.origin}\x0310" if query.origin
      line << " Definition:\x0F #{definition.definition}\x0310" if definition.definition
      line << " Eksempel:\x0F #{definition.example}\x0310" if definition.example
    end
  end

  def send_usage_information(channel)
    channel.say(format("Usage:\x0F .ddo <word>"))
  end

  def format(message)
    %(\x0310>\x0F\x02 DDO:\x0F\x0310 #{message})
  end
end
