# typed: strict

module Kuby
  module Docker
    class WebserverPhase < Layer
      extend T::Sig

      class Webserver
        extend T::Sig
        extend T::Helpers

        abstract!

        sig { returns(WebserverPhase) }
        attr_reader :phase

        sig { params(phase: WebserverPhase).void }
        def initialize(phase)
          @phase = phase
        end

        sig { abstract.params(dockerfile: Dockerfile).void }
        def apply_to(dockerfile); end
      end

      class Puma < Webserver
        sig { override.params(dockerfile: Dockerfile).void }
        def apply_to(dockerfile)
          dockerfile.cmd(
            'puma',
            '--workers', '4',
            '--bind', 'tcp://0.0.0.0',
            '--port', phase.port,
            '--pidfile', './server.pid',
            './config.ru'
          )

          dockerfile.expose(phase.port)
        end
      end

      DEFAULT_PORT = T.let('8080', String)
      WEBSERVER_MAP = T.let({ puma: Puma }.freeze, T::Hash[Symbol, T.class_of(Webserver)])

      sig { params(port: String).void }
      attr_writer :port

      sig { returns(T.nilable(Symbol)) }
      attr_reader :webserver

      sig { params(webserver: Symbol).void }
      attr_writer :webserver

      sig { override.params(environment: Environment).void }
      def initialize(environment)
        super

        @port = T.let(@port, T.nilable(String))
        @webserver = T.let(@webserver, T.nilable(Symbol))
      end

      sig { override.params(dockerfile: Dockerfile).void }
      def apply_to(dockerfile)
        ws = webserver || default_webserver
        ws_class = WEBSERVER_MAP[T.must(ws)]
        raise "No webserver named #{ws}" unless ws_class

        ws_class.new(self).apply_to(dockerfile)
      end

      sig { returns(String) }
      def port
        @port || DEFAULT_PORT
      end

      private

      sig { returns(T.nilable(Symbol)) }
      def default_webserver
        :puma if Gem.loaded_specs.include?('puma')
      end
    end
  end
end
