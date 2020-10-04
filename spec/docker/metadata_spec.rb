# typed: false
require 'spec_helper'
require 'timecop'

describe Kuby::Docker::Metadata do
  let(:metadata) { definition.environment.docker.metadata }

  describe '#image_url' do
    subject { metadata.image_url }

    it { is_expected.to eq(docker_image_url) }

    context 'when no image URL is configured' do
      let(:docker_image_url) { nil }
      it { is_expected.to eq(definition.app_name) }
    end
  end

  describe '#image_host' do
    subject { metadata.image_host }

    it { is_expected.to eq(described_class::DEFAULT_REGISTRY_HOST) }

    context 'when the image URL contains an explicit host' do
      let(:docker_image_url) { 'registry.foo.com/foo/testapp' }

      it { is_expected.to eq('https://registry.foo.com') }
    end

    context 'when the image URL contains an explicit host with scheme' do
      let(:docker_image_url) { 'http://registry.foo.com/foo/testapp' }

      it { is_expected.to eq('http://registry.foo.com') }
    end
  end

  describe '#image_repo' do
    subject { metadata.image_repo }

    it { is_expected.to eq('foo/testapp') }

    context 'when the image URL contains an explicit host' do
      let(:docker_image_url) { 'registry.foo.com/foo/testapp' }

      it { is_expected.to eq('foo/testapp') }
    end
  end

  describe '#image_hostname' do
    subject { metadata.image_hostname }

    it { is_expected.to eq('www.docker.com') }

    context 'when the image URL contains an explicit host' do
      let(:docker_image_url) { 'registry.foo.com/foo/testapp' }

      it { is_expected.to eq('registry.foo.com') }
    end
  end

  describe '#tags' do
    subject { metadata.tags }

    it 'specifies the current timestamp tag and the default tag' do
      Timecop.freeze do
        expect(subject).to eq([
                                Time.now.strftime('%Y%m%d%H%M%S'),
                                Kuby::Docker::Metadata::LATEST_TAG
                              ])
      end
    end
  end

  describe '#distro' do
    subject { metadata.distro }

    it { is_expected.to eq(Kuby::Docker::Metadata::DEFAULT_DISTRO) }

    context 'with a distro set manually' do
      before { metadata.distro = :alpine }

      it { is_expected.to eq(:alpine) }
    end
  end
end
