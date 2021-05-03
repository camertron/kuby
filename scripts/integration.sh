#! /bin/bash

# preflight
set -ev
unset BUNDLE_GEMFILE
K8S_VERSION='1.19.10-00'

echo travis_fold:start:setup_cluster
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update
sudo apt-get install -y jq kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION
cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
networking:
  podSubnet: "192.168.0.0/16"
controllerManager:
  extraArgs:
    enable-hostpath-provisioner: "true"
EOF
sudo kubeadm init --config ./kubeadm-config.yaml

# copy kubeconfig to default location so kubectl works
mkdir -p ~/.kube
sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# start up the calico CNI
kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml
# make hostpath storage class available
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  namespace: kube-system
  name: hostpath
  annotations:
    storageclass.beta.kubernetes.io/is-default-class: "true"
  labels:
    addonmanager.kubernetes.io/mode: EnsureExists
provisioner: kubernetes.io/host-path
EOF
# allow pods to be scheduled on the master node
kubectl taint nodes --all node-role.kubernetes.io/master-
echo travis_fold:end:setup_cluster

# generate rails app
echo travis_fold:start:generate_app
git clone --depth=1 https://github.com/camertron/prebundler --branch=fix_nokogiri_issues
pushd prebundler; \
  bundle install --jobs 2 --retry 3 && \
  bundle exec rake build && \
  gem install pkg/prebundler-0.11.7.gem; \
  popd
cd ..
git clone --depth=1 https://github.com/getkuby/kuby_test.git
cd kuby_test
printf "\ngem 'kuby-core', github: 'getkuby/kuby-core', branch: 'kubeadm'\n" >> Gemfile
bundle lock
# bundle install
cat <<'EOF' > .prebundle_config
Prebundler.configure do |config|
  config.storage_backend = Prebundler::S3Backend.new(
    client: Aws::S3::Client.new(
      region: 'default',
      credentials: Aws::Credentials.new(
        ENV['PREBUNDLER_ACCESS_KEY_ID'],
        ENV['PREBUNDLER_SECRET_ACCESS_KEY']
      ),
      endpoint: 'https://us-east-1.linodeobjects.com',
      http_continue_timeout: 0
    ),
    bucket: 'prebundler',
    region: 'us-east-1'
  )
end
EOF
prebundle install --jobs 2 --retry 3
bundle exec bin/rails g kuby
cat <<'EOF' > kuby.rb
require 'active_support/core_ext'
require 'active_support/encrypted_configuration'

class PrebundlerPhase < Kuby::Docker::BundlerPhase
  def apply_to(dockerfile)
    dockerfile.run(<<~END)
      git clone --depth=1 https://github.com/camertron/prebundler --branch=fix_nokogiri_issues && \
        cd prebundler && \
        bundle install --jobs 2 --retry 3 && \
        bundle exec rake build && \
        gem install pkg/prebundler-0.11.7.gem
    END

    app_creds = ActiveSupport::EncryptedConfiguration.new(
      config_path: File.join('config', 'credentials.yml.enc'),
      key_path: File.join('config', 'master.key'),
      env_key: 'RAILS_MASTER_KEY',
      raise_if_missing_key: true
    )

    dockerfile.env('PREBUNDLER_ACCESS_KEY_ID', app_creds[:PREBUNDLER_ACCESS_KEY_ID])
    dockerfile.env('PREBUNDLER_SECRET_ACCESS_KEY', app_creds[:PREBUNDLER_SECRET_ACCESS_KEY])

    dockerfile.copy('.prebundle_config', '.')
    # dockerfile.run('gem', 'install', 'prebundler', '-v', "'< 1'")

    super

    dockerfile.commands.each do |cmd|
      next unless cmd.is_a?(Kuby::Docker::Dockerfile::Run)

      if cmd.args[0..1] == ['bundle', 'install']
        cmd.args[0] = 'prebundle'
      end
    end
  end
end

Kuby.define('Kubyapp') do
  environment(:production) do
    docker do
      insert(:vendor, before: :bundler_phase) do |dockerfile|
        dockerfile.copy('vendor', 'vendor')
      end

      image_url 'localhost:5000/kubyapp'

      insert :prebundler_phase, PrebundlerPhase.new(environment), after: :bundler_phase
      delete :bundler_phase
    end

    kubernetes do
      add_plugin :rails_app do
        tls_enabled false

        database do
          user 'kubyapp'
          password 'password'
        end
      end

      provider :bare_metal
    end
  end
end
EOF
cat <<'EOF' > config/database.yml
default: &default
  adapter: mysql2
  encoding: utf8mb4
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  username: root
  password: password
  host: localhost
development:
  <<: *default
  database: kubyapp_development
production:
  <<: *default
  database: kubyapp_production
EOF
cat <<'EOF' > config/routes.rb
Rails.application.routes.draw do
  root to: 'home#index'
end
EOF
cat <<'EOF' > app/controllers/home_controller.rb
class HomeController < ApplicationController
  def index
  end
end
EOF
mkdir app/views/home/
touch app/views/home/index.html.erb
echo travis_fold:end:generate_app

# start docker registry
echo travis_fold:start:start_registry
docker run -d -p 5000:5000 --name registry registry:2
echo travis_fold:end:start_registry

# build and push
echo travis_fold:start:build_and_push
GLI_DEBUG=true bundle exec kuby -e production build
GLI_DEBUG=true bundle exec kuby -e production push
echo travis_fold:end:build_and_push

# setup cluster
echo travis_fold:start:setup
GLI_DEBUG=true bundle exec kuby -e production setup
# force nginx ingress to be a nodeport since we don't have any load balancers
kubectl -n ingress-nginx patch svc ingress-nginx -p '{"spec":{"type":"NodePort"}}'
echo travis_fold:end:setup

# deploy!
echo travis_fold:start:deploy
GLI_DEBUG=true bundle exec kuby -e production deploy || \
  GLI_DEBUG=true bundle exec kuby -e production deploy
echo travis_fold:end:deploy

# get ingress IP from kubectl; attempt to hit the app
ingress_ip=$(kubectl -n ingress-nginx get svc ingress-nginx -o json | jq -r .spec.clusterIP)
curl -vvv $ingress_ip:80 \
  -H "Host: localhost"\
  --fail \
  --connect-timeout 5 \
  --max-time 10 \
  --retry 5 \
  --retry-max-time 40
