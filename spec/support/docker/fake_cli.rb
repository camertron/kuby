# typed: true
module Docker
  class FakeCLI
    attr_reader :auths

    def initialize
      @auths = []
      @images = Hash.new { |h, k| h[k] = [] }
    end

    def config_file
      default_config_file if File.exist?(default_config_file)
    end

    def default_config_file
      File.join(Dir.home, '.docker', 'config.json')
    end

    def login(url:, username:, password:)
      auths << url
      nil
    end

    def build(dockerfile:, image_url:, tags:)
      @images[image_url] += tags
      nil
    end

    def run(image_url:, tag: 'latest', env: {}, ports: []); end

    def images(image_url)
      @images.fetch(image_url, []).map do |tag|
        {
          containers: 'N/A',
          created_at: '2020-08-29 16:54:05 -0700 PDT',
          created_since: '22 hours ago',
          digest: '<none>',
          id: '0b261b06270a',
          repository: image_url,
          shared_size: 'N/A',
          size: '1.14GB',
          tag: tag,
          unique_size: 'N/A',
          virtual_size: '1.138GB'
        }
      end
    end

    def push(image_url, tag); end
  end
end
