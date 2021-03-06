module Kuby
  module Plugins
    module RailsApp
      class AssetsImage < ::Kuby::Docker::Image
        attr_reader :base_image

        def initialize(base_image, dockerfile, main_tag = nil, alias_tags = [])
          super(dockerfile, base_image.image_url, base_image.credentials, main_tag, alias_tags)
          @base_image = base_image
        end

        def new_version
          # Asset images track the base image, so return the current version
          # here. There can be no asset image without a base image.
          current_version
        end

        def current_version
          @current_version ||= duplicate_with_annotated_tags(
            base_image.current_version
          )
        end

        def previous_version
          @previous_version ||= duplicate_with_annotated_tags(
            base_image.previous_version
          )
        end

        def build(build_args = {})
          docker_cli.build(current_version, build_args: build_args)
        end

        def push(tag)
          docker_cli.push(image_url, tag)
        end

        private

        def duplicate_with_annotated_tags(image)
          self.class.new(
            base_image,
            dockerfile,
            annotate_tag(image.main_tag),
            image.alias_tags.map { |at| annotate_tag(at) }
          )
        end

        def annotate_tag(tag)
          "#{tag}-assets"
        end
      end
    end
  end
end
