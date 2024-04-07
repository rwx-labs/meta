# frozen_string_literal: true

require 'httpx'
require 'semantic_logger'

Blur::Script :github do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.2'
  Description 'GitHub.com integration'

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  command!('.gh') do |_, channel, args, _tags|
    return send_usage_information(channel) unless args

    Async do
      response = search_repos(args, { 'sort' => 'stars', 'order' => 'desc' }).wait
      result = response['items']&.first

      if result
        channel.say(format_repo_details(result))
      else
        channel.say(format('No results'))
      end
    rescue HTTPX::HTTPError => e
      channel.say(format("http error #{e.status}"))
    end
  end

  # Searches for repositories based on the given +query+.
  def search_repos(query, params = {})
    params = {
      'q' => query
    }.merge(params)
    headers = {
      'Accept' => 'application/vnd.github+json',
      'X-GitHub-Api-Version' => '2022-11-28'
    }

    Async do
      response = @http.get('https://api.github.com/search/repositories', params:, headers:)
      response.raise_for_status
      response.json
    end
  end

  def format_repo_details(item)
    line = String.new
    line << "\x0f\u2442\x0310 " if item['fork'] # fork unicode character
    line << item['full_name']
    line << " - #{item['description']}" if item['description']
    line << " -\x0f #{item['html_url']}"
    line << "\x0310 - Language:\x0f #{item['language'] || '?'}\x0310 Stars:\x0f #{item['stargazers_count']}"

    format(line)
  end

  def command_usage
    '.gh <query>'
  end

  def send_usage_information(channel)
    channel.say(format(command_usage))
  end

  def format(message)
    %(\x0310>\x0F\x02 GitHub:\x02\x0310 #{message})
  end
end
