# typed: true
require 'kube-dsl'

module Kuby
  module Plugins
    class NginxIngress < ::Kuby::Plugin
      class Config
        extend ::KubeDSL::ValueFields

        value_fields :provider
      end

      VERSION = '0.27.1'.freeze
      DEFAULT_PROVIDER = 'cloud-generic'.freeze
      NAMESPACE = 'ingress-nginx'.freeze
      SERVICE_NAME = 'ingress-nginx'.freeze

      SETUP_RESOURCES = [
        "https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-#{VERSION}/deploy/static/mandatory.yaml",
        "https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-#{VERSION}/deploy/static/provider/%{provider}.yaml"
      ].freeze

      def configure(&block)
        @config.instance_eval(&block) if block
      end

      def setup
        Kuby.logger.info('Deploying nginx ingress resources')

        if already_deployed?
          Kuby.logger.info('Nginx ingress already deployed, skipping')
          return
        end

        SETUP_RESOURCES.each do |uri|
          uri = format(uri, provider: @config.provider || DEFAULT_PROVIDER)
          kubernetes_cli.apply_uri(uri)
        end

        Kuby.logger.info('Nginx ingress resources deployed!')
      rescue StandardError => e
        Kuby.logger.fatal(e.message)
        raise
      end

      def namespace
        NAMESPACE
      end

      def service_name
        SERVICE_NAME
      end

      private

      def already_deployed?
        kubernetes_cli.get_object('Service', 'ingress-nginx', 'ingress-nginx')
        true
      rescue KubernetesCLI::GetResourceError
        false
      end

      def after_initialize
        @config = Config.new
      end

      def kubernetes_cli
        environment.kubernetes.provider.kubernetes_cli
      end
    end
  end
end
