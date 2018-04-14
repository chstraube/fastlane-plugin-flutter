require 'fastlane/action'
require_relative '../helper/flutter_helper'

module Fastlane
  module Actions
    module SharedValues
      FLUTTER_OUTPUT_APP = :FLUTTER_OUTPUT_APP
      FLUTTER_OUTPUT_APK = :FLUTTER_OUTPUT_APK
    end

    class FlutterAction < Action
      FLUTTER_ACTIONS = %(build analyze test format l10n)

      PLATFORM_TO_FLUTTER = {
        ios: 'ios',
        android: 'apk',
      }

      FLUTTER_TO_OUTPUT = {
        'ios' => SharedValues::FLUTTER_OUTPUT_APP,
        'apk' => SharedValues::FLUTTER_OUTPUT_APK,
      }

      def self.run(params)
        case params[:action]
        when 'build'
          flutter_platforms = %w(apk ios)
          # Override if we are on a specific platform (non-root lane).
          if fastlane_platform = lane_context[SharedValues::PLATFORM_NAME]
            flutter_platforms = [PLATFORM_TO_FLUTTER[fastlane_platform]]
          end

          additional_args = []
          additional_args.push('--debug') if params[:debug]

          built_files = {}

          flutter_platforms.each do |platform|
            sh('flutter', 'build', platform, *additional_args) do |status, res|
              if status.success?
                # Dirty hacks ahead!
                if FLUTTER_TO_OUTPUT.key?(platform)
                  # Examples:
                  # Built /Users/foo/src/flutter/build/output/myapp.app.
                  # Built build/output/myapp.apk (32.4MB).
                  if res =~ /^Built (.*?)(:? \([^)]*\))?\.$/
                    built_file = File.absolute_path($1)
                    built_files[PLATFORM_TO_FLUTTER.key(platform)] = built_file
                    lane_context[FLUTTER_TO_OUTPUT[platform]] = built_file
                  end
                end
              end
            end
          end

          built_files
        when 'test'
          sh *%w(flutter test)
        when 'analyze'
          sh *%W(flutter analyze #{params[:lib_path]})
        when 'format'
          sh *%W(flutter format #{params[:lib_path]})
        when 'l10n'
          output_dir = File.join(params[:lib_path], 'l10n')
          l10n_messages_file = File.join(output_dir, 'intl_messages.arb')
          l10n_messages_was = File.read(l10n_messages_file)

          sh *%W(flutter pub pub run intl_translation:extract_to_arb
            --output-dir=#{output_dir} #{params[:l10n_strings_file]})

          # intl will update @@last_modified even if there are no updates;
          # this leaves Git directory unnecessary dirty. If that's the only
          # change, just restore the previous contents.
          if Helper::FlutterHelper.restore_l10n_timestamp(
              l10n_messages_file, l10n_messages_was)
            UI.message(
              "@@last_modified has been restored in #{l10n_messages_file}")
          end

          # Sort files for consistency, because messages_all.dart will have
          # imports ordered as in the command line below.
          arb_files = Dir.glob(File.join(output_dir, 'intl_*.arb')).sort
          # Don't generate .dart for the original ARB, messages_all.dart has it.
          arb_files.delete(l10n_messages_file)

          sh *%W(flutter pub pub run intl_translation:generate_from_arb
            --output-dir=#{output_dir}
            --no-use-deferred-loading
            #{params[:l10n_strings_file]}) + arb_files
        end
      end

      def self.description
        "Flutter actions plugin for Fastlane"
      end

      def self.authors
        ["Artem Sheremet"]
      end

      def self.return_value
        'For "build" action, the return value is a mapping of fastlane ' +
          'platform names into built output files, e.g.: ' +
          { android: '/Users/foo/src/flutter/build/outputs/myapp.apk' }.inspect
      end

      def self.details
        # Optional:
        ""
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :action,
            env_name: 'FL_FLUTTER_ACTION',
            description: 'Flutter action to run',
            optional: false,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("Supported actions are: #{FLUTTER_ACTIONS}") unless FLUTTER_ACTIONS.include?(value)
            end,
          ),
          FastlaneCore::ConfigItem.new(
            key: :debug,
            env_name: 'FL_FLUTTER_DEBUG',
            description: 'Build a Debug version of the app if true',
            optional: true,
            is_string: false,
            default_value: false,
          ),
          FastlaneCore::ConfigItem.new(
            key: :lib_path,
            env_name: 'FL_FLUTTER_LIB_PATH',
            description: "Path to Flutter 'lib' directory",
            optional: true,
            default_value: 'lib',
            verify_block: proc do |value|
              UI.user_error!('Directory does not exist') unless Dir.exists?(value)
            end,
          ),
          FastlaneCore::ConfigItem.new(
            key: :l10n_strings_file,
            env_name: 'FL_FLUTTER_L10N_STRINGS',
            description: 'Path to the .dart file with l10n strings',
            optional: true,
            verify_block: proc do |value|
              UI.user_error!('File does not exist') unless File.exists?(value)
            end,
          ),
        ]
      end

      def self.is_supported?(platform)
        # Also support nil (root lane).
        [nil, :ios, :android].include?(platform)
      end
    end
  end
end