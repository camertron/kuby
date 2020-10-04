# typed: true
require 'kuby/version'
require 'gli'

module Kuby
  class Commands
    extend GLI::App

    # GLI doesn't have a wildcard option, so it's impossible to tell it to
    # slurp up all args after a certain point. In our case, we want to be
    # able to invoke `rails` commands and pass through all the original
    # flags, switches, etc. To get around GLI's limitations, we identify
    # `rails` commands in this hijacked `run` method and only use GLI to
    # parse global options (like -e). The rest of the Rails options are
    # captured in an instance variable and thereby made available to the
    # Rails command handlers defined below. We use Module#prepend here to
    # avoid the usual series of cryptic alias_method calls (note that there
    # is no singleton class version of #prepend in the Ruby language).
    singleton_class.send(:prepend, Module.new do
      def run(args)
        if idx = args.index('rails') || idx = args.index('rake')
          @rails_options = args[idx..-1]
          super(args[0..idx])
        else
          super
        end
      end
    end)

    def self.tasks
      Kuby::Tasks.new(Kuby.environment)
    end

    def self.must_be_dev_env!
      raise "Command not supported in the '#{Kuby.environment.name}' environment" unless Kuby.environment.development?
    end

    program_desc 'Kuby command-line interface. Kuby is a convention '\
      'over configuration approach for running Rails apps in Kubernetes.'

    version Kuby::VERSION

    subcommand_option_handling :normal
    arguments :loose

    desc 'The Kuby environment to use. Overrides KUBY_ENV.'
    flag %i[e environment], type: String, required: false

    desc 'Path to your Kuby config file. Overrides KUBY_CONFIG.'
    default_value './kuby.rb'
    flag %i[c config]

    pre do |global_options, _options, _args|
      Kuby.env = global_options[:environment] if global_options[:environment]
      Kuby.load!(global_options[:config])

      # GLI will abort unless this block returns a truthy value
      true
    end

    # These are only stubs included to fill out the help screens. Rails
    # commands are handled by the RailsCommands class.
    desc 'Runs a Rails command.'
    command :rails do |rc|
      rc.action do |_global_options, _options, _args|
        must_be_dev_env!
        exit 1 unless tasks.dev_deployment_ok
        Kuby::RailsCommands.run(@rails_options)
      end

      rc.desc 'Runs the rails server (run `rails server --help` for options)'
      rc.command [:server, :s] do |c|
        c.action do |_global_options, _options, _args|
          must_be_dev_env!
          exit 1 unless tasks.dev_deployment_ok
          Kuby::RailsCommands.run(@rails_options)
        end
      end

      rc.desc 'Runs a script in the Rails environment (run `rails runner --help` for options)'
      rc.command [:runner, :r] do |c|
        c.action do |_global_options, _options, _args|
          must_be_dev_env!
          exit 1 unless tasks.dev_deployment_ok
          Kuby::RailsCommands.run(@rails_options)
        end
      end

      rc.desc 'Starts an interactive Ruby console with the Rails environment loaded '\
        '(run `rails console --help` for options)'
      rc.command [:console, :c] do |c|
        c.action do |_global_options, _options, _args|
          must_be_dev_env!
          exit 1 unless tasks.dev_deployment_ok
          Kuby::RailsCommands.run(@rails_options)
        end
      end
    end

    desc 'Runs a rake task.'
    command :rake do |rc|
      rc.action do |_global_options, _options, _args|
        must_be_dev_env!
        exit 1 unless tasks.dev_deployment_ok
        Kuby::RailsCommands.run(@rails_options)
      end
    end

    desc 'Builds the Docker image.'
    command :build do |c|
      c.action do |_global_options, _options, _args|
        tasks.build
      end
    end

    desc 'Pushes the Docker image to the configured registry.'
    command :push do |c|
      c.action do |_global_options, _options, _args|
        tasks.push
      end
    end

    desc 'Gets your Kubernetes cluster ready to run your Rails app.'
    command :setup do |c|
      c.action do |_global_options, _options, _args|
        tasks.setup
      end
    end

    desc 'Prints the effective Dockerfile used to build the Docker image.'
    command :dockerfile do |c|
      c.action do |_global_options, _options, _args|
        tasks.print_dockerfile
      end
    end

    desc 'Deploys the application.'
    command :deploy do |c|
      c.desc 'The Docker tag to deploy. Defaults to the most recent tag.'
      c.flag %i[t tag], required: false
      c.action do |_global_options, options, _args|
        tasks.deploy(options[:tag])
      end
    end

    desc 'Rolls back to the previous Docker tag.'
    command :rollback do |c|
      c.action do |_global_options, _options, _args|
        tasks.rollback
      end
    end

    desc 'Prints the effective Kubernetes resources that will be applied on deploy.'
    command :resources do |c|
      c.action do |_global_options, _options, _args|
        tasks.print_resources
      end
    end

    desc 'Prints out the contents of the kubeconfig Kuby is using to communicate with your cluster.'
    command :kubeconfig do |c|
      c.action do |_global_options, _options, _args|
        tasks.print_kubeconfig
      end
    end

    desc 'Runs an arbitrary kubectl command.'
    command :kubectl do |c|
      c.desc 'Prefixes the kubectl command with the namespace associated with '\
        'the current environment. For example, if the Kuby env is "production", '\
        'this option will prefix the kubectl command with "-n myapp-production".'
      c.switch %i[N namespaced], default: false
      c.action do |_global_options, options, args|
        if options[:namespaced]
          # sorry Demeter
          namespace = Kuby.definition.environment.kubernetes.namespace.metadata.name
          args = ['-n', namespace, *args]
        end

        tasks.kubectl(*args)
      end
    end

    desc 'Runs commands, etc against the Kubernetes cluster.'
    command :remote do |rc|
      rc.desc 'Tails (i.e. continuously streams) the Rails log from your running application.'
      rc.command :logs do |c|
        c.action do |_global_options, _options, _args|
          exit 1 unless tasks.dev_deployment_ok
          tasks.remote_logs
        end
      end

      rc.desc 'Lists running Kubernetes pods.'
      rc.command :status do |c|
        c.action do |_global_options, _options, _args|
          exit 1 unless tasks.dev_deployment_ok
          tasks.remote_status
        end
      end

      rc.desc 'Runs an arbitrary command inside a running Rails pod.'
      rc.command :exec do |c|
        c.action do |_global_options, _options, args|
          exit 1 unless tasks.dev_deployment_ok
          tasks.remote_exec(args)
        end
      end

      rc.desc 'Establishes a shell inside a running Rails pod.'
      rc.command :shell do |c|
        c.action do |_global_options, _options, _args|
          exit 1 unless tasks.dev_deployment_ok
          tasks.remote_shell
        end
      end

      rc.desc 'Establishes a Rails console inside a running Rails pod.'
      rc.command :console do |c|
        c.action do |_global_options, _options, _args|
          exit 1 unless tasks.dev_deployment_ok
          tasks.remote_console
        end
      end

      rc.desc 'Establishes a database console inside a running Rails pod.'
      rc.command :dbconsole do |c|
        c.action do |_global_options, _options, _args|
          exit 1 unless tasks.dev_deployment_ok
          tasks.remote_dbconsole
        end
      end

      rc.desc "Restarts the Rails app's web pods."
      rc.command :restart do |c|
        c.action do |_global_options, _options, _args|
          exit 1 unless tasks.dev_deployment_ok
          tasks.remote_restart
        end
      end
    end
  end
end
