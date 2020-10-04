# typed: strict

require 'pathname'

module Kuby
  module Docker
    class BundlerPhase < Layer
      extend T::Sig

      DEFAULT_WITHOUT = T.let(
        %w[development test deploy].freeze, T::Array[String]
      )

      sig { returns(T.nilable(String)) }
      attr_reader :version

      sig { params(version: String).void }
      attr_writer :version

      sig { returns(T.nilable(String)) }
      attr_reader :gemfile

      sig { params(gemfile: String).void }
      attr_writer :gemfile

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :without

      sig { params(without: T::Array[String]).void }
      attr_writer :without

      sig { params(environment: Environment).void }
      def initialize(environment)
        super

        @version = T.let(@version, T.nilable(String))
        @gemfile = T.let(@gemfile, T.nilable(String))
        @without = T.let(@without, T.nilable(T::Array[String]))
      end

      sig { override.params(dockerfile: Dockerfile).void }
      def apply_to(dockerfile)
        gf = gemfile || default_gemfile
        lf = "#{gf}.lock"
        v = version || default_version
        wo = without || DEFAULT_WITHOUT

        dockerfile.run('gem', 'install', 'bundler', '-v', v)

        # bundle install
        dockerfile.copy(gf, '.')
        dockerfile.copy(lf, '.')

        # set bundle path so docker will cache the bundle
        dockerfile.run('mkdir', './bundle')
        dockerfile.env('BUNDLE_PATH=./bundle')

        dockerfile.env("BUNDLE_WITHOUT='#{wo.join(' ')}'") unless wo.empty?

        dockerfile.run(
          'bundle', 'install',
          '--jobs', '$(nproc)',
          '--retry', '3',
          '--gemfile', gf
        )

        # generate binstubs and add the bin directory to our path
        dockerfile.run('bundle', 'binstubs', '--all')
        dockerfile.env("PATH=./bin:$PATH")
      end

      private

      sig { returns(String) }
      def default_version
        Bundler::VERSION
      end

      sig { returns(String) }
      def default_gemfile
        Bundler
          .definition
          .gemfiles
          .first
          .relative_path_from(Pathname(Dir.getwd))
          .to_s
      end
    end
  end
end
