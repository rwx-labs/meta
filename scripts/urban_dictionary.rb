# frozen_string_literal: true

require 'oj'
require 'httpx'

Blur::Script :urban_dictionary do
  include Blur::Commands

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Search for definitions on urbandictionary.com'

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  command!('.ud') do |_user, channel, args, _tags|
    Async do
      if args.strip.casecmp('georgehale').zero?
        hardcoded_output = "Term:\x0F GEORGEHALE\x0310 Definition:\x0F Icelandic sheep fucker.\x0310"
        channel.say(format(hardcoded_output))
        next
      end
      results = search(args).wait
      result = results&.first

      if result
        output = "Term:\x0F #{result['word']}\x0310 "
        output << "Definition:\x0F #{strip_newlines(result['definition'])}\x0310 " if result['definition']
        output << "Example:\x0F #{strip_newlines(result['example'])}\x0310" if result['example']

        channel.say(format(output))
      else
        channel.say(format('No results'))
      end
    end
  end

  # Searches for the given +term+ on Urban Dictionary.
  def search(term)
    Async do
      params = { 'term' => term }
      response = @http.get("https://api.urbandictionary.com/v0/define", params:)
      response.raise_for_status

      results_from_response(response)
    end
  end

  protected

  def strip_newlines(string)
    string.gsub("\n", ' ')
  end

  def results_from_response(response)
    json = response.json
    return [] unless json

    json['list']
  end

  def format(message)
    %(\x0310>\x0F\x02 Urban Dictionary:\x02\x0310 #{message})
  end
end
