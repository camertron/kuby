# typed: strict

require 'docker/remote'

module Kuby
  module Docker
    class Spec
      extend T::Sig

      sig { returns(Environment) }
      attr_reader :environment

      sig { params(environment: Environment).void }
      def initialize(environment)
        @environment = environment

        @credentials = T.let(@credentials, T.nilable(Credentials))
        @setup_phase = T.let(@setup_phase, T.nilable(SetupPhase))
        @package_phase = T.let(@package_phase, T.nilable(PackagePhase))
        @bundler_phase = T.let(@bundler_phase, T.nilable(BundlerPhase))
        @yarn_phase = T.let(@yarn_phase, T.nilable(YarnPhase))
        @copy_phase = T.let(@copy_phase, T.nilable(CopyPhase))
        @assets_phase = T.let(@assets_phase, T.nilable(AssetsPhase))
        @webserver_phase = T.let(@webserver_phase, T.nilable(WebserverPhase))
        @metadata = T.let(@metadata, T.nilable(Metadata))

        @distro_spec = T.let(@distro_spec, T.nilable(Distro))
        @cli = T.let(@cli, T.nilable(CLI))
        @remote_client = T.let(@remote_client, T.nilable(::Docker::Remote::Client))
        @tags = T.let(@tags, T.nilable(Tags))
        @layer_stack = T.let(@layer_stack, T.nilable(Kuby::Docker::LayerStack))
      end

      sig { params(image_url: String).void }
      def base_image(image_url)
        setup_phase.base_image = image_url
      end

      sig { params(dir: String).void }
      def working_dir(dir)
        setup_phase.working_dir = dir
      end

      sig { params(env: String).void }
      def rails_env(env)
        setup_phase.rails_env = env
      end

      sig { params(version: String).void }
      def bundler_version(version)
        bundler_phase.version = version
      end

      sig { params(path: String).void }
      def gemfile(path)
        bundler_phase.gemfile = path
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

      sig { params(path: String).void }
      def files(path)
        copy_phase << path
      end

      sig { params(port: String).void }
      def port(port)
        webserver_phase.port = port
      end

      sig { params(url: String).void }
      def image_url(url)
        metadata.image_url = url
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

      sig do
        params(block: T.nilable(T.proc.void)).returns(Credentials)
      end
      def credentials(&block)
        @credentials ||= Credentials.new
        @credentials.instance_eval(&block) if block
        @credentials
      end

      sig { returns(Dockerfile) }
      def to_dockerfile
        Dockerfile.new.tap do |df|
          layer_stack.each { |layer| layer.apply_to(df) }
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

      sig { returns(BundlerPhase) }
      def bundler_phase
        @bundler_phase ||= BundlerPhase.new(environment)
      end

      sig { returns(YarnPhase) }
      def yarn_phase
        @yarn_phase ||= YarnPhase.new(environment)
      end

      sig { returns(CopyPhase) }
      def copy_phase
        @copy_phase ||= CopyPhase.new(environment)
      end

      sig { returns(AssetsPhase) }
      def assets_phase
        @assets_phase ||= AssetsPhase.new(environment)
      end

      sig { returns(WebserverPhase) }
      def webserver_phase
        @webserver_phase ||= WebserverPhase.new(environment)
      end

      sig { returns(Metadata) }
      def metadata
        @metadata ||= Metadata.new(environment)
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
      def previous_tag(current_tag)
        t = tags.previous_timestamp_tag(current_tag)

        raise MissingTagError, 'could not find previous timestamped tag' unless t

        t.to_s
      end

      sig { returns(CLI) }
      def cli
        @cli ||= Docker::CLI.new
      end

      sig { returns(::Docker::Remote::Client) }
      def remote_client
        @remote_client ||= ::Docker::Remote::Client.new(
          metadata.image_host, metadata.image_repo,
          credentials.username, credentials.password
        )
      end

      sig { returns(Distro) }
      def distro_spec
        @distro_spec ||= if distro_klass = Kuby.distros[metadata.distro]
                           distro_klass.new(self)
                         else
                           raise MissingDistroError, "distro '#{metadata.distro}' hasn't been registered"
                         end
      end

      sig { returns(Tags) }
      def tags
        @tags ||= Tags.new(cli, remote_client, metadata)
      end

      private

      sig { returns(Kuby::Docker::LayerStack) }
      def layer_stack
        @layer_stack ||= Kuby::Docker::LayerStack.new.tap do |stack|
          stack.use(:setup_phase, setup_phase)
          stack.use(:package_phase, package_phase)
          stack.use(:bundler_phase, bundler_phase)
          stack.use(:yarn_phase, yarn_phase)
          stack.use(:copy_phase, copy_phase)
          stack.use(:assets_phase, assets_phase)
          stack.use(:webserver_phase, webserver_phase)
        end
      end
    end
  end
end
