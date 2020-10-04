# typed: strict

module Kuby
  module Docker
    class RemoteTags
      extend T::Sig

      sig { returns(::Docker::Remote::Client) }
      attr_reader :remote_client

      sig { returns(Metadata) }
      attr_reader :metadata

      sig do
        params(
          remote_client: ::Docker::Remote::Client,
          metadata: Metadata
        )
          .void
      end
      def initialize(remote_client, metadata)
        @remote_client = remote_client
        @metadata = metadata
      end

      sig { returns(T::Array[String]) }
      def tags
        remote_client.tags
      end

      sig { returns(T::Array[String]) }
      def latest_tags
        # not available for remote repos
        []
      end

      sig { returns(T::Array[TimestampTag]) }
      def timestamp_tags
        tags.map { |t| TimestampTag.try_parse(t) }.compact
      end
    end
  end
end
