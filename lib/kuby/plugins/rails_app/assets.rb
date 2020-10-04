# typed: false
require 'kube-dsl'

module Kuby
  module Plugins
    module RailsApp
      class Assets < ::Kuby::Plugin
        extend ::KubeDSL::ValueFields

        ROLE = 'assets'.freeze
        NGINX_IMAGE = 'nginx:1.9-alpine'.freeze
        NGINX_PORT = 8082
        NGINX_MOUNT_PATH = '/usr/share/nginx/assets'.freeze
        RAILS_MOUNT_PATH = '/usr/share/assets'.freeze

        value_fields :asset_url, :packs_url, :asset_path

        def configure(&block)
          instance_eval(&block)
        end

        def configure_ingress(ingress, hostname)
          spec = self

          ingress.spec.rule do
            host hostname

            http do
              path do
                path spec.asset_url

                backend do
                  service_name spec.service.metadata.name
                  service_port spec.service.spec.ports.first.port
                end
              end

              path do
                path spec.packs_url

                backend do
                  service_name spec.service.metadata.name
                  service_port spec.service.spec.ports.first.port
                end
              end
            end
          end
        end

        def configure_deployment(deployment, docker_image)
          spec = self

          deployment.spec.template.spec do
            init_container(:copy_assets) do
              name "#{spec.selector_app}-copy-assets"
              command %w[bundle exec rake kuby:rails_app:assets:copy]
              image docker_image

              volume_mount do
                name 'assets'
                mount_path RAILS_MOUNT_PATH
              end
            end

            container(:web) do
              volume_mount do
                name 'assets'
                mount_path NGINX_MOUNT_PATH
              end
            end

            volume do
              name 'assets'

              persistent_volume_claim do
                claim_name spec.volume_claim.metadata.name
              end
            end
          end
        end

        def copy_task
          @copy_task ||= AssetCopyTask.new(
            from: asset_path, to: RAILS_MOUNT_PATH
          )
        end

        def service(&block)
          spec = self

          @service ||= KubeDSL.service do
            metadata do
              name "#{spec.selector_app}-#{spec.role}-svc"
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
                port NGINX_PORT
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
              name "#{spec.selector_app}-#{spec.role}-sa"
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

        def nginx_config(&block)
          spec = self

          @nginx_config ||= KubeDSL.config_map do
            metadata do
              name "#{spec.selector_app}-#{spec.role}-nginx-config"
              namespace spec.namespace.metadata.name
            end

            data do
              add 'nginx.conf', <<~END
                user  nginx;
                worker_processes  1;

                error_log  /var/log/nginx/error.log warn;
                pid        /var/run/nginx.pid;

                events {
                  worker_connections  1024;
                }

                http {
                  include       /etc/nginx/mime.types;
                  default_type  application/octet-stream;

                  log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                                    '$status $body_bytes_sent "$http_referer" '
                                    '"$http_user_agent" "$http_x_forwarded_for"';

                  access_log  /var/log/nginx/access.log  main;

                  sendfile           on;
                  keepalive_timeout  65;
                  gzip               on;

                  server {
                    listen #{NGINX_PORT};
                    server_name localhost;

                    location / {
                      root #{File.join(NGINX_MOUNT_PATH, 'current')};
                    }

                    error_page   500 502 503 504  /500.html;
                  }
                }
              END
            end
          end

          @nginx_config.instance_eval(&block) if block
          @nginx_config
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
            end

            spec do
              replicas 1

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
                  container(:nginx) do
                    name "#{kube_spec.selector_app}-#{kube_spec.role}"
                    image_pull_policy 'IfNotPresent'
                    image NGINX_IMAGE

                    port do
                      container_port NGINX_PORT
                      name 'http'
                      protocol 'TCP'
                    end

                    volume_mount do
                      name 'nginx-config'
                      mount_path '/etc/nginx/nginx.conf'
                      sub_path 'nginx.conf'
                    end

                    volume_mount do
                      name 'assets'
                      mount_path NGINX_MOUNT_PATH
                    end

                    readiness_probe do
                      success_threshold 1
                      failure_threshold 2
                      initial_delay_seconds 5
                      period_seconds 3
                      timeout_seconds 1

                      http_get do
                        path '/500.html'
                        port NGINX_PORT
                        scheme 'HTTP'
                      end
                    end
                  end

                  volume do
                    name 'nginx-config'

                    config_map do
                      name kube_spec.nginx_config.metadata.name
                    end
                  end

                  volume do
                    name 'assets'

                    persistent_volume_claim do
                      claim_name kube_spec.volume_claim.metadata.name
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

        def volume_claim
          spec = self

          @volume_claim ||= KubeDSL.persistent_volume_claim do
            metadata do
              name "#{spec.selector_app}-#{spec.role}"
              namespace spec.namespace.metadata.name
            end

            spec do
              access_modes ['ReadWriteOnce']
              storage_class_name spec.environment.kubernetes.provider.storage_class_name

              resources do
                requests do
                  add :storage, '10Gi'
                end
              end
            end
          end
        end

        def resources
          @resources ||= [
            service,
            service_account,
            nginx_config,
            deployment,
            volume_claim
          ]
        end

        def namespace
          environment.kubernetes.namespace
        end

        def selector_app
          environment.kubernetes.selector_app
        end

        def role
          ROLE
        end
      end
    end
  end
end
