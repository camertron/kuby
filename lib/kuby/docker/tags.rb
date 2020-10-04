# typed: strict

module Kuby
  module Docker
    class Tags
      extend T::Sig

      LATEST = Metadata::LATEST_TAG

      sig { returns(CLI) }
      attr_reader :cli

      sig { returns(::Docker::Remote::Client) }
      attr_reader :remote_client

      sig { returns Metadata }
      attr_reader :metadata

      sig do
        params(
          cli: CLI,
          remote_client: ::Docker::Remote::Client,
          metadata: Metadata
        )
          .void
      end
      def initialize(cli, remote_client, metadata)
        @cli = cli
        @remote_client = remote_client
        @metadata = metadata

        @local = T.let(@local, T.nilable(LocalTags))
        @remote = T.let(@remote, T.nilable(RemoteTags))
        @latest_timestamp_tag = T.let(@latest_timestamp_tag, T.nilable(TimestampTag))
      end

      sig { returns(T::Array[String]) }
      def tags
        (local.tags + remote.tags).uniq
      end

      sig { returns(T::Array[String]) }
      def latest_tags
        (local.latest_tags + remote.latest_tags).uniq
      end

      sig do
        params(current_tag: String).returns(T.nilable(TimestampTag))
      end
      def previous_timestamp_tag(current_tag)
        current_tag = TimestampTag.try_parse(current_tag)
        return nil unless current_tag

        all_tags = timestamp_tags.sort

        idx = all_tags.index do |tag|
          tag.time == current_tag.time
        end

        idx ||= 0
        return nil unless idx > 0

        all_tags[idx - 1]
      end

      sig { returns(T::Array[TimestampTag]) }
      def timestamp_tags
        (local.timestamp_tags + remote.timestamp_tags).uniq
      end

      sig { returns(T.nilable(TimestampTag)) }
      def latest_timestamp_tag
        @latest_timestamp_tag ||= timestamp_tags.max
      end

      sig { returns(T.self_type) }
      def all
        self
      end

      sig { returns(LocalTags) }
      def local
        @local ||= LocalTags.new(cli, metadata)
      end

      sig { returns(RemoteTags) }
      def remote
        @remote ||= RemoteTags.new(remote_client, metadata)
      end
    end
  end
end
