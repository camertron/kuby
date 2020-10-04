# typed: false
require 'yaml'

module Kuby
  module Plugins
    module RailsApp
      class UnsupportedDatabaseError < StandardError; end

      class Database
        ADAPTER_MAP = {
          sqlite3: Sqlite,
          mysql2: MySQL,
          postgresql: Postgres
        }.freeze

        def self.get(rails_app)
          new(rails_app) if rails_app.manage_database?
        end

        def self.get_adapter(adapter_name)
          ADAPTER_MAP.fetch(adapter_name) do
            raise UnsupportedDatabaseError, "Kuby does not support the '#{adapter}' "\
              'database adapter'
          end
        end

        attr_reader :rails_app

        def initialize(rails_app)
          @rails_app = rails_app
        end

        def plugin
          @plugin ||= self.class
                          .get_adapter(adapter_name)
                          .new(rails_app.environment, db_configs)
        end

        def adapter_name
          @adapter_name ||= db_config['adapter'].to_sym
        end

        alias plugin_name adapter_name

        private

        def db_config
          @db_config ||= db_configs[rails_app.environment.name]
        end

        def db_configs
          @db_configs ||= YAML.load(File.read(db_config_path))
        end

        def db_config_path
          @db_config_path ||= begin
            db_config_paths.first or
              raise "Couldn't find database config in #{db_config_pattern}"
          end
        end

        def db_config_paths
          @db_config_paths ||= Dir.glob(db_config_pattern)
        end

        def db_config_pattern
          @db_config_pattern ||= File.join(
            rails_app.root, 'config', 'database.{yml,erb,yml.erb,yaml,yaml.erb}'
          )
        end
      end
    end
  end
end
