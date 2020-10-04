# typed: strict

require 'json'
require 'open3'
require 'shellwords'

module Kuby
  module Docker
    class CLI < CLIBase
      extend T::Sig

      sig { returns(String) }
      attr_reader :executable

      sig { params(executable: T.nilable(String)).void }
      def initialize(executable = nil)
        @executable = T.let(executable || `which docker`.strip, String)
      end

      sig { returns(T.nilable(String)) }
      def config_file
        default_config_file if File.exist?(default_config_file)
      end

      sig { returns(String) }
      def default_config_file
        File.join(Dir.home, '.docker', 'config.json')
      end

      sig { params(url: String, username: String, password: String).void }
      def login(url:, username:, password:)
        cmd = [
          executable, 'login', url, '--username', username, '--password-stdin'
        ]

        open3_w({}, cmd) do |stdin, _wait_threads|
          stdin.puts(password)
        end

        unless last_status.success?
          raise LoginError, 'build failed: docker command exited with '\
            "status code #{last_status.exitstatus}"
        end
      end

      sig { returns(T::Array[String]) }
      def auths
        return [] unless config_file

        config = JSON.parse(File.read(T.must(config_file)))
        config.fetch('auths', {}).keys
      end

      sig do
        params(
          dockerfile: Dockerfile,
          image_url: String,
          tags: T::Array[String],
          build_args: T::Hash[T.any(Symbol, String), String]
        )
          .void
      end
      def build(dockerfile:, image_url:, tags:, build_args: {})
        cmd = [
          executable, 'build',
          *tags.flat_map { |tag| ['-t', "#{image_url}:#{tag}"] },
          *build_args.flat_map do |arg, val|
            ['--build-arg', Shellwords.shellescape("#{arg}=#{val}")]
          end,
          '-f-', '.'
        ]

        open3_w({}, cmd) do |stdin, _wait_threads|
          stdin.puts(dockerfile.to_s)
        end

        unless last_status.success?
          raise BuildError, 'build failed: docker command exited with '\
            "status code #{last_status.exitstatus}"
        end
      end

      sig do
        params(
          image_url: String,
          tag: String,
          env: T::Hash[T.any(Symbol, String), String],
          ports: T::Array[T.any(String, Integer)]
        )
          .void
      end
      def run(image_url:, tag: 'latest', env: {}, ports: [])
        cmd = [
          executable, 'run',
          *env.flat_map { |k, v| ['-e', "#{k}=#{v}"] },
          *ports.flat_map { |port| ['-p', "#{port}:#{port}"] },
          '--init',
          '--rm',
          "#{image_url}:#{tag}"
        ]

        execc(cmd)
      end

      sig { params(image_url: String).returns(T::Array[T::Hash[Symbol, String]]) }
      def images(image_url)
        cmd = [
          executable, 'images', image_url,
          '--format', '"{{json . }}"'
        ]

        backticks(cmd).split("\n").map do |image_data|
          JSON.parse(image_data).each_with_object({}) do |(k, v), ret|
            ret[k.underscore.to_sym] = v
          end
        end
      end

      sig { params(image_url: String, tag: String).void }
      def push(image_url, tag)
        systemm([
                  executable, 'push', "#{image_url}:#{tag}"
                ])

        unless last_status.success?
          raise PushError, 'push failed: docker command exited with '\
            "status code #{last_status.exitstatus}"
        end
      end

      sig { params(image_url: String, tag: String).void }
      def pull(image_url, tag)
        systemm([
                  executable, 'pull', "#{image_url}:#{tag}"
                ])

        unless last_status.success?
          raise PullError, 'pull failed: docker command exited with '\
            "status code #{last_status.exitstatus}"
        end
      end

      sig { returns(Symbol) }
      def status_key
        :kuby_docker_cli_last_status
      end

      sig { returns(Symbol) }
      def stdout_key
        :kuby_docker_stdout
      end

      sig { returns(Symbol) }
      def stderr_key
        :kuby_docker_stderr
      end
    end
  end
end
