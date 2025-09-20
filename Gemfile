# frozen_string_literal: true

source 'https://rubygems.org'

# General dependencies
gem 'blur', '~> 3.0.0pre.alpha', git: 'https://github.com/mkroman/blur', branch: 'main'

gem 'httpx', '~> 1.2'
gem 'brotli', '~> 0.6'

# Used by the `dig' script
gem 'net-dns', '~> 0.20', require: 'net/dns'
# Used by the `r2` script
gem 'aws-sdk-s3', '~> 1.146'
gem 'activesupport', '~> 7.1'
gem 'oj', '~> 3.16'
gem 'multi_json', '~> 1.15'

# Used by the `spotify` script
gem 'rspotify', '~> 2.12'

# Used by the `tvmaze` script
gem 'dotiw', '~> 5.3'

# # Required by multiple scripts.
gem 'nokogiri', '~> 1.16'
gem 'htmlentities', '~> 4.3'

# Required by scripts with CLI-like argument parsing.
gem 'optimist', '~> 3.1'

# Required by scripts that allow fuzzy-matching.
gem 'fuzzy_match', '~> 2.1'


# Used by the `unicode-utils` script
gem 'unicode-categories', '~> 1.9'
gem 'unicode-name', '~> 1.12'
gem 'unicode-sequence_name', '~> 1.13'

group :development do
  gem 'solargraph'
end
