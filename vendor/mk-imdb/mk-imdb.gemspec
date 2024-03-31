require_relative 'lib/mk/imdb/version'

Gem::Specification.new do |s|
  s.name = 'mk-imdb'
  s.version = MK::IMDb::Version
  s.summary = 'IMDb movie page parser'
  s.author = 'Mikkel Kroman'
  s.email = 'mk@maero.dk'
  s.files = Dir.glob('lib/**.rb')

  s.add_runtime_dependency 'nokogiri', '~> 1.8'

  s.add_development_dependency 'rspec', '~> 3.7'
end
