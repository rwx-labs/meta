# frozen_string_literal: true

require 'semantic_logger'

Blur::Script :isitopen do
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.2'
  Description 'Lets the user ask if a place is open'

  class Error < StandardError; end
  class PlaceNotFoundError < Error; end

  IS_OPEN = 'is_open'
  IS_CLOSED = 'is_closed'
  OPENING_TIME = 'opening_time'
  CLOSING_TIME = 'closing_time'

  def initialize
    # script(:settings).register 'isitopen', 'profile.location', 'Your location in the format lattiude,longitude'
  end

  def message(user, channel, line, _tags)
    line = line.force_encoding('utf-8')
    my_name = Regexp.escape(channel.network.nickname)
    request, place_name = extract_request(line, my_name)

    return unless request

    # account = tags['account']
    # location = script(:user_settings).get(account, 'profile.location') if account

    Async do
      place = find_place(place_name).wait
      raise PlaceNotFoundError unless place

      case request
      when IS_OPEN then cmd_is_place_open(user, channel, place)
      when IS_CLOSED then cmd_is_place_closed(user, channel, place)
      when OPENING_TIME then cmd_when_does_place_open(user, channel, place)
      when CLOSING_TIME then cmd_when_does_place_close(user, channel, place)
      end
    rescue PlaceNotFoundError
      channel.say(format('Error: place not found'))
    end
  end

  def extract_request(message, my_name)
    request = case message
              when /^#{my_name}[,:] hvornår åbner (?<place>.*?)\?/,
                   /^#{my_name}[,:] hvad tid åbner (?<place>.*?)\?/
                OPENING_TIME
              when /^#{my_name}[,:] hvornår lukker (?<place>.*?)\?/,
                   /^#{my_name}[,:] hvad tid lukker (?<place>.*?)\?/
                CLOSING_TIME
              when /^#{my_name}[,:] (har|er) (?<place>.*?) åbent?\?/
                IS_OPEN
              when /^#{my_name}[,:] (har|er) (?<place>.*?) lukket\?/
                IS_CLOSED
              end

    return unless request

    place_name = Regexp.last_match('place')
    [request, place_name]
  end

  def find_place(place_name)
    logger.debug('searching for place', place_name:)

    Async do
      places = script(:google_maps).search_places(place_name).wait
      place = places&.first

      next unless place

      script(:google_maps).get_place_details(place).wait
    end
  end

  def cmd_when_does_place_open(user, channel, place)
    if place.always_open?
      channel.say("#{user.nick}:\x02 #{place.name}\x02 har døgnåbent")
    elsif place.open?
      channel.say("#{user.nick}:\x02 #{place.name}\x02 har allerede åbent - de åbnede kl.\x02 #{place.opening_time}\x02")
    elsif (opening_time = place.opening_time)
      channel.say("#{user.nick}:\x02 #{place.name}\x02 åbner kl.\x02 #{opening_time}\x02")
    else
      channel.say("#{user.nick}: pas -\x02 #{place.name}\x02 har ikke nogen åbningstid")
    end
  end

  def cmd_when_does_place_close(user, channel, place)
    if place.always_open?
      channel.say("#{user.nick}:\x02 #{place.name}\x02 har døgnåbent")
    elsif place.open?
      channel.say("#{user.nick}:\x02 #{place.name}\x02 lukker kl.\x02 #{place.closing_time}\x02 - de åbnede kl.\x02 #{place.opening_time}\x02")
    else
      now = Time.now
      open_time, close_time = place.open_and_close_time

      if open_time && close_time
        if open_time >= now
          channel.say("#{user.nick}:\x02 #{place.name}\x02 lukker kl.\x02 #{place.closing_time}\x02, men de har ikke åbent endnu - de åbner først kl.\x02 #{place.opening_time}\x02")
        else
          channel.say("#{user.nick}:\x02 #{place.name}\x02 har lukket for resten af dagen")
        end
      else
        channel.say("#{user.nick}: pas -\x02 #{place.name}\x02 har ikke nogen lukketid")
      end
    end
  end

  def cmd_is_place_open(user, channel, place)
    if place.always_open?
      channel.say("#{user.nick}: ja,\x02 #{place.name}\x02 har døgnåbent")
    elsif place.open?
      channel.say("#{user.nick}: ja,\x02 #{place.name}\x02 åbnede kl.\x02 #{place.opening_time}\x02 i dag")
    else
      now = Time.now
      open_time, close_time = place.open_and_close_time

      if open_time && close_time
        if open_time >= now
          channel.say("#{user.nick}: nej,\x02 #{place.name}\x02 har lukket, men de åbner kl.\x02 #{place.opening_time}")
        else
          channel.say("#{user.nick}: nej,\x02 #{place.name}\x02 har lukket for i dag")
        end
      else
        channel.say("#{user.nick}: pas -\x02 #{place.name}\x02 har ikke nogen åben- og lukketid")
      end
    end
  end

  def cmd_is_place_closed(user, channel, place)
    if place.always_open?
      channel.say("#{user.nick}: nej,\x02 #{place.name}\x02 har døgnåbent")
    elsif place.open?
      channel.say("#{user.nick}: nej,\x02 #{place.name}\x02 åbnede kl.\x02 #{place.opening_time}\x02 og lukker kl.\x02 #{place.closing_time}\x02 i dag")
    else
      now = Time.now
      open_time, _close_time = place.open_and_close_time

      if open_time && open_time >= now
        channel.say("#{user.nick}: ja,\x02 #{place.name}\x02 har lukket, men de åbner kl.\x02 #{place.opening_time}")
      else
        channel.say("#{user.nick}: ja,\x02 #{place.name}\x02 har lukket for i dag")
      end
    end
  end

  private

  def format(message)
    %(\x0310#{message})
  end

  register! :message
end
