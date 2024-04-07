# frozen_string_literal: true

require 'httpx'
require 'multi_json'
require 'semantic_logger'

Blur::Script :google_images do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.1'
  Description 'Google image search support'

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  command!('.gis') do |_user, channel, args, _tags|
    Async do
      result = search(args).wait
      logger.trace('result:', result)
      ischj = result['ischj']

      if ischj.empty?
        channel.say(format('No results'))
      else
        images = ischj['metadata']
        image = images&.first
        text_in_grid = image['text_in_grid']
        original_image = image['original_image']

        channel.say(format("#{text_in_grid['snippet']} - #{original_image['url']}"))
      end
    end
  end

  def search(query, page: 0)
    logger.debug('searching for images', query:)

    Async do
      params = {
        'q' => query,
        'tbm' => 'isch',
        'asearch' => 'isch',
        'async' => "_fmt:json,p:1,ijn:#{page}"
      }
      headers = {
        'Accept' => '*/*'
      }
      response = @http.get('https://www.google.com/search', params:, headers:)
      response.raise_for_status
      body = response.body.to_s
      offset = body.index('{"ischj":')
      MultiJson.load(body[offset..]) if offset
    end
  end

  private

  def format(message)
    %(\x0310>\x0f \x02Google:\x02\x0310 #{message})
  end
end
