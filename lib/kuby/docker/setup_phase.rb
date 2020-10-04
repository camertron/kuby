# typed: strict

module Kuby
  module Docker
    class SetupPhase < Layer
      extend T::Sig

      DEFAULT_WORKING_DIR = T.let('/usr/src/app'.freeze, String)

      sig { returns(T.nilable(String)) }
      attr_reader :base_image

      sig { params(base_image: String).void }
      attr_writer :base_image

      sig { returns(T.nilable(String)) }
      attr_reader :working_dir

      sig { params(working_dir: String).void }
      attr_writer :working_dir

      sig { returns(T.nilable(String)) }
      attr_reader :rails_env

      sig { params(rails_env: String).void }
      attr_writer :rails_env

      sig { params(environment: Environment).void }
      def initialize(environment)
        super

        @base_image = T.let(@base_image, T.nilable(String))
        @working_dir = T.let(@working_dir, T.nilable(String))
        @rails_env = T.let(@rails_env, T.nilable(String))
      end

      sig { override.params(dockerfile: Dockerfile).void }
      def apply_to(dockerfile)
        dockerfile.from(base_image || default_base_image)
        dockerfile.workdir(working_dir || DEFAULT_WORKING_DIR)
        dockerfile.env("RAILS_ENV=#{rails_env || Kuby.env}")
        dockerfile.env("KUBY_ENV=#{Kuby.env}")
        dockerfile.arg('RAILS_MASTER_KEY')
      end

      private

      sig { returns(String) }
      def default_base_image
        case metadata.distro
        when :debian
          "ruby:#{RUBY_VERSION}"
        when :alpine
          "ruby:#{RUBY_VERSION}-alpine"
        else
          raise MissingDistroError, "distro '#{metadata.distro}' hasn't been registered"
        end
      end
    end
  end
end
