# frozen_string_literal: true

Blur::Script :auth do
  include Blur::Commands

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.1'
  Description 'Simple authorization script'

  def initialize
    @admins = @config['admins'] || []
    @commands = @config['commands'] || []
  end

  def authorized?(user)
    @admins.include?("#{user.nick}!#{user.name}@#{user.host}")
  end

  command! '.reload' do |user, channel, _, _tags|
    if authorized?(user)
      _client_ref.reload! do
        channel.say("\x0310> Configuration and scripts reloaded.")
      end
    else
      channel.say("\x0310> You're not authorized to use this command.")
    end
  end

  # Authenticate with NickServ if a password is provided.
  def connection_ready(network)
    password = ENV.fetch('NICKSERV_PASSWORD', nil)

    network.say('NICKSERV', "IDENTIFY #{password}") if password
  end

  register! :connection_ready
end
