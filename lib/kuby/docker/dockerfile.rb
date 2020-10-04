# typed: strict

require 'digest'

module Kuby
  module Docker
    class Dockerfile
      extend T::Sig

      class Command
        extend T::Sig

        sig { returns(T::Array[String]) }
        attr_reader :args

        sig { params(args: T::Array[String]).void }
        def initialize(args)
          @args = args
        end

        sig { returns(String) }
        def to_s
          args.join(' ')
        end
      end

      class From < Command
        sig { returns(String) }
        attr_reader :image_url

        sig { returns(T.nilable(String)) }
        attr_reader :as

        sig { params(image_url: String, as: T.nilable(String)).void }
        def initialize(image_url, as: nil)
          @image_url = image_url
          @as = as
        end

        sig { returns(String) }
        def to_s
          str = "FROM #{image_url}"
          str << " AS #{as}" if as
          str
        end
      end

      class Workdir < Command
        sig { returns(String) }
        def to_s
          "WORKDIR #{super}"
        end
      end

      class Env < Command
        sig { returns(String) }
        def to_s
          "ENV #{super}"
        end
      end

      class Run < Command
        sig { returns(String) }
        def to_s
          "RUN #{super}"
        end
      end

      class Copy < Command
        sig { returns(String) }
        attr_reader :source

        sig { returns(String) }
        attr_reader :dest

        sig { returns(T.nilable(String)) }
        attr_reader :from

        sig { params(source: String, dest: String, from: T.nilable(String)).void }
        def initialize(source, dest, from: nil)
          @source = source
          @dest = dest
          @from = from
        end

        sig { returns(String) }
        def to_s
          cmd = ['COPY']
          cmd << "--from=#{from}" if from
          cmd += [source, dest]
          cmd.join(' ')
        end
      end

      class Expose < Command
        sig { returns(String) }
        def to_s
          "EXPOSE #{super}"
        end
      end

      class Cmd < Command
        sig { returns(String) }
        def to_s
          "CMD #{super}"
        end
      end

      class Arg < Command
        sig { returns(String) }
        def to_s
          "ARG #{super}"
        end
      end

      sig { returns(T::Array[Command]) }
      attr_reader :commands

      sig { returns(Integer) }
      attr_reader :cursor

      sig { void }
      def initialize
        @commands = T.let([], T::Array[Command])
        @cursor = T.let(0, Integer)
      end

      sig { params(image_url: String, as: T.nilable(String)).void }
      def from(image_url, as: nil)
        add From.new(image_url, as: as)
      end

      sig { params(args: String).void }
      def workdir(*args)
        add Workdir.new(args)
      end

      sig { params(args: String).void }
      def env(*args)
        add Env.new(args)
      end

      sig { params(args: String).void }
      def arg(*args)
        add Arg.new(args)
      end

      sig { params(args: String).void }
      def run(*args)
        add Run.new(args)
      end

      sig { params(source: String, dest: String, from: T.nilable(String)).void }
      def copy(source, dest, from: nil)
        add Copy.new(source, dest, from: from)
      end

      sig { params(args: String).void }
      def expose(*args)
        add Expose.new(args)
      end

      sig { params(args: String).void }
      def cmd(*args)
        add Cmd.new(args)
      end

      sig { returns(String) }
      def to_s
        # ensure trailing newline
        "#{commands.map(&:to_s).join("\n")}\n"
      end

      sig { returns(String) }
      def checksum
        Digest::SHA256.hexdigest(to_s)
      end

      sig { returns(T::Array[String]) }
      def exposed_ports
        commands
          .select { |c| c.is_a?(Expose) }
          .map { |c| T.must(c.args.first) }
      end

      sig { params(pos: Integer, block: T.proc.void).void }
      def insert_at(pos)
        @cursor = pos
        yield
      ensure
        @cursor = commands.size
      end

      private

      sig { params(cmd: Command).void }
      def add(cmd)
        commands.insert(cursor, cmd)
        @cursor += 1
      end
    end
  end
end
