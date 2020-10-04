# typed: true
module Kuby
  class Args
    attr_reader :args, :flag_aliases

    def initialize(args, flag_aliases = [])
      @args = args
      @flag_aliases = flag_aliases
    end

    def [](flag)
      idx = find_arg_index(flag)
      idx ? args[idx] : nil
    end

    def []=(flag, new_value)
      idx = find_arg_index(flag)

      if idx
        args[idx] = new_value
      else
        @args += [flag, new_value]
      end
    end

    private

    def find_arg_index(flag)
      idx = args.find_index do |arg|
        flag_aliases.any? { |fas| fas.include?(arg) && fas.include?(flag) }
      end

      idx ? idx + 1 : nil
    end
  end

  class RailsCommands
    PREFIX = %w[bundle exec].freeze
    SERVER_ARG_ALIASES = [['--binding', '-b'], ['-p', '--port']].freeze

    class << self
      def run(args = ARGV)
        command = args[0]

        if command == 'rails'
          subcommand = args[1]
          arglist = nil

          case subcommand
          when 'server', 's'
            arglist = Args.new([*PREFIX, *args], SERVER_ARG_ALIASES)
            arglist['-b'] ||= '0.0.0.0'
            arglist['-p'] ||= '3000'
          end
        end

        setup

        arglist ||= Args.new([*PREFIX, *args])
        tasks = Kuby::Tasks.new(environment)
        tasks.remote_exec(arglist.args)
      end

      private

      def setup
        require 'kuby'
        Kuby.load!
      end

      def kubernetes_cli
        kubernetes.provider.kubernetes.cli
      end

      def kubernetes
        environment.kubernetes
      end

      def environment
        Kuby.definition.environment
      end
    end
  end
end
