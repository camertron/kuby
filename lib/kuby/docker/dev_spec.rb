# typed: strict

module Kuby
  module Docker
    class WebserverDevPhase < Layer
      extend T::Sig

      DEFAULT_PORT = T.let('3000'.freeze, String)

      sig { params(port: String).void }
      attr_writer :port

      sig { params(environment: Environment).void }
      def initialize(environment)
        super

        @port = T.let(@port, T.nilable(String))
      end

      sig { override.params(dockerfile: Dockerfile).void }
      def apply_to(dockerfile)
        dockerfile.expose(port)
      end

      sig { returns(String) }
      def port
        @port || DEFAULT_PORT
      end
    end

    class DevSpec
      extend T::Sig

      sig { returns(Environment) }
      attr_reader :environment

      sig { params(environment: Environment).void }
      def initialize(environment)
        @environment = environment

        @setup_phase = T.let(@setup_phase, T.nilable(SetupPhase))
        @package_phase = T.let(@package_phase, T.nilable(PackagePhase))
        @webserver_phase = T.let(@webserver_phase, T.nilable(WebserverDevPhase))
        @metadata = T.let(@metadata, T.nilable(Metadata))
        @distro_spec = T.let(@distro_spec, T.nilable(Distro))
        @cli = T.let(@cli, T.nilable(CLI))
        @tags = T.let(@tags, T.nilable(LocalTags))
        @layer_stack = T.let(@layer_stack, T.nilable(Docker::LayerStack))
      end

      sig { params(dir: String).void }
      def working_dir(dir)
        setup_phase.working_dir = dir
      end

      sig { params(env: String).void }
      def rails_env(env)
        setup_phase.rails_env = env
      end

      sig do
        params(
          package_name: Symbol,
          version: T.nilable(String)
        )
          .void
      end
      def package(package_name, version = nil)
        package_phase.add(package_name, version)
      end

      sig { params(distro_name: Symbol).void }
      def distro(distro_name)
        metadata.distro = distro_name
        @distro_spec = nil
      end

      sig { params(port: String).void }
      def port(port)
        webserver_phase.port = port
      end

      sig do
        params(
          name: Symbol,
          layer: T.nilable(Layer),
          block: T.nilable(T.proc.params(df: Dockerfile).void)
        )
          .void
      end
      def use(name, layer = nil, &block)
        layer_stack.use(name, layer, &block)
      end

      sig do
        params(
          name: Symbol,
          layer: T.nilable(T.any(Layer, T::Hash[Symbol, T.untyped])),
          options: T::Hash[Symbol, T.untyped],
          block: T.nilable(T.proc.params(df: Dockerfile).void)
        )
          .void
      end
      def insert(name, layer = nil, options = {}, &block)
        layer_stack.insert(name, layer, options, &block)
      end

      sig { params(name: Symbol).void }
      def delete(name)
        layer_stack.delete(name)
      end

      sig { params(name: Symbol).returns(T::Boolean) }
      def exists?(name)
        layer_stack.includes?(name)
      end

      sig { returns(Dockerfile) }
      def to_dockerfile
        Dockerfile.new.tap do |df|
          layer_stack.each { |layer| layer.apply_to(df) }
          df.cmd("#{distro_spec.shell_exe} -c 'while test 1; do sleep 5; done'")
        end
      end

      sig { returns(SetupPhase) }
      def setup_phase
        @setup_phase ||= SetupPhase.new(environment)
      end

      sig { returns(PackagePhase) }
      def package_phase
        @package_phase ||= PackagePhase.new(environment)
      end

      sig { returns(WebserverDevPhase) }
      def webserver_phase
        @webserver_phase ||= WebserverDevPhase.new(environment)
      end

      sig { returns(Metadata) }
      def metadata
        @metadata ||= Metadata.new(environment)
      end

      sig { returns(Distro) }
      def distro_spec
        @distro_spec ||= if distro_klass = Kuby.distros[metadata.distro]
                           distro_klass.new(self)
                         else
                           raise MissingDistroError, "distro '#{metadata.distro}' hasn't been registered"
                         end
      end

      sig { returns(String) }
      def tag
        t = ENV.fetch('KUBY_DOCKER_TAG') do
          tags.latest_timestamp_tag
        end

        raise MissingTagError, 'could not find latest timestamped tag' unless t

        t.to_s
      end

      sig { params(current_tag: String).returns(String) }
      def previous_tag(_current_tag)
        raise MissingTagError, 'cannot roll back in the development environment'
      end

      sig { returns(CLI) }
      def cli
        @cli ||= Docker::CLI.new
      end

      private

      sig { returns(LocalTags) }
      def tags
        @tags ||= LocalTags.new(cli, metadata)
      end

      sig { returns(Docker::LayerStack) }
      def layer_stack
        @layer_stack ||= Docker::LayerStack.new.tap do |stack|
          stack.use(:setup_phase, setup_phase)
          stack.use(:package_phase, package_phase)
          stack.use(:webserver_phase, webserver_phase)
        end
      end
    end
  end
end
