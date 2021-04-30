# typed: true
module Kuby
  class Environment
    attr_reader :name, :definition
    attr_accessor :configured

    alias_method :configured?, :configured

    def initialize(name, definition, &block)
      @name = name
      @definition = definition
    end

    def docker(&block)
      @docker ||= Docker::Spec.new(self)
      # @docker ||= if development?
      #   Docker::DevSpec.new(self)
      # else
      #   Docker::Spec.new(self)
      # end

      @docker.instance_eval(&block) if block
      @docker
    end

    def kubernetes(&block)
      @kubernetes ||= Kubernetes::Spec.new(self)
      @kubernetes.instance_eval(&block) if block
      @kubernetes
    end

    def app_name
      definition.app_name
    end

    def development?
      name == 'development'
    end
  end
end
