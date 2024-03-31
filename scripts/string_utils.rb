# frozen_string_literal: true

Blur::Script :string_utils do
  include Blur::Commands

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'String utillities such as string length, reversing, etc.'

  # Usage: .rev <string>
  #
  # Reverses the string.
  command!('.rev') do |_user, channel, args, _tags|
    return channel.say(format(usage('.rev <string>'))) unless args

    channel.say(format(args.reverse))
  end

  # Usage: .len <string>
  #
  # Returns the number of characters in the string.
  command!('.len') do |_user, channel, args, _tags|
    return channel.say(format(usage('.len <string>'))) unless args

    channel.say(format(args.length))
  end

  # Usage: .b <string>
  #
  # Converts the string from UTF-8 to ASCII-8BIT.
  command!('.b') do |_user, channel, args, _tags|
    return channel.say(format(usage('.b <chars..>'))) unless args

    channel.say(format(args.b.inspect))
  end

  # Usage: .count <char> <string>
  #
  # Counts the number of occurences of `character` in `string`.
  command!('.count') do |_user, channel, args, _tags|
    params = args.split(' ', 2) if args
    return channel.say(format(usage('.count <char> <string>'))) if params.nil? || params.length < 2

    char = params[0]
    string = params[1]
    result = string.count(char)

    channel.say(format(result))
  end

  # Usage: .ord <chars..>
  #
  # Returns the integer ordinal for each of the characters.
  command!('.ord') do |_user, channel, args, _tags|
    return channel.say(format(usage('.ord <chars..>'))) unless args

    result = args.chars.map(&:ord).join(', ')

    channel.say(format(result))
  end

  # Usage: .codepoints <chars..>
  #
  # Returns the UTF-8 codepoints for each of the characters.
  command!('.codepoints') do |_user, channel, args, _tags|
    return channel.say(format(usage('.codepoints <chars..>'))) unless args

    input = args.force_encoding('UTF-8')
    result = input.codepoints.join(', ')

    channel.say(format(result))
  end

  private

  def usage(example)
    %(Usage:\x0f #{example})
  end

  def format(*args)
    %(\x0310> #{args.join})
  end
end
