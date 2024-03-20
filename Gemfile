# frozen_string_literal: true

source 'https://rubygems.org'

# General dependencies
gem 'blur', '~> 3.0.pre.alpha', git: 'https://github.com/mkroman/blur', branch: 'main'

gem 'httpx', '~> 1.2'

# Used by the `dig' script
gem 'net-dns', '~> 0.20', require: 'net/dns'
# Used by the `r2` script
gem 'aws-sdk-s3', '~> 1.146'
gem 'activesupport', '~> 7.1'
gem 'oj', '~> 3.16'
gem 'multi_json', '~> 1.15'

# Used by the `tvmaze` script
gem 'dotiw', '~> 5.3'

# # Required by multiple scripts.
gem 'nokogiri', '~> 1.16'

# # Required by the ddo script.
gem 'ordnet', path: 'vendor/ordnet'

group :development do
  gem 'solargraph'
end
