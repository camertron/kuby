# typed: true
module Kuby
  class Definition
    attr_reader :app_name

    def initialize(app_name)
      @app_name = app_name
    end

    def environment(name = Kuby.env, &block)
      name = name.to_s

      environments[name] ||= Environment.new(name, self)

      environments[name].instance_eval(&block) if block_given?

      environments[name]
    end

    def environments
      @environments ||= {}
    end
  end
end
