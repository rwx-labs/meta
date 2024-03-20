# frozen_string_literal: true

require 'open3'

require 'async/barrier'
require 'semantic_logger'
require 'httpx'

Blur::Script :tiktok do
  include Blur::URLHandling
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Mirroring of tiktok videos'

  class TiktokError < StandardError; end

  def initialize
    @http = HTTPX.with(:compression).with_timeout(total_timeout: 30)
  end

  register_url!('www.tiktok.com') do |_user, channel, url|
    handle_video_link(channel, url)
  end

  register_url!('vm.tiktok.com') do |_user, channel, url|
    handle_shortened_video_link(channel, url)
  end

  def handle_shortened_video_link(channel, url)
    Async do |task|
      logger.debug("resolving shortened link #{url}")

      video_url = get_video_url(url, parent: task).wait
      raise TiktokError, 'Could not resolve video url' unless video_url

      handle_video_link(channel, video_url, parent: task)
    end
  end

  def handle_video_link(channel, url, parent: Async::Task.current)
    logger.debug("getting oembed data for tiktok video link #{url}")

    oembed = get_oembed(url, parent:).wait
    raise TiktokError, 'Could not retrieve ombed data for video' unless oembed

    type = oembed['type']
    video_id = oembed['embed_product_id']

    if type != 'video'
      logger.debug("Skipping tiktok link as it's not a video")
      return
    end

    # Send a summary of the link to the channel
    channel.say(format_video_oembed_summary(oembed))

    parent.async do |task|
      if (result = video_already_uploaded?(video_id).wait)
        url = public_url_for_video(video_id)
        logger.debug("the video has already been uploaded, sending link: #{result}")
        channel.say("\x0310> #{url}")
        next
      end

      logger.debug("downloading tiktok video with id #{video_id} and url #{url}")

      output_dir = Dir.mktmpdir
      result_json = download_video(url, output_dir:).wait

      # Process each downloaded file
      barrier = Async::Barrier.new(parent: task)
      result_json['requested_downloads'].each do |download|
        barrier.async do |subtask|
          path = download['filepath']

          logger.warn("the video is in a format that isn't supported by browsers") if download['vcodec'] != 'h264'

          url = upload_video(path, parent: subtask).wait
          logger.debug("uploaded to s3: #{url}")

          channel.say("\x0310> #{url}")
        end
      end

      barrier.wait

      # Remove any downloaded files
      FileUtils.remove_dir(output_dir, true)
    end
  rescue HTTPX::HTTPError => e
    channel.say("\x0310> HTTP error: #{e.status}")
  rescue HTTPX::ConnectTimeoutError => _e
    channel.say("\x0310> HTTP connection timed out")
  rescue StandardError => e
    logger.error("Error", e)
    channel.say("\x0310> Error: #{e}")
  end

  def video_already_uploaded?(video_id, parent: Async::Task.current)
    parent.async do
      key = "~meta/tiktok/#{video_id}.mp4"
      script(:r2).object_exists?(key).wait
    end
  end

  def upload_video(path, parent: Async::Task.current)
    parent.async do
      filename = File.basename(path)
      video_id = File.basename(path, '.*')
      key = "~meta/tiktok/#{filename}"

      logger.debug("uploading file #{path} to s3 using key #{key}")

      result = script(:r2).upload(path, key, parent:).wait
      return nil unless result

      logger.debug("uploaded to s3: #{result}")

      public_url_for_video(video_id)
    end
  end

  # Formats the oembed data as a human-readable description of the link.
  def format_video_oembed_summary(oembed)
    title = oembed['title']
    author = oembed['author_name']

    "\x0310> “\x0f#{title&.strip}\x0310” is a TikTok video by\x0f #{author&.strip}"
  end

  # Returns the public viewable url for the given +video_id+.
  def public_url_for_video(video_id)
    public_url = URI('https://pub.rwx.im/~meta/tiktok.html')
    public_url.query = video_id
    public_url
  end

  # Returns the oembed details for the given video url.
  def get_oembed(video_url, parent: Async::Task.current)
    parent.async do
      res = @http.get('https://www.tiktok.com/oembed', params: { 'url' => video_url.to_s })
      res.raise_for_status
      res.json
    rescue HTTPX::HTTPError => e
      raise TiktokError, "Could not fetch oembed data (http error #{e.status})"
    end
  end

  # Downloads the video from the given +video_url+ and yields the temporary
  # directory where it's stored
  def download_video(video_url, **opts, &block)
    script(:yt_dlp).download(
      video_url.to_s,
      format: 'bestvideo*[vcodec=h264]+bestaudio*',
      extra_args: ['--merge-output-format', 'mp4'],
      **opts,
      &block
    )
  end

  # Returns the URL to the full video for the given vm.tiktok.com link
  def get_video_url(url, parent: Async::Task.current)
    return unless url.host == 'vm.tiktok.com'

    parent.async do
      res = @http.get(url.to_s)
      res.raise_for_status
      res.headers['location']
    end
  end
end
