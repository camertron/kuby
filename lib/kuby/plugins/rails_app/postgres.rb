# typed: false
require 'kube-dsl'
require 'kuby/kube-db'

module Kuby
  module Plugins
    module RailsApp
      class Postgres < ::Kuby::Plugin
        ROLE = 'web'.freeze

        attr_reader :environment, :configs

        def initialize(environment, configs)
          @environment = environment
          @configs = configs

          user(config['username'])
          password(config['password'])
        end

        def name
          :postgres
        end

        def resources
          @resources ||= [secret, database]
        end

        def after_configuration
          environment.docker.package_phase.add(:postgres_dev)
          environment.docker.package_phase.add(:postgres_client)
        end

        def host
          # host is the same as the name thanks to k8s DNS
          @host ||= database.metadata.name
        end

        def rewritten_configs
          # deep dup
          @rewritten_configs ||= Marshal.load(Marshal.dump(configs)).tap do |new_configs|
            new_configs[environment.name]['host'] = host
          end
        end

        def user(user)
          secret do
            data do
              set :POSTGRES_USER, user
            end
          end
        end

        def password(password)
          secret do
            data do
              set :POSTGRES_PASSWORD, password
            end
          end
        end

        def secret(&block)
          context = self

          @secret ||= KubeDSL.secret do
            metadata do
              name "#{context.base_name}-postgres-secret"
              namespace context.kubernetes.namespace.metadata.name
            end

            type 'Opaque'
          end

          @secret.instance_eval(&block) if block
          @secret
        end

        def database(&block)
          context = self

          @database ||= Kuby::KubeDB.postgres do
            api_version 'kubedb.com/v1alpha1'

            metadata do
              name "#{context.base_name}-postgres"
              namespace context.kubernetes.namespace.metadata.name
            end

            spec do
              database_secret do
                secret_name context.secret.metadata.name
              end

              version '11.2'
              standby_mode 'Hot'
              streaming_mode 'asynchronous'
              storage_type 'Durable'

              storage do
                storage_class_name context.kubernetes.provider.storage_class_name
                access_modes ['ReadWriteOnce']

                resources do
                  requests do
                    add :storage, '10Gi'
                  end
                end
              end

              termination_policy 'DoNotTerminate'
            end
          end

          @database.instance_eval(&block) if block
          @database
        end

        def base_name
          @base_name ||= "#{kubernetes.selector_app}-#{ROLE}"
        end

        def kubernetes
          environment.kubernetes
        end

        private

        def config
          configs[environment.name]
        end
      end
    end
  end
end

Kuby.register_package(:postgres_dev,
                      debian: 'postgresql-client',
                      alpine: 'postgresql-dev')

Kuby.register_package(:postgres_client,
                      debian: 'postgresql-client',
                      alpine: 'postgresql-client')
