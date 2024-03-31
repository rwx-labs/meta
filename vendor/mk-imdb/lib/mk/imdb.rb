# frozen_string_literal: true

require 'nokogiri'

require_relative 'imdb/movie'
require_relative 'imdb/version'

module MK
  module IMDb
    # Indicates that there was an error when parsing the movie page.
    class MovieDataError < StandardError; end
  end
end
