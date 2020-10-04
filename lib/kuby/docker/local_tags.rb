# typed: strict

module Kuby
  module Docker
    class LocalTags
      extend T::Sig

      sig { returns CLI }
      attr_reader :cli

      sig { returns(Metadata) }
      attr_reader :metadata

      sig do
        params(
          cli: CLI,
          metadata: Metadata
        )
          .void
      end
      def initialize(cli, metadata)
        @cli = cli
        @metadata = metadata

        @latest_timestamp_tag = T.let(@latest_timestamp_tag, T.nilable(TimestampTag))
      end

      sig { returns(T::Array[String]) }
      def tags
        images = cli.images(metadata.image_url)
        images.map { |image| T.must(image[:tag]) }
      end

      sig { returns(T::Array[String]) }
      def latest_tags
        # find "latest" tag
        images = cli.images(metadata.image_url)
        latest = images.find { |image| image[:tag] == Tags::LATEST }

        raise MissingTagError.new(Tags::LATEST) unless latest

        # find all tags that point to the same image as 'latest'
        images.each_with_object([]) do |image_data, tags|
          tags << image_data[:tag] if image_data[:id] == latest[:id]
        end
      end

      sig { returns(T::Array[TimestampTag]) }
      def timestamp_tags
        tags.map { |t| TimestampTag.try_parse(t) }.compact
      end

      sig { returns(T.nilable(TimestampTag)) }
      def latest_timestamp_tag
        @latest_timestamp_tag ||= timestamp_tags.max
      end
    end
  end
end
