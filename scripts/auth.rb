# frozen_string_literal: true

Blur::Script :auth do
  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.1'
  Description 'Simple authorization script'

  include Blur::Commands

  def authorized?(user)
    @config[:admins].include? "#{user.nick}!#{user.name}@#{user.host}"
  end

  command! '.reload' do |user, channel, _|
    if authorized? user
      _client_ref.reload! do
        channel.say "\x0310> Configuration and scripts reloaded."
      end
    else
      channel.say "\x0310> You're not authorized to use this command."
    end
  end
end
