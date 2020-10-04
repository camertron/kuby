# typed: true
require 'fileutils'
require 'pathname'

module Kuby
  module Plugins
    module RailsApp
      # Works by maintaining a directory structure where each deploy creates
      # a new directory. Each directory is given a timestamped name. Assets
      # are symlinked into a special 'current' directory from each of the
      # timestamped directories. Each invocation overrides existing symlinks
      # if they already exist. This technique ensures assets from the previous
      # deploy remain available while the web servers are restarting.
      class AssetCopyTask
        TIMESTAMP_FORMAT = '%Y%m%d%H%M%S'.freeze
        KEEP = 5

        attr_reader :dest_path, :source_path

        def initialize(to:, from:)
          @dest_path = to
          @source_path = from
        end

        def run
          FileUtils.mkdir_p(ts_dir)
          FileUtils.mkdir_p(current_dir)

          copy_new_assets
          delete_old_assets

          nil
        end

        private

        def copy_new_assets
          # Copy all assets to new timestamp directory
          #
          # "source_path/." is special syntax. From the Ruby docs:
          # cp_r('src', 'dest') makes dest/src, but cp_r('src/.', 'dest') doesn't
          FileUtils.cp_r(File.join(source_path, '.'), ts_dir)

          relative_source_files = Dir.chdir(ts_dir) do
            Dir.glob(File.join('**', '*'))
          end

          relative_source_files.each do |relative_source_file|
            source_file = Pathname(File.join(current_dir, relative_source_file))
            source_ts_file = Pathname(File.join(ts_dir, relative_source_file))
            next unless File.file?(source_ts_file)

            # create individual symlinks for each file in source dir
            target_file = File.join(current_dir, relative_source_file)
            FileUtils.mkdir_p(File.dirname(target_file))
            source_ln_file = source_ts_file.relative_path_from(source_file.dirname)
            FileUtils.ln_s(source_ln_file, target_file, force: true)
            Kuby.logger.info("Linked #{source_ln_file} -> #{target_file}")
          end
        end

        def delete_old_assets
          # find all asset directories; directories have timestamp names
          asset_dirs = (Dir.glob(File.join(dest_path, '*')) - [current_dir])
                       .select { |dir| File.directory?(dir) && try_parse_ts(File.basename(dir)) }
                       .sort_by { |dir| parse_ts(File.basename(dir)) }
                       .reverse

          # only keep the n most recent directories
          dirs_to_delete = asset_dirs[KEEP..-1] || []

          dirs_to_delete.each do |dir_to_delete|
            relative_files_to_delete = Dir.chdir(dir_to_delete) do
              Dir.glob(File.join('**', '*'))
            end

            relative_files_to_delete.each do |relative_file_to_delete|
              file_to_delete = File.join(dir_to_delete, relative_file_to_delete)
              next unless File.file?(file_to_delete)

              link = File.join(current_dir, relative_file_to_delete)
              next unless File.symlink?(link)

              # Only remove a symlink if it still points to a resource
              # in the directory we're currently deleting. Othewise, leave
              # it there - it was added by another deploy.
              File.unlink(link) if File.readlink(link) == file_to_delete
            end

            FileUtils.rm_r(dir_to_delete)
          end
        end

        def try_parse_ts(ts)
          parse_ts(ts)
        rescue ArgumentError
          nil
        end

        def parse_ts(ts)
          Time.strptime(ts, TIMESTAMP_FORMAT)
        end

        def ts_dir
          @ts_dir ||= File.join(
            dest_path, Time.now.strftime(TIMESTAMP_FORMAT)
          )
        end

        def current_dir
          @current_dir ||= File.join(dest_path, 'current')
        end
      end
    end
  end
end
