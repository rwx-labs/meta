# frozen_string_literal: true

require 'async'
require 'net/dns'

Blur::Script :dig do
  include Blur::Commands
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'DNS lookup utillity'

  # @return [Array<String>] list of records types that is supported
  VALID_RECORD_TYPES = %w[A CNAME MX SRV TXT PTR AAAA NS SOA ANY SPF].freeze

  # Error that occurs when a specified record type isn't valid
  class InvalidRecordType < StandardError; end

  def initialize
    @resolver = Net::DNS::Resolver.new
  end

  command!('.dig') do |_user, channel, args, _tags|
    return channel.say(format(usage)) if args.nil? || args.empty?

    domain, record = args.split

    Async do |task|
      result = query(domain, record || 'A', parent: task).wait

      if result.answer.any?
        result.answer.each do |answer|
          channel.say(format(answer))
        end
      else
        channel.say(format('No answers'))
      end
    rescue StandardError => e
      channel.say(format("Error: #{e.message}"))
    end
  end

  def query(domain, record = 'A', parent: Async::Task.current)
    record = record.upcase

    raise InvalidRecordType, "Invalid record type #{record}" unless VALID_RECORD_TYPES.include?(record)

    parent.async do
      logger.debug('sending dns query', { domain:, record: })

      @resolver.search(domain, record)
    end
  end

  def usage
    %(Usage: .dig <domain> [#{VALID_RECORDS.join('|')}])
  end

  def format(message)
    %(\x0310>\x03\x02 DNS:\x02\x0310 #{message})
  end
end
