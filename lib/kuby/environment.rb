# typed: true
module Kuby
  class Environment
    attr_reader :name, :definition
    attr_accessor :configured

    alias configured? configured

    def initialize(name, definition)
      @name = name
      @definition = definition
    end

    def docker(&block)
      @docker ||= if development?
                    Docker::DevSpec.new(self)
                  else
                    Docker::Spec.new(self)
                  end

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
