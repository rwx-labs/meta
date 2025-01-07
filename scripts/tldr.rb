# frozen_string_literal: true

require 'httpx'
require 'optimist'
require 'shellwords'
require 'multi_json'
require 'fuzzy_match'
require 'semantic_logger'

Blur::Script :tldr do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.2'
  Description 'Summarize content using Kagi.com'

  # URL to the summarization endpoint
  SUMMARY_API_URL = 'https://kagi.com/mother/summary_labs'
  # The default language to target
  TARGET_LANGUAGE = 'DOC'
  # List of supported languages
  SUPPORTED_LANGUAGES = {
    'Default' => '',
    'Document Language' => 'DOC',
    'Bulgarian' => 'BG',
    'Czech' => 'CS',
    'Danish' => 'DA',
    'German' => 'DE',
    'Greek' => 'EL',
    'English' => 'EN',
    'Spanish' => 'ES',
    'Estonian' => 'ET',
    'Finnish' => 'FI',
    'French' => 'FR',
    'Hungarian' => 'HU',
    'Indonesian' => 'ID',
    'Italian' => 'IT',
    'Japanese' => 'JA',
    'Korean' => 'KO',
    'Lithuanian' => 'LT',
    'Latvian' => 'LV',
    'Norwegian' => 'NB',
    'Dutch' => 'NL',
    'Polish' => 'PL',
    'Portuguese' => 'PT',
    'Romanian' => 'RO',
    'Russian' => 'RU',
    'Slovak' => 'SK',
    'Slovenian' => 'SL',
    'Swedish' => 'SV',
    'Turkish' => 'TR',
    'Ukrainian' => 'UK',
    'Chinese (simplified)' => 'ZH',
    'Chinese (traditional)' => 'ZH-HANT'
  }.freeze
  RESUMMARIZE_PROMPT = <<-PROMPT
You will be given a long summary of an article or news story. Your task is to create a shorter, more concise summary that captures the essential information.

Here is the long summary:
<long_summary>
{{LONG_SUMMARY}}
</long_summary>

This is a prompt provided by the user:
<user_prompt>
{{USER_PROMPT}}
</user_prompt>

To create the shorter summary:
1. Identify the main topic or event described in the long summary.
2. Determine the key actors or parties involved.
3. Highlight the most important facts or developments.
4. Include any significant outcomes or implications.

Write the summary according to the given user prompt, using a <short_summary> tag.
  PROMPT
  DEFAULT_USER_PROMPT = <<-PROMPT
Write the summary in a single sentence.
  PROMPT

  class Error < StandardError; end
  class RequestError < Error; end
  class UnexpectedResponseError < Error; end

  # The user requested a list of supported languages
  class LanguageListNeeded < Error; end
  class InvalidURLError < Error; end

  def initialize
    @token = @config['token'] || ENV.fetch('KAGI_SESSION_TOKEN', nil)
    raise "`token' (or KAGI_SESSION_TOKEN) is not set" unless @token

    @google_ai_key = @config['google_ai_key'] || ENV.fetch('GOOGLE_AI_KEY', nil)
    raise "`google_ai_key' (or GOOGLE_AI_KEY) is not set" unless @google_ai_key

    @http = HTTPX.with_timeout(total_timeout: 60)
  end

  # .tldr [OPTIONS] <url>
  command!('.tldr') do |_user, channel, args, _tags|
    opts, url, prompt = parse_args(args)

    logger.debug('opts:', opts)
    logger.debug('url:', url)
    logger.debug('prompt:', prompt)

    summary_type = (opts[:takeway] ? 'takeaway' : 'summary')
    target_language = find_language_code_by_name_or_code(opts[:language])

    Async do
      result = summarize(url, summary_type:, target_language:).wait

      data = result['output_data']
      return channel.say(format('Could not summarize contents')) if data.nil? || data.empty?

      markdown = data['markdown']
      summary = resummarize(markdown, prompt || DEFAULT_USER_PROMPT).wait

      summary.to_s.each_line.lazy.map(&:strip).each do |line|
        channel.say(format(line)) unless line.empty?
      end
    rescue Error => e
      channel.say(format("Error:\x0f #{e}"))
    end
  rescue LanguageListNeeded
    send_language_list(channel)
  rescue Optimist::HelpNeeded
    send_command_help(channel)
  rescue Optimist::CommandlineError => e
    channel.say(format(e.message))
  rescue Error => e
    channel.say(format("Error:\x0f #{e.message}"))
  end

  # This is an argument parser for the `.tldr` command.
  ArgumentParser = Optimist::Parser.new do
    banner <<~BANNER
      Usage: .tldr [OPTIONS] <url> [prompt]
    BANNER

    opt :takeway, 'Generate a list of takeaway points instead of a summarization'
    opt :language, 'Language to summarize the content in', default: 'Default'
  end

  def ArgumentParser.die(arg, message = nil)
    raise Optimist::CommandlineError, "argument --#{@specs[arg].long} #{message}." if message
  end

  def summarize(url, summary_type: 'summary', target_language: nil)
    headers = request_headers
    params = build_request_params(url, summary_type:, target_language:)

    Async do
      logger.info("requesting #{summary_type} for url #{url} using language #{target_language}")

      response = @http.post(SUMMARY_API_URL, params:, headers:)

      response.raise_for_status
      process_summary_response(response)
    end
  end

  def resummarize(summary, user_prompt)
    Async do
      response = request_resummary(summary, user_prompt).wait

      json = response&.json
      candidates = json['candidates']
      raise UnexpectedResponseError, "no candidates" unless candidates

      content = candidates.find { |candidate| candidate.key?('content') }['content']
      text_parts = content['parts'].select { |part| part.key?('text') }
      text = text_parts.map { |part| part['text'] }.join($INPUT_RECORD_SEPARATOR)

      if text =~ %r{<short_summary>(.*?)</short_summary>}mi
        Regexp.last_match(1)
      else
        text
      end
    end
  end

  # Send a request to have Claude resummarize the summary.
  def request_resummary(summary, user_prompt)
    Async do
      prompt = RESUMMARIZE_PROMPT.gsub('{{LONG_SUMMARY}}', summary).gsub('{{USER_PROMPT}}', user_prompt)
      request = {
        'contents' => [
            { 'role' => 'user', 'parts' => [{ text: prompt }] }
          ],
          'generationConfig' => {
            'maxOutputTokens' => 1024
          }
      }
      params = {
        'key' => @google_ai_key
      }
      logger.debug('request:', request)
      response = @http.post('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent', json: request, params:)
      response.raise_for_status
      response
    end
  end

  def process_summary_response(response)
    raise UnexpectedResponseError, "unexpected http status: #{response.status}" unless response.status == 200

    json = response.json

    if json['error']
      error_message = json['output_text']
      raise Error, error_message
    end

    json
  end

  # Parses the given +args+ and returns a set of options and a url.
  #
  # @return [Hash, String] the parsed options and the argument url
  def parse_args(args)
    args = Shellwords.split(args) || []
    opts = ArgumentParser.parse(args)

    raise LanguageListNeeded if ['help', '?'].include?(opts[:language])

    url = args.shift
    prompt = args.join(' ')

    if prompt.empty?
      prompt = DEFAULT_USER_PROMPT
    end

    raise Optimist::HelpNeeded unless url
    raise InvalidURLError, 'The provided argument is not a valid URL' unless url.start_with?('http')

    [opts, url, prompt]
  end

  # Finds and returns the closest matching language code based on the languages
  # in `SUPPORTED_LANGUAGES`
  def find_language_code_by_name_or_code(name_or_code)
    # Short-circuit if the input is a valid code
    maybe_code = name_or_code.upcase
    code = SUPPORTED_LANGUAGES.values.find { |c| c == maybe_code }
    return code if code

    find_language_code_by_name(name_or_code)
  end

  # Finds and returns the closest matching language code based on the languages
  # in `SUPPORTED_LANGUAGES`
  def find_language_code_by_name(name)
    matcher = FuzzyMatch.new(SUPPORTED_LANGUAGES.keys)
    language = matcher.find(name)

    return unless language

    SUPPORTED_LANGUAGES[language]
  end

  # Sends the command usage description to `channel`
  def send_command_help(channel)
    StringIO.new.tap do |io|
      ArgumentParser.educate(io)
      io.rewind

      io.each_line do |line|
        channel.say(format(line))
      end
    end
  end

  # Sends the list of supported language lists to the given +channel+
  def send_language_list(channel)
    formatted_language_list = SUPPORTED_LANGUAGES.keys.join("\x0310,\x0f ")
    formatted_message = format("Supported languages:\x0f #{formatted_language_list}")

    channel.say(formatted_message)
  end

  private

  # Builds and returns the request headers.
  def request_headers
    {
      'Authorization' => @token,
      'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:123.0) Gecko/20100101 Firefox/123.0'
    }
  end

  # Builds and returns the request parameters for requesting a summary.
  def build_request_params(url, summary_type:, target_language: nil)
    params = {
      'url' => url,
      'summary_type' => summary_type
    }

    params['target_language'] = target_language if target_language

    params
  end

  def format(message, title = nil)
    if title
      %(\x0310>\x0f\x02 TLDR\x02\x0310 (\x0f#{title}\x0310): #{message})
    else
      %(\x0310>\x0f\x02 TLDR\x02\x0310: #{message})
    end
  end
end
