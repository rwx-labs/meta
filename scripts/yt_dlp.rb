# frozen_string_literal: true

require 'json'

Blur::Script :yt_dlp do
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '0.1'
  Description 'API to execute yt-dlp commands'

  # The default command to to run `yt-dlp`
  DEFAULT_COMMAND = ['python3', '-m', 'yt_dlp'].freeze
  # The default output container for videos
  DEFAULT_CONTAINER = 'mp4'
  # The default format to download
  DEFAULT_FORMAT = nil

  class Error < StandardError; end

  def initialize
    @command = @config.fetch('ytdlp_command', DEFAULT_COMMAND)
    @container = @config.fetch('container', DEFAULT_CONTAINER)
    @format = @config.fetch('format', DEFAULT_FORMAT)
  end

  # Runs `yt-dlp` with the given command-line +args+.
  def run(args, parent: Async::Task.current, **opts)
    command = build_command(args)

    logger.debug("starting yt-dlp with the following command: #{command.inspect}")

    parent.async do
      Open3.popen3(*command, **opts) do |_stdin, stdout, stderr, wait_thr|
        exit_status = wait_thr.value

        if exit_status.success?
          buf = stdout.read
          logger.debug('yt-dlp finished with success')

          JSON.parse(buf)
        else
          buf = stderr.read
          logger.error("yt-dlp finished with error: #{buf}")
          raise Error, buf
        end
      end
    end
  end

  # Attempts to download videos from the given +url+.
  def download(url, output_dir: Dir.pwd, extra_args: [], format: @format, parent: Async::Task.current)
    parent.async do |task|
      args = [
        url,
        '--output', '%(id)s.%(ext)s',
        '--dump-single-json',
        '--no-simulate'
      ]

      args += ['-f', format] if format
      # args += ['--merge-output-format', @container] if @container
      args += extra_args

      run(args, chdir: output_dir, parent: task).wait
    end
  end

  def build_command(args)
    @command + args
  end
end
