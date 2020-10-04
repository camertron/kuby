# typed: false
require 'base64'

module Kuby
  module Kubernetes
    class RegistrySecret < ::KubeDSL::DSL::V1::Secret
      array_field(:docker_config) { DockerConfig.new }

      def initialize(&block)
        instance_eval(&block) if block
      end

      def serialize
        super.tap do |result|
          result[:type] = 'kubernetes.io/dockerconfigjson'
          result[:data] = {
            ".dockerconfigjson": Base64.strict_encode64({
              auths: docker_configs.each_with_object({}) do |dc, ret|
                ret.merge!(dc.serialize)
              end
            }.to_json)
          }
        end
      end
    end
  end
end
