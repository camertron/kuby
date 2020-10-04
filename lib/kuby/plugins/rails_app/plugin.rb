# typed: false
require 'kube-dsl'
require 'kuby/cert-manager'

module Kuby
  module Plugins
    module RailsApp
      class Plugin < ::Kuby::Plugin
        extend ::KubeDSL::ValueFields

        WEB_ROLE = 'web'.freeze
        DEFAULT_HOSTNAME = 'localhost'.freeze
        MASTER_KEY_VAR = 'RAILS_MASTER_KEY'.freeze
        ENV_SECRETS = [MASTER_KEY_VAR].freeze
        ENV_EXCLUDE = ['RAILS_ENV'].freeze
        DEFAULT_ASSET_URL = '/assets'.freeze
        DEFAULT_PACKS_URL = '/packs'.freeze
        DEFAULT_ASSET_PATH = './public'.freeze

        value_field :root, default: '.'
        value_fields :hostname, :tls_enabled
        value_fields :manage_database, :database, :replicas
        value_fields :asset_url, :packs_url, :asset_path

        alias manage_database? manage_database

        def initialize(environment)
          @environment = environment
          @tls_enabled = true
          @replicas = 1
          @manage_database = true
          @hostname = DEFAULT_HOSTNAME
          @asset_url = DEFAULT_ASSET_URL
          @packs_url = DEFAULT_PACKS_URL
          @asset_path = DEFAULT_ASSET_PATH
          # @database = Database.get(self)
        end

        def configure(&block)
          instance_eval(&block) if block
        end

        def after_configuration
          context = self

          if manage_database? && @database = Database.get(self)
            @database.plugin.instance_eval(&@database_block) if @database_block
            environment.kubernetes.plugins[@database.plugin_name] = @database.plugin
            environment.kubernetes.add_plugin(:kube_db)

            unless environment.development?
              environment.docker do
                insert :rewrite_db_config, RewriteDbConfig.new, after: :copy_phase
              end
            end
          end

          unless environment.development?
            environment.kubernetes.add_plugin(:nginx_ingress)
            environment.kubernetes.add_plugin(:rails_assets) do
              asset_url context.asset_url
              packs_url context.packs_url
              asset_path context.asset_path
            end

            if @tls_enabled
              context = self

              environment.kubernetes.add_plugin(:cert_manager) do
                email context.environment.docker.credentials.email
              end
            end
          end
        end

        def database_host
          database.plugin.host
        end

        def before_deploy(_manifest)
          # Make sure plugin has been configured. If not, do nothing.
          if cert_manager = environment.kubernetes.plugin(:cert_manager)
            cert_manager.annotate_ingress(ingress)
          end

          image_with_tag = "#{docker.metadata.image_url}:#{kubernetes.tag}"

          if assets = environment.kubernetes.plugin(:rails_assets)
            assets.configure_ingress(ingress, hostname)
            assets.configure_deployment(deployment, image_with_tag)
          end

          spec = self

          deployment do
            spec do
              template do
                spec do
                  container(:web) do
                    image image_with_tag
                  end

                  unless spec.environment.development?
                    init_container(:create_db) do
                      image image_with_tag
                    end

                    init_container(:migrate_db) do
                      image image_with_tag
                    end
                  end
                end
              end
            end
          end
        end

        def database(&block)
          if block
            @database_block = block
          elsif environment.configured?
            @database
          end
        end

        def service(&block)
          spec = self

          @service ||= KubeDSL.service do
            metadata do
              name "#{spec.selector_app}-svc"
              namespace spec.namespace.metadata.name

              labels do
                add :app, spec.selector_app
                add :role, spec.role
              end
            end

            spec do
              type 'NodePort'

              selector do
                add :app, spec.selector_app
                add :role, spec.role
              end

              port do
                name 'http'
                port spec.docker.webserver_phase.port
                protocol 'TCP'
                target_port 'http'
              end
            end
          end

          @service.instance_eval(&block) if block
          @service
        end

        def service_account(&block)
          spec = self

          @service_account ||= KubeDSL.service_account do
            metadata do
              name "#{spec.selector_app}-sa"
              namespace spec.namespace.metadata.name

              labels do
                add :app, spec.selector_app
                add :role, spec.role
              end
            end
          end

          @service_account.instance_eval(&block) if block
          @service_account
        end

        def config_map(&block)
          spec = self

          @config_map ||= KubeDSL.config_map do
            metadata do
              name "#{spec.selector_app}-config"
              namespace spec.namespace.metadata.name
            end

            data do
              ENV.each_pair do |key, val|
                include_key = key.start_with?('RAILS_') &&
                              !ENV_SECRETS.include?(key) &&
                              !ENV_EXCLUDE.include?(key)

                add key.to_sym, val if include_key
              end
            end
          end

          @config_map.instance_eval(&block) if block
          @config_map
        end

        def app_secrets(&block)
          spec = self

          @app_secrets ||= KubeDSL.secret do
            metadata do
              name "#{spec.selector_app}-secrets"
              namespace spec.namespace.metadata.name
            end

            type 'Opaque'

            data do
              if master_key = ENV[MASTER_KEY_VAR]
                add MASTER_KEY_VAR.to_sym, master_key
              else
                master_key_path = File.join(spec.root, 'config', 'master.key')

                add MASTER_KEY_VAR.to_sym, File.read(master_key_path).strip if File.exist?(master_key_path)
              end
            end
          end

          @app_secrets.instance_eval(&block) if block
          @app_secrets
        end

        def deployment(&block)
          kube_spec = self

          @deployment ||= KubeDSL.deployment do
            metadata do
              name "#{kube_spec.selector_app}-#{kube_spec.role}"
              namespace kube_spec.namespace.metadata.name

              labels do
                add :app, kube_spec.selector_app
                add :role, kube_spec.role
              end

              annotations do
                add(
                  'getkuby.io/dockerfile-checksum',
                  kube_spec.environment.docker.to_dockerfile.checksum
                )
              end
            end

            spec do
              replicas kube_spec.replicas

              selector do
                match_labels do
                  add :app, kube_spec.selector_app
                  add :role, kube_spec.role
                end
              end

              strategy do
                type 'RollingUpdate'

                rolling_update do
                  max_surge '25%'
                  max_unavailable 0
                end
              end

              template do
                metadata do
                  labels do
                    add :app, kube_spec.selector_app
                    add :role, kube_spec.role
                  end
                end

                spec do
                  container(:web) do
                    name "#{kube_spec.selector_app}-#{kube_spec.role}"
                    image_pull_policy 'IfNotPresent'

                    port do
                      container_port kube_spec.docker.webserver_phase.port
                      name 'http'
                      protocol 'TCP'
                    end

                    env_from do
                      config_map_ref do
                        name kube_spec.config_map.metadata.name
                      end
                    end

                    env_from do
                      secret_ref do
                        name kube_spec.app_secrets.metadata.name
                      end
                    end

                    unless kube_spec.environment.development?
                      readiness_probe do
                        success_threshold 1
                        failure_threshold 2
                        initial_delay_seconds 15
                        period_seconds 3
                        timeout_seconds 1

                        http_get do
                          path '/healthz'
                          port kube_spec.docker.webserver_phase.port
                          scheme 'HTTP'
                        end
                      end
                    end

                    if kube_spec.environment.development?
                      env do
                        name 'BUNDLE_PATH'
                        value '/bundle'
                      end

                      env do
                        name 'GEM_HOME'
                        value '/bundle'
                      end

                      env do
                        name 'BOOTSNAP_CACHE_DIR'
                        value '/usr/src/bootsnap'
                      end

                      volume_mount do
                        name "#{kube_spec.selector_app}-code"
                        mount_path '/usr/src/app'
                      end

                      volume_mount do
                        name "#{kube_spec.selector_app}-bundle"
                        mount_path '/bundle'
                      end

                      volume_mount do
                        name "#{kube_spec.selector_app}-bootsnap"
                        mount_path '/usr/src/bootsnap'
                      end
                    end
                  end

                  if kube_spec.environment.development?
                    volume do
                      name "#{kube_spec.selector_app}-code"

                      persistent_volume_claim do
                        claim_name kube_spec.code_volume_claim.metadata.name
                      end
                    end

                    volume do
                      name "#{kube_spec.selector_app}-bundle"

                      persistent_volume_claim do
                        claim_name kube_spec.bundle_volume_claim.metadata.name
                      end
                    end

                    volume do
                      name "#{kube_spec.selector_app}-bootsnap"

                      persistent_volume_claim do
                        claim_name kube_spec.bootsnap_volume_claim.metadata.name
                      end
                    end
                  else
                    init_container(:create_db) do
                      name "#{kube_spec.selector_app}-create-db"
                      command %w[bundle exec rake kuby:rails_app:db:create_unless_exists]
                    end

                    init_container(:migrate_db) do
                      name "#{kube_spec.selector_app}-migrate-db"
                      command %w[bundle exec rake db:migrate]
                    end

                    image_pull_secret do
                      name kube_spec.environment.kubernetes.registry_secret.metadata.name
                    end
                  end

                  restart_policy 'Always'
                  service_account_name kube_spec.service_account.metadata.name
                end
              end
            end
          end

          @deployment.instance_eval(&block) if block
          @deployment
        end

        def ingress(&block)
          spec = self
          tls_enabled = @tls_enabled

          @ingress ||= KubeDSL::DSL::Extensions::V1beta1::Ingress.new do
            metadata do
              name "#{spec.selector_app}-ingress"
              namespace spec.namespace.metadata.name

              annotations do
                add :'kubernetes.io/ingress.class', 'nginx'
              end
            end

            spec do
              rule do
                host spec.hostname

                http do
                  path do
                    path '/'

                    backend do
                      service_name spec.service.metadata.name
                      service_port spec.service.spec.ports.first.port
                    end
                  end
                end
              end

              if tls_enabled
                tls do
                  secret_name "#{spec.selector_app}-tls"
                  hosts [spec.hostname]
                end
              end
            end
          end

          @ingress.instance_eval(&block) if block
          @ingress
        end

        def code_volume(&block)
          spec = self

          if environment.development?
            @code_volume ||= KubeDSL.persistent_volume do
              metadata do
                name "#{spec.selector_app}-code"
              end

              spec do
                access_modes ['ReadWriteMany']

                capacity do
                  add :storage, '1Mi'
                end

                host_path do
                  path File.expand_path(spec.root)
                end

                storage_class_name 'hostpath'
              end
            end

            @code_volume.instance_eval(&block) if block
            @code_volume
          end
        end

        def code_volume_claim(&block)
          spec = self

          if environment.development?
            @code_volume_claim ||= KubeDSL.persistent_volume_claim do
              metadata do
                name "#{spec.selector_app}-code"
                namespace spec.namespace.metadata.name
              end

              spec do
                access_modes ['ReadWriteMany']

                resources do
                  requests do
                    add :storage, '1Mi'
                  end
                end

                storage_class_name 'hostpath'
                volume_name spec.code_volume.metadata.name
              end
            end

            @code_volume_claim.instance_eval(&block) if block
            @code_volume_claim
          end
        end

        def bundle_volume_claim(&block)
          spec = self

          if environment.development?
            @bundle_volume_claim ||= KubeDSL.persistent_volume_claim do
              metadata do
                name "#{spec.selector_app}-bundle"
                namespace spec.namespace.metadata.name
              end

              spec do
                access_modes ['ReadWriteMany']
                storage_class_name 'hostpath'

                resources do
                  requests do
                    add :storage, '2Gi'
                  end
                end
              end
            end

            @bundle_volume_claim.instance_eval(&block) if block
            @bundle_volume_claim
          end
        end

        def bootsnap_volume_claim(&block)
          spec = self

          if environment.development?
            @bootsnap_volume_claim ||= KubeDSL.persistent_volume_claim do
              metadata do
                name "#{spec.selector_app}-bootsnap"
                namespace spec.namespace.metadata.name
              end

              spec do
                access_modes ['ReadWriteMany']
                storage_class_name 'hostpath'

                resources do
                  requests do
                    add :storage, '2Gi'
                  end
                end
              end
            end

            @bootsnap_volume_claim.instance_eval(&block) if block
            @bootsnap_volume_claim
          end
        end

        def resources
          @resources ||= [
            service,
            service_account,
            config_map,
            app_secrets,
            deployment,
            ingress,
            code_volume,
            code_volume_claim,
            bundle_volume_claim,
            bootsnap_volume_claim,
            *database&.plugin&.resources
          ]
        end

        def selector_app
          environment.kubernetes.selector_app
        end

        def role
          WEB_ROLE
        end

        def docker
          environment.docker
        end

        def kubernetes
          environment.kubernetes
        end

        def namespace
          environment.kubernetes.namespace
        end
      end
    end
  end
end
