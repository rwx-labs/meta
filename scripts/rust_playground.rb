# frozen_string_literal: true

require 'httpx'

Blur::Script :rust_playground do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Evaluates Rust code using the online Rust Playground'

  BASE_URL = 'https://play.rust-lang.org'

  def initialize
    @http = HTTPX.with_timeout(total_timeout: 30)
  end

  command!('.rs') do |_user, channel, line, _tags|
    expr = line&.strip
    return channel.say(format("Usage: .rs\x0f <expr>")) if expr.nil? || expr.empty?

    Async do
      result = self.eval(expr).wait

      if result['success']
        output = result['stdout'][0..250].strip
        output.gsub!(/[\x00-\x19\127]/, '')

        channel.say("\x0310> #{output}")
      else
        # Rudamentary extraction of errors from stderr
        stderr = result['stderr']
        errors = stderr.scan(/^error(\[E\d+\])?: (.*?)$/)
        formatted_errors = errors.map { |(_code, message)| message.to_s }

        channel.say("\x0310> Compilation error(s): #{formatted_errors.join(', ')[0..250]}")
      end
    rescue HTTPX::HTTPError => e
      logger.error('http error', e)
      channel.say(format("http error #{e.status}"))
    end
  end

  def eval(expr, edition = '2021', mode = 'debug')
    body = build_exec_request(expr, edition, mode)

    Async do
      request = @http.post("#{BASE_URL}/execute", json: body)
      request.raise_for_status
      request.json
    end
  end

  private

  def build_exec_request(expr, edition = '2018', mode = 'debug')
    code = <<~CODE
      fn main() {
        println!("{:?}", {
          #{expr}
        });
      }
    CODE

    {
      'channel' => 'stable',
      'mode' => mode,
      'edition' => edition,
      'crateType' => 'bin',
      'tests' => false,
      'code' => code,
      'backtrace' => false
    }
  end

  def format(message)
    %(\x0310>\x0F\x02 Rust Playground:\x02\x0310 #{message})
  end
end
