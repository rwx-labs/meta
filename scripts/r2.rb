# frozen_string_literal: true

require 'aws-sdk-s3'
require 'semantic_logger'

Blur::Script :r2 do
  include SemanticLogger::Loggable

  Author 'Mikkel Kroman <mk@maero.dk>'
  Version '1.0'
  Description 'Client API for uploading and downloading files from a R2 bucket'

  # Raised when a configuration key is missing.
  class MissingConfigError < StandardError; end

  # The default prefix to use when handling objects.
  DEFAULT_KEY_PREFIX = ''

  # The default ACL value when creating new objects.
  DEFAULT_ACL = 'public-read'

  # Set of configuration options for the script.
  CONFIGURATION_OPTIONS = {
    'access_key_id' => {
      'env' => 'R2_ACCESS_KEY_ID'
    },
    'secret_access_key' => {
      'env' => 'R2_SECRET_ACCESS_KEY'
    },
    'endpoint' => {
      'env' => 'R2_ENDPOINT',
      'optional' => true
    },
    'region' => {
      'env' => 'R2_REGION'
    },
    'bucket_name' => {
      'env' => 'R2_BUCKET_NAME'
    },
    'prefix' => {
      'env' => 'R2_PREFIX',
      'optional' => true
    }
  }.freeze

  def initialize
    load_config!

    options = {
      access_key_id: @access_key_id,
      secret_access_key: @secret_access_key,
      region: @region
    }

    options[:endpoint] = @endpoint if @endpoint

    @client = Aws::S3::Client.new(options)
  end

  # Uploads the given +path_or_io+ to the bucket using +key+.
  #
  # @return [Hash] the object on success
  def upload(path_or_io, key, acl = DEFAULT_ACL, parent: Async::Task.current)
    parent.async do
      close_after = false

      # Open anything that isn't IO-like as a file
      unless path_or_io.is_a?(IO) || path_or_io.is_a?(StringIO)
        path_or_io = File.open(path_or_io)
        close_after = true
      end

      options = {
        acl:,
        key:,
        body: path_or_io,
        bucket: @bucket_name
      }

      object = @client.put_object(options)
      object
    ensure
      path_or_io.close if close_after
    end
  end

  def head_object(key, parent: Async::Task.current)
    parent.async do
      @client.head_object(bucket: @bucket_name, key:)
    end
  end

  # @return [Boolean] true if an object with the given key exists.
  def object_exists?(key, parent: Async::Task.current)
    parent.async do
      true if head_object(key, parent:).wait
    rescue Aws::S3::Errors::Forbidden, Aws::S3::Errors::NotFound
      false
    end
  end

  # @return [String] the public url for a given objecy key.
  def get_object_public_url(key)
    object = Aws::S3::Object.new(@bucket_name, key, client: @client)
    object.public_url
  end

  protected

  # Sets instance variables based on `CONFIGURATION_OPTIONS`.
  def load_config!
    CONFIGURATION_OPTIONS.each do |key, params|
      env = params['env']
      optional = params['optional']
      value = @config[key]
      value = ENV.fetch(env, nil) if value.nil? && env

      raise MissingConfigError, config_missing_error_message(key, params) unless value || optional

      instance_variable_set(:"@#{key}", value)
    end
  end

  # Generates a helpful error message when a configuration value is missing.
  def config_missing_error_message(key, params)
    env = params['env']

    error_message = "missing configuration key `#{key}'"
    error_message += " (or env #{env})" if env

    error_message
  end
end
