# typed: false
require 'rouge'

module Kuby
  class Tasks
    attr_reader :environment

    def initialize(environment)
      @environment = environment
    end

    def print_dockerfile
      theme = Rouge::Themes::Base16::Solarized.new
      formatter = Rouge::Formatters::Terminal256.new(theme)
      lexer = Rouge::Lexers::Docker.new
      tokens = lexer.lex(Kuby.environment.docker.to_dockerfile.to_s)
      puts formatter.format(tokens)
    end

    def setup
      environment.kubernetes.setup
    end

    def build
      build_args = {}

      build_args['RAILS_MASTER_KEY'] = ENV['RAILS_MASTER_KEY'] unless ENV.fetch('RAILS_MASTER_KEY', '').empty?

      docker.cli.build(
        dockerfile: docker.to_dockerfile,
        image_url: docker.metadata.image_url,
        tags: docker.metadata.tags,
        build_args: build_args
      )
    end

    def push
      raise 'Cannot push Docker images built for the development environment' if environment.development?

      hostname = docker.metadata.image_hostname

      unless docker.cli.auths.include?(hostname)
        Kuby.logger.info("Attempting to log in to registry at #{hostname}")

        begin
          docker.cli.login(
            url: docker.metadata.image_host,
            username: docker.credentials.username,
            password: docker.credentials.password
          )
        rescue Kuby::Docker::LoginError => e
          Kuby.logger.fatal("Couldn't log in to the registry at #{hostname}")
          Kuby.logger.fatal(e.message)
          return
        end
      end

      image_url = docker.metadata.image_url

      begin
        docker.tags.local.latest_tags.each do |tag|
          docker.cli.push(image_url, tag)
        end
      rescue Kuby::Docker::MissingTagError => e
        msg = "#{e.message} Run rake kuby:build to build the"\
          'Docker image before running this task.'

        Kuby.logger.fatal(msg)
        Kuby.logger.fatal(e.message)
      end
    end

    def deploy(tag = nil)
      environment.kubernetes.deploy(tag)
    end

    def rollback
      environment.kubernetes.rollback
    end

    def print_resources
      kubernetes.before_deploy

      kubernetes.resources.each do |res|
        puts res.to_resource.serialize.to_yaml
      end
    end

    def print_kubeconfig
      path = kubernetes.provider.kubeconfig_path
      Kuby.logger.info("Printing contents of #{path}")
      puts File.read(path)
    end

    def kubectl(*cmd)
      kubernetes_cli.run_cmd(cmd)
    end

    def remote_logs
      kubernetes_cli.logtail(namespace, match_labels.serialize)
    end

    def remote_status
      kubernetes_cli.run_cmd(['-n', namespace, 'get', 'pods'])
    end

    def remote_exec(cmd)
      first_pod = get_first_pod
      kubernetes_cli.exec_cmd(cmd, namespace, first_pod.dig('metadata', 'name'))
    end

    def remote_system(cmd)
      first_pod = get_first_pod
      kubernetes_cli.system_cmd(cmd, namespace, first_pod.dig('metadata', 'name'))
    end

    def remote_shell
      remote_exec(docker.distro_spec.shell_exe)
    end

    def remote_console
      remote_exec('bundle exec rails console')
    end

    def remote_dbconsole
      remote_exec('bundle exec rails dbconsole')
    end

    def remote_restart
      deployment = rails_app.deployment.metadata.name
      kubernetes_cli.restart_deployment(namespace, deployment)
    end

    def dev_deployment_ok
      return true unless Kuby.environment.development?

      deployments = kubernetes_cli.get_objects(
        'deployments', namespace, match_labels.serialize
      )

      if deployments.empty?
        puts 'No development environment detected.'
        STDOUT.write('Set up development environment? (y/n): ')
        answer = STDIN.gets.strip.downcase
        return false unless answer =~ /ye?s?/

        return DevSetup.new(environment).run
      else
        depl = deployments.first
        deployed_checksum = depl.dig('metadata', 'annotations', 'getkuby.io/dockerfile-checksum')
        current_checksum = docker.to_dockerfile.checksum

        if deployed_checksum != current_checksum
          puts "Development environment appears to be out-of-date."
          puts "Environment checksum: #{deployed_checksum}"
          puts "Current checksum:     #{current_checksum}"
          STDOUT.write('Update development environment? (y/n): ')
          answer = STDIN.gets.strip.downcase
          # return true here to prevent letting an out-of-date deployment
          # stop us from running commands
          return true unless answer =~ /ye?s?/

          return DevSetup.new(environment).run
        end
      end

      true
    end

    private

    def get_first_pod
      pods = kubernetes_cli.get_objects(
        'pods', namespace, match_labels.serialize
      )

      # consider only "Running" pods that aren't marked for deletion
      pods.select! do |pod|
        pod.dig('status', 'phase') == 'Running' &&
          !pod.dig('metadata', 'deletionTimestamp')
      end

      if pods.empty?
        raise Kuby::Kubernetes::MissingResourceError,
              "Couldn't find any running pods in namespace '#{namespace}' :("

        exit 1
      end

      pods.first
    end

    def namespace
      kubernetes.namespace.metadata.name
    end

    def match_labels
      rails_app.deployment.spec.selector.match_labels
    end

    def rails_app
      kubernetes.plugin(:rails_app)
    end

    def kubernetes_cli
      kubernetes.provider.kubernetes_cli
    end

    def helm_cli
      kubernetes.provider.helm_cli
    end

    def docker_cli
      docker.cli
    end

    def kubernetes
      Kuby.environment.kubernetes
    end

    def docker
      Kuby.environment.docker
    end
  end
end
