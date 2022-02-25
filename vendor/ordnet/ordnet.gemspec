require_relative 'lib/ordnet/version'

Gem::Specification.new do |s|
  s.name = 'ordnet'
  s.version = Ordnet::Version
  s.summary = 'Ordnet result page parser'
  s.author = 'Mikkel Kroman'
  s.email = 'mk@maero.dk'
  s.files = Dir.glob('lib/**.rb')

  s.add_runtime_dependency 'nokogiri', '~> 1.6'
end
