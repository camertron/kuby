# typed: true
require 'fileutils'
require 'securerandom'
require 'yaml'

module Kuby
  module Kubernetes
    class Deployer
      attr_reader :environment
      attr_accessor :logdev

      def initialize(environment)
        @environment = environment
      end

      def deploy
        restart_rails_deployment_if_necessary do
          namespaced, global = all_resources.partition do |resource|
            # Unfortunately we can't use respond_to here because all KubeDSL
            # objects use ObjectMeta, which has a namespace field. Not sure
            # why, since it makes no sense for a namespace to have a namespace.
            # Instead we just check for nil here.
            resource.metadata.namespace
          end

          deploy_global_resources(global)
          deploy_namespaced_resources(namespaced)
        end
      end

      # adhere to the "CLI" interface
      def with_pipes(_out = STDOUT, err = STDERR)
        previous_logdev = logdev
        @logdev = err
        yield
      ensure
        @logdev = previous_logdev
      end

      def logdev
        @logdev || STDERR
      end

      def last_status
        nil
      end

      private

      def deploy_global_resources(resources)
        resources.each do |res|
          Kuby.logger.info(
            "Validating global resource, #{res.kind_sym.to_s.humanize.downcase} '#{res.metadata.name}'"
          )

          cli.apply(res, dry_run: true)
        end

        resources.each do |res|
          Kuby.logger.info(
            "Deploying #{res.kind_sym.to_s.humanize.downcase} '#{res.metadata.name}'"
          )

          cli.apply(res)
        end
      rescue KubernetesCLI::InvalidResourceError => e
        Kuby.logger.fatal(e.message)
        Kuby.logger.fatal(e.resource.to_resource.to_yaml)
      end

      def deploy_namespaced_resources(resources)
        old_kubeconfig = ENV['KUBECONFIG']
        ENV['KUBECONFIG'] = provider.kubeconfig_path

        tmpdir = Dir.mktmpdir('kuby-deploy-resources')

        resources.each do |resource|
          resource_path = File.join(
            tmpdir, "#{SecureRandom.hex(6)}-#{resource.kind_sym.downcase}.yaml"
          )

          File.write(resource_path, resource.to_resource.to_yaml)
        end

        task = ::Kuby::Kubernetes::DeployTask.new(
          namespace: namespace.metadata.name,
          context: cli.current_context,
          filenames: [tmpdir]
        )

        task.logger.reopen(logdev)

        task.run!(verify_result: true, prune: false)
      ensure
        ENV['KUBECONFIG'] = old_kubeconfig
        FileUtils.rm_rf(tmpdir)
      end

      def restart_rails_deployment_if_necessary
        deployed_image = nil
        current_image = "#{docker.metadata.image_url}:#{docker.tag}"

        if rails_app = kubernetes.plugin(:rails_app)
          deployment_name = rails_app.deployment.metadata.name

          begin
            deployment = cli.get_object(
              'deployment', namespace.metadata.name, deployment_name
            )

            deployed_image = deployment.dig('spec', 'template', 'spec', 'containers', 0, 'image')
          rescue ::KubernetesCLI::GetResourceError
          end
        end

        yield

        if deployed_image == current_image
          Kuby.logger.info('Docker image URL did not change, restarting Rails deployment manually')
          cli.restart_deployment(namespace.metadata.name, deployment_name)
        end
      end

      def provider
        kubernetes.provider
      end

      def namespace
        kubernetes.namespace
      end

      def all_resources
        kubernetes.resources
      end

      def docker
        environment.docker
      end

      def kubernetes
        environment.kubernetes
      end

      def cli
        provider.kubernetes_cli
      end
    end
  end
end
