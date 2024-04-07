# frozen_string_literal: true

require 'unicode/name'
require 'unicode/sequence_name'
require 'unicode/categories'
require 'active_support'
require 'active_support/inflector'
require 'active_support/core_ext/string/filters'

Blur::Script :unicode_utils do
  include Blur::Commands

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.2'
  Description 'Provides utillities for identifying unicode glyphs.'

  NUM_MAX_CODEPOINTS = 5

  command!('.uni') do |_user, channel, args, _tags|
    return channel.say(format("Usage: #{command_usage}")) unless args

    input = args.force_encoding('utf-8')
    result = describe_unicode_input(input)

    channel.say(truncate(format(result)))
  end

  def describe_unicode_input(input)
    # If the input is a sequence of codepoints get the name (emojis can be
    # combinations of codepoints for example) and return it
    if (sequence = Unicode::SequenceName.of(input))
      input_codepoints = input.codepoints.map(&method(:format_unicode_offset))

      return "\x0310{\x0f#{input_codepoints.join(', ')}\x0310}\x0310:\x0f #{sequence}"
    end

    # If the input isn't a sequence, get the name and category of each
    # invidivudal codepoint
    codepoint_names = input.codepoints.take(NUM_MAX_CODEPOINTS)
                           .map(&method(:format_codepoint))

    codepoint_names.join(', ')
  end

  def format_codepoint(codepoint)
    char = codepoint.chr('utf-8')
    name = Unicode::Name.readable(char)
    category = Unicode::Categories.category(char, format: :long)
    category.gsub!('_', ' ')
    offset = format_unicode_offset(codepoint)

    "#{offset}\x0310:\x0f #{name}\x0310 (\x0f#{category}\x0310)\x0f"
  end

  private

  def command_usage
    ".uni\x0f <char[,char..]>"
  end

  def format_unicode_offset(codepoint)
    "U+#{codepoint.to_s(16).rjust(4, '0').upcase}"
  end

  def format(input)
    "\x0310> #{input}"
  end

  def truncate(message)
    message.truncate(350, separator: /,\s/, omission: "\x0f, \u2026")
  end
end
