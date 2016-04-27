$LOAD_PATH.unshift './lib'

require 'tweeter/version'

Gem::Specification.new do |s|
  s.name        = 'tweeter'
  s.version     = Tweeter::VERSION
  s.summary     = 'Tweeter is a light wrapper around the Twitter REST API'
  s.homepage    = 'https://www.github.com/sukhchander/tweeter'

  s.authors     = ['sukhchander']
  s.email       = 'sukhchander@gmail.com'

  s.files       += %w(README.rdoc)
  s.files       += Dir.glob('lib/**/*')
  s.files       += Dir.glob('test/**/*')

  s.extra_rdoc_files  = %w(README.rdoc)

  s.description = 'Tweeter wraps the Twitter REST API'

  s.add_dependency 'json', '~> 1.8'
  s.add_dependency 'oauth', '~> 0.5'
  s.add_dependency 'mime-types', '~> 3.0'
end