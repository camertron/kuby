$:.unshift File.join(File.dirname(__FILE__), 'lib')
require 'kuby/version'

Gem::Specification.new do |s|
  s.name     = 'kuby-core'
  s.version  = ::Kuby::VERSION
  s.authors  = ['Cameron Dutro']
  s.email    = ['camertron@gmail.com']
  s.homepage = 'http://github.com/getkuby/kuby-core'

  s.description = s.summary = 'Deploy your Rails app onto Kubernetes the easy way.'

  s.platform = Gem::Platform::RUBY

  s.add_dependency 'colorize', '~> 0.8'
  s.add_dependency 'docker-remote', '~> 0.1'
  s.add_dependency 'gli', '~> 2.0'
  s.add_dependency 'helm-cli', '~> 0.3'
  # See: https://github.com/Shopify/krane/pull/720
  # See: https://github.com/Shopify/krane/blob/master/CHANGELOG.md#114
  s.add_dependency 'krane', '>= 1.1.4', '< 2.0'
  s.add_dependency 'kube-dsl', '~> 0.4'
  s.add_dependency 'kubernetes-cli', '~> 0.3'
  s.add_dependency 'kuby-cert-manager', '>= 0.3'
  s.add_dependency 'kuby-kube-db', '>= 0.6'
  s.add_dependency 'railties', '>= 5.1'
  s.add_dependency 'rouge', '~> 3.0'
  s.add_dependency 'sorbet-runtime-stub', '~> 0.2'

  s.add_development_dependency 'rspec'

  s.require_path = 'lib'
  s.executables << 'kuby'

  s.files = Dir['{lib,spec}/**/*', 'Gemfile', 'LICENSE', 'CHANGELOG.md', 'README.md', 'Rakefile', 'kuby-core.gemspec']
end
