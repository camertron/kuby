# typed: true
module Kuby
  class Spinner
    PIECES = %w[- \\ | /].freeze
    INTERVAL = 0.2  # seconds

    def self.spin(message)
      yield new(message)
    end

    attr_reader :message, :status

    def initialize(message)
      @message = message
      @status = :running
      @thread = Thread.new do
        counter = 0

        loop do
          case status
          when :running
            piece = PIECES[counter % PIECES.size]
            STDOUT.write "\r[#{piece}] #{message}"
            sleep INTERVAL
            counter += 1
          when :success
            STDOUT.write("\r[+] #{message}")
            break
          when :failure
            STDOUT.write("\r[×] #{message}")
            break
          end
        end

        puts
      end
    end

    def success
      @status = :success
      @thread.join
    end

    def failure
      @status = :failure
      @thread.join
    end
  end

  class SetupTask
    attr_reader :message, :callable

    def initialize(message, callable)
      @message = message
      @callable = callable
    end

    def run
      callable.call
    end
  end

  class Pipe
    attr_reader :name, :cli, :out, :err

    def initialize(name, cli)
      @name = name
      @cli = cli
      @out = StringIO.new
      @err = StringIO.new
    end

    def wrap(&block)
      cli.with_pipes(out, err) do
        block.call
      end
    end

    def success?
      cli.last_status.nil? || cli.last_status.success?
    end
  end

  class Pipes
    include Enumerable

    attr_reader :pipes, :ex

    def self.build(clis)
      new(clis.map { |name, cli| Pipe.new(name, cli) })
    end

    def initialize(pipes)
      @pipes = pipes
    end

    def each(&block)
      pipes.each(&block)
    end

    def wrap(&block)
      do_wrap(pipes, &block)
    end

    def success?
      pipes.all?(&:success?) && !ex
    end

    private

    def do_wrap(remaining_pipes, &block)
      if remaining_pipes.empty?
        begin
          yield
        rescue StandardError => e
          @ex = e
        end

        return
      end

      remaining_pipes[0].wrap do
        do_wrap(remaining_pipes[1..-1], &block)
      end
    end
  end

  class SetupTaskList
    attr_reader :tasks, :clis

    def initialize(tasks, clis)
      @tasks = tasks
      @clis = clis
    end

    def run
      tasks.each do |task|
        pipes = Pipes.build(clis)

        Spinner.spin(task.message) do |spinner|
          pipes.wrap { task.run }

          if pipes.success?
            spinner.success
          else
            spinner.failure
            print_error(pipes.ex)

            pipes.each do |pipe|
              print_streams(pipe)
            end

            return false
          end
        end
      end

      true
    end

    private

    def print_streams(pipe)
      unless pipe.out.string.strip.empty?
        puts("========= #{pipe.name.upcase} STDOUT ========")
        puts pipe.out.string
      end

      unless pipe.err.string.strip.empty?
        puts("========= #{pipe.name.upcase} STDERR ========")
        puts pipe.err.string
      end
    end

    def print_error(ex)
      return unless ex

      puts("========= RUBY ERROR ========")
      puts(ex.message)
      puts(ex.backtrace.join("\n"))
    end
  end

  class DevSetup
    attr_reader :environment

    def initialize(environment)
      @environment = environment
    end

    def run
      SetupTaskList.new(setup_tasks, clis).run
    end

    private

    def setup_tasks
      @setup_tasks ||= [
        SetupTask.new(
          'Building dev Docker image', -> { tasks.build }
        ),

        SetupTask.new(
          'Setting up local Kubernetes cluster', -> { tasks.setup }
        ),

        SetupTask.new(
          'Deploying dev environment', -> { tasks.deploy }
        ),

        SetupTask.new(
          'Installing bundler', lambda {
            tasks.remote_system("gem install bundler -v #{Bundler::VERSION}")
          }
        ),

        SetupTask.new(
          'Installing bundled gems', -> { tasks.remote_system('bundle install') }
        ),

        SetupTask.new(
          'Installing Javascript packages', -> { tasks.remote_system('yarn install') }
        ),

        SetupTask.new(
          'Creating database', -> { tasks.remote_system('bundle exec rake db:create') }
        ),

        SetupTask.new(
          'Migrating database', -> { tasks.remote_system('bundle exec rake db:migrate') }
        )
      ]
    end

    def kubernetes
      environment.kubernetes
    end

    def docker
      environment.docker
    end

    def clis
      @clis ||= {
        kubectl: kubernetes.provider.kubernetes_cli,
        helm: kubernetes.provider.helm_cli,
        krane: kubernetes.provider.deployer,
        docker: docker.cli,
        kuby: Kuby.logger
      }
    end

    def tasks
      @tasks ||= Kuby::Tasks.new(environment)
    end
  end
end
