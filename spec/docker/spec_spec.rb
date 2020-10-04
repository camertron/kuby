# typed: false
require 'spec_helper'
require 'timecop'

describe Kuby::Docker::Spec do
  let(:spec) { definition.environment.docker }

  describe '#base_image' do
    subject { spec.to_dockerfile.to_s }

    it 'uses the default base image for Debian' do
      expect(subject).to include("FROM ruby:#{RUBY_VERSION}\n")
    end

    context 'when the distro is set to Alpine' do
      before { spec.distro(:alpine) }

      it 'uses the Alpine base image' do
        expect(subject).to include("FROM ruby:#{RUBY_VERSION}-alpine\n")
      end
    end

    context 'when the base image is set to something custom' do
      before { spec.base_image('foo/bar') }

      it 'uses the base image as given' do
        expect(subject).to include("FROM foo/bar\n")
      end
    end
  end

  describe '#working_dir' do
    let(:default_working_dir) do
      Kuby::Docker::SetupPhase::DEFAULT_WORKING_DIR
    end

    subject { spec.to_dockerfile.to_s }

    it 'uses the default working dir' do
      expect(subject).to(
        include("WORKDIR #{default_working_dir}\n")
      )
    end

    context 'when the working dir is set to something custom' do
      before { spec.working_dir('/foo/bar') }

      it 'uses the working dir as given' do
        expect(subject).to include("WORKDIR /foo/bar\n")
      end
    end
  end

  describe '#rails_env' do
    subject { spec.to_dockerfile.to_s }

    it 'uses the name of the current Kuby environment' do
      expect(subject).to include("ENV RAILS_ENV=#{spec.environment.name}\n")
      expect(subject).to include("ENV KUBY_ENV=#{spec.environment.name}\n")
    end

    context 'when the environment is set to something custom' do
      before { spec.rails_env('foobar') }

      it 'uses the environment as given' do
        expect(subject).to include("ENV RAILS_ENV=foobar\n")
      end

      it "doesn't change the Kuby env" do
        expect(subject).to include("ENV KUBY_ENV=#{spec.environment.name}\n")
      end
    end
  end

  describe '#bundler_version' do
    subject { spec.to_dockerfile.to_s }

    it 'installs the current bundler version' do
      expect(subject).to(
        include("RUN gem install bundler -v #{Bundler::VERSION}\n")
      )
    end

    context 'when the bundler version is set to something custom' do
      before { spec.bundler_version('1.17.3') }

      it 'installs the given version' do
        expect(subject).to include("RUN gem install bundler -v 1.17.3\n")
      end
    end
  end

  describe '#gemfile' do
    subject { spec.to_dockerfile.to_s }

    it 'uses the default Gemfile' do
      expect(subject).to include("COPY Gemfile .\n")
      expect(subject).to include("COPY Gemfile.lock .\n")
      expect(subject).to match(/RUN bundle install .* --gemfile Gemfile/)
    end

    context 'when the gemfile path is set to something custom' do
      before { spec.gemfile('foo/bar/Gemfile') }

      it 'uses the given gemfile' do
        expect(subject).to include("COPY foo/bar/Gemfile .\n")
        expect(subject).to include("COPY foo/bar/Gemfile.lock .\n")
        expect(subject).to match(%r{RUN bundle install .* --gemfile foo/bar/Gemfile})
      end
    end
  end

  describe '#package' do
    subject { spec.to_dockerfile.to_s }

    it 'installs the given package' do
      # configured in spec_helper.rb
      spec.package(:fake_package)

      expect(subject).to match(/apt-get install .* fake_package/m)
    end
  end

  describe '#files' do
    subject { spec.to_dockerfile.to_s }

    it 'copies the current directory contents by default' do
      expect(subject).to include("COPY ./ .\n")
    end

    context 'when given a custom path to copy' do
      before { spec.files('./foo/bar') }

      it 'copies the given paths only' do
        expect(subject).to include("COPY ./foo/bar .\n")
      end
    end
  end

  describe '#port' do
    let(:default_port) do
      Kuby::Docker::WebserverPhase::DEFAULT_PORT
    end

    subject { spec.to_dockerfile.to_s }

    it 'exposes the default port' do
      expect(subject).to include("EXPOSE #{default_port}\n")
    end

    context 'when given a custom port' do
      before { spec.port(5555) }

      it 'exposes the given port' do
        expect(subject).to include("EXPOSE 5555\n")
      end
    end
  end

  describe '#tag' do
    let(:tag) { make_ts_tag(Time.now) }

    subject { spec.tag }

    context 'with no local or remote tags' do
      it 'raises an error' do
        expect { subject }.to raise_error(Kuby::Docker::MissingTagError)
      end
    end

    context 'with an available remote tag' do
      before { docker_remote_client.tags << tag }

      it { is_expected.to eq(tag) }
    end

    context 'with an available local tag' do
      before do
        docker_cli.build(
          dockerfile: nil,
          image_url: docker_image_url,
          tags: [tag]
        )
      end

      it { is_expected.to eq(tag) }
    end

    context 'with multiple remote tags' do
      let(:time) { Time.now }

      before do
        docker_remote_client.tags +=
          [time - 5, time + 10, time - 10, time + 15].map do |t|
            make_ts_tag(t)
          end
      end

      it { is_expected.to eq(make_ts_tag(time + 15)) }
    end

    context 'with multiple local and remote tags' do
      let(:time) { Time.now }

      before do
        docker_remote_client.tags +=
          [time - 5, time + 10, time - 10, time + 15].map do |t|
            make_ts_tag(t)
          end

        docker_cli.build(
          dockerfile: nil,
          image_url: docker_image_url,
          tags: [time - 3, time + 6, time - 6, time + 18].map do |t|
            make_ts_tag(t)
          end
        )
      end

      it { is_expected.to eq(make_ts_tag(time + 18)) }
    end
  end

  describe '#previous_tag' do
    let(:time) { Time.now }
    let(:current_tag) { make_ts_tag(time) }

    before do
      docker_remote_client.tags << current_tag
      docker_cli.build(
        dockerfile: nil,
        image_url: docker_image_url,
        tags: [current_tag]
      )
    end

    subject { spec.previous_tag(current_tag) }

    context 'with no previous local or remote tag' do
      it 'raises an error' do
        expect { subject }.to raise_error(Kuby::Docker::MissingTagError)
      end
    end

    context 'with an available previous remote tag' do
      let(:previous_tag) { make_ts_tag(time - 5) }

      before { docker_remote_client.tags << previous_tag }

      it { is_expected.to eq(previous_tag) }
    end

    context 'with an available previous local tag' do
      let(:previous_tag) { make_ts_tag(time - 5) }

      before do
        docker_cli.build(
          dockerfile: nil,
          image_url: docker_image_url,
          tags: [previous_tag]
        )
      end

      it { is_expected.to eq(previous_tag) }
    end
  end

  describe '#insert' do
    subject { spec.to_dockerfile.to_s }

    context 'with a custom class-based build phase' do
      before do
        foo_phase = Class.new do
          def apply_to(dockerfile)
            dockerfile.insert_at(0) do
              dockerfile.run('echo "foo"')
            end
          end
        end

        spec.insert :foo_phase, foo_phase.new, after: :webserver_phase
      end

      it 'inserts the commands' do
        expect(subject).to match(/\ARUN echo "foo"$/)
      end
    end

    context 'with a custom inline build phase' do
      before do
        spec.insert :hello, after: :webserver_phase do |dockerfile|
          dockerfile.insert_at(0) do
            dockerfile.run('echo "foo"')
          end
        end
      end

      it 'allows inserting custom build phases' do
        expect(subject).to match(/\ARUN echo "foo"$/)
      end
    end
  end
end
