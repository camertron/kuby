# typed: true
module Kuby
  module Middleware
    class HealthCheck
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call(env)
        return [204, {}, ['']] if env.fetch('PATH_INFO') == '/healthz'

        app.call(env)
      end
    end
  end
end
