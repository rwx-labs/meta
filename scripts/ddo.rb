# encoding: utf-8

require 'em-http-request'

require 'ordnet'

Blur::Script :ordnet do
  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.2'
  Description "Query ordnet.dk's ddo database"

  include Blur::Commands

  command! '.ddo' do |user, channel, args|
    next send_usage_information channel unless args

    query args do |success, result|
      if success
        channel.say format format_query_response result
      else
        channel.say format result
      end
    end
  end

  def format_query_response query
    if query.definitions.any?
      format_definition query, query.definitions.first
    else
      format_idiom query, query.idioms.first
    end
  end

  def format_definition query, definition
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

  def format_idiom query, definition
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

  def query word
    http = EM::HttpRequest.new("https://ws.dsl.dk/ddo/query?q=#{URI.escape word}").get

    http.callback do
      query = Ordnet::Query.new http.response

      if query.success
        yield true, query
      else
        yield false, 'No results'
      end
    end

    http.errback do
      yield false, 'Connection error'
    end
  end

  def send_usage_information channel
    channel.say format "Usage:\x0F .ddo <word>"
  end

  def format message
    %{\x0310>\x0F\x02 DDO:\x0F\x0310 #{message}}
  end
end
