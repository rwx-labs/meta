# frozen_string_literal: true

Blur::Script :health do
  include Blur::Commands

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.4'
  Description 'Monitor the current resource usage'

  def initialize
    @page_size = `getconf PAGESIZE`.to_f
  end

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
    statm = File.read('/proc/self/statm').split

    vsz = statm[0].to_f * @page_size / 1024 / 1024
    rss = statm[1].to_f * @page_size / 1024 / 1024

    { vsz: vsz, rss: rss }
  end
end
