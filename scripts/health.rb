# frozen_string_literal: true

Blur::Script :health do
  include Blur::Commands

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.4'
  Description 'Monitor the current resource usage'

  command!('.health') do |_user, channel, _args, _tags|
    channel.say(format("#{memory_summary} #{thread_summary} Scripts:\x0F #{_client_ref.scripts.count}\x0310"))
  end

  def memory_summary
    mem = memory_usage

    "Memory usage:\x0f #{mem[:rss].round(2)} MiB\x0310 (VSZ:\x0f #{mem[:vsz].round(2)} MiB\x0310)"
  end

  def thread_summary
    threads = Thread.list
    running = threads.select { |thread| thread.status == 'run' }
    sleeping = threads.select { |thread| thread.status == 'sleep' }

    "Threads:\x0f #{threads.count}\x0310 (\x0f#{running.count}\x0310 running,\x0f #{sleeping.count}\x0310 sleeping)"
  end

  def format(message)
    %(\x0310>\x0F\x02 Health:\x02\x0310 #{message})
  end

  def memory_usage
    rss, vsz = `ps -o rss=,vsz= -p #{Process.pid}`.split

    { vsz: vsz.to_f / 1000, rss: rss.to_f / 1000 }
  end
end
