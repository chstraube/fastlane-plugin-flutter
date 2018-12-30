require 'fastlane/action'
require_relative '../helper/flutter_helper'

# This is the entry point for this plugin. For more information on writing
# plugins: https://docs.fastlane.tools/advanced/

module Fastlane
  module Actions
    module SharedValues
      FLUTTER_OUTPUT_APP = :FLUTTER_OUTPUT_APP
      FLUTTER_OUTPUT_APK = :FLUTTER_OUTPUT_APK
      FLUTTER_OUTPUT_BUILD_NUMBER_OVERRIDE =
        :FLUTTER_OUTPUT_BUILD_NUMBER_OVERRIDE
      FLUTTER_OUTPUT_BUILD_NAME_OVERRIDE = :FLUTTER_OUTPUT_BUILD_NAME_OVERRIDE
    end

    class FlutterAction < Action
      FLUTTER_ACTIONS = %(build analyze test format l10n)

      PLATFORM_TO_FLUTTER = {
        ios: 'ios',
        android: 'apk',
      }

      PLATFORM_TO_OUTPUT = {
        ios: SharedValues::FLUTTER_OUTPUT_APP,
        android: SharedValues::FLUTTER_OUTPUT_APK,
      }

      def self.run(params)
        # You can print a table of plugin configuration params like that:
        #
        # FastlaneCore::PrintTable.print_values(
        #   config: params,
        #   title: "Summary for Flutter plugin #{Fastlane::Flutter::VERSION}",
        # )

        case params[:action]
        when 'build'
          # A map of fastlane platform name into "flutter build" args list.
          build_args = {}

          (lane_context[SharedValues::PLATFORM_NAME] ||
           # If platform is unspecified, build for all platforms.
           PLATFORM_TO_FLUTTER.keys).each do |fastlane_platform|
            build_args[fastlane_platform] = [
              PLATFORM_TO_FLUTTER[fastlane_platform],
            ]
          end

          if params[:debug]
            build_args.each_value do |a|
              a.push('--debug')
            end
          end

          unless params[:codesign]
            build_args[:ios].push('--no-codesign') if build_args.key?(:ios)
          end

          if lane_context[SharedValues::FLUTTER_OUTPUT_BUILD_NUMBER_OVERRIDE] =
               build_number = Helper::FlutterHelper.build_number(
                 params[:build_number_override]
               )
            build_args.each_value do |a|
              a.push('--build-number', build_number.to_s)
            end
          end

          if lane_context[SharedValues::FLUTTER_OUTPUT_BUILD_NAME_OVERRIDE] =
               build_name = Helper::FlutterHelper.build_name(
                 params[:build_name_override]
               )
            build_args.each_value do |a|
              a.push('--build-name', build_name)
            end
          end

          # Note: this statement is expected to return a value (map of platform
          # into file name).
          build_args.map do |platform, args|
            sh('flutter', 'build', *args) do |status, res|
              if status.success?
                # Dirty hacks ahead!
                if FLUTTER_TO_OUTPUT.key?(platform)
                  # Examples:
                  # Built /Users/foo/src/flutter/build/output/myapp.app.
                  # Built build/output/myapp.apk (32.4MB).
                  if res =~ /^Built (.*?)(:? \([^)]*\))?\.$/
                    lane_context[PLATFORM_TO_OUTPUT[platform]] =
                      File.absolute_path($1)
                  end
                end
              else
                # fastlane does not fail automatically if we provide a block.
                UI.build_failure!("flutter build #{platform} has failed.")
              end
            end
          end
        when 'test'
          sh *%w(flutter test)
        when 'analyze'
          sh *%w(flutter analyze)
        when 'format'
          sh *%w(flutter format .)
        when 'l10n'
          run_l10n(params)
        end
      end

      def self.run_l10n(params)
        unless params[:l10n_strings_file]
          UI.user_error!('l10n_strings_file is a required parameter for ' \
                         'l10n action')
        end

        output_dir = 'lib/l10n'
        l10n_messages_file = File.join(output_dir, 'intl_messages.arb')
        # This file will not exist before it's generated for the first time.
        if File.exist?(l10n_messages_file)
          l10n_messages_was = File.read(l10n_messages_file)
        end

        extract_to_arb_options = ["--output-dir=#{output_dir}"]
        if params[:l10n_strings_locale]
          extract_to_arb_options.push(
            "--locale=#{params[:l10n_strings_locale]}"
          )
        end

        sh *%w(flutter pub pub run intl_translation:extract_to_arb),
           *extract_to_arb_options, params[:l10n_strings_file]

        if l10n_messages_was
          # intl will update @@last_modified even if there are no updates;
          # this leaves Git directory unnecessary dirty. If that's the only
          # change, just restore the previous contents.
          if Helper::FlutterHelper.restore_l10n_timestamp(
            l10n_messages_file, l10n_messages_was
          )
            UI.message(
              "@@last_modified has been restored in #{l10n_messages_file}"
            )
          end
        end

        # Sort files for consistency, because messages_all.dart will have
        # imports ordered as in the command line below.
        arb_files = Dir.glob(File.join(output_dir, 'intl_*.arb')).sort

        if params[:l10n_verify_arb]
          errors_found = arb_files.any? do |arb_file|
            unless arb_file == l10n_messages_file
              UI.message("Verifying #{arb_file}...")
              errors = Helper::FlutterHelper.compare_arb(l10n_messages_file,
                                                         arb_file)
              if errors.any?
                errors.each { |e| UI.error(e) }
              end
            end
          end
          UI.user_error!('Found inconsistencies in ARB files') if errors_found
        end

        unless params[:l10n_strings_locale]
          # Don't generate .dart for the original ARB unless it has its own
          # locale.
          arb_files.delete(l10n_messages_file)
        end

        if params[:l10n_reformat_arb]
          arb_files.each do |arb_file|
            UI.message("Reformatting file #{arb_file}...")
            Helper::FlutterHelper.reformat_arb(arb_file)
          end
        end

        sh *%W(flutter pub pub run intl_translation:generate_from_arb
               --output-dir=#{output_dir}
               --no-use-deferred-loading
               #{params[:l10n_strings_file]}) + arb_files
      end

      def self.description
        "Flutter actions plugin for Fastlane"
      end

      def self.authors
        ["Artem Sheremet"]
      end

      def self.return_value
        'For "build" action, the return value is a mapping of fastlane ' \
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
            key: :codesign,
            env_name: 'FL_FLUTTER_CODESIGN',
            description: 'Set to false to skip iOS app signing. This may be ' \
            'useful e.g. on CI or when signed by Fastlane "sigh"',
            optional: true,
            is_string: false,
            default_value: true,
          ),
          FastlaneCore::ConfigItem.new(
            key: :build_number_override,
            env_name: 'FL_FLUTTER_BUILD_NUMBER_OVERRIDE',
            description: <<-'DESCRIPTION',
              Override build number in pubspec.yaml. Can be either a number, or
              a schema definition, ex.: ci (take from CI) vcs (take from Git),
              ci+1000 (take from CI and add 1000).
              WARNING: does not override Android build number specified in
                       pubspec.yaml due to Flutter bug:
                       https://github.com/flutter/flutter/issues/22788.
            DESCRIPTION
            optional: true,
            verify_block: Helper::FlutterHelper.method(:build_number),
          ),
          FastlaneCore::ConfigItem.new(
            key: :build_name_override,
            env_name: 'FL_FLUTTER_BUILD_NAME_OVERRIDE',
            description: <<-'DESCRIPTION',
              Override build name in pubspec.yaml. Can be either a string, or a
              schema definition, ex.: vcs* (take from VCS, add "*" for dirty
              tree), vcs (take from VCS, no dirty mark).
              NOTE: for App Store, must be in the format of at most 3 integeres
                    separated by a dot (".").
              WARNING: does not override Android build number specified in
                       pubspec.yaml due to Flutter bug:
                       https://github.com/flutter/flutter/issues/22788.
            DESCRIPTION
            optional: true,
            verify_block: Helper::FlutterHelper.method(:build_name),
          ),
          # l10n settings
          FastlaneCore::ConfigItem.new(
            key: :l10n_strings_file,
            env_name: 'FL_FLUTTER_L10N_STRINGS',
            description: 'Path to the .dart file with l10n strings',
            optional: true,
            verify_block: proc do |value|
              UI.user_error!('File does not exist') unless File.exist?(value)
            end,
          ),
          FastlaneCore::ConfigItem.new(
            key: :l10n_strings_locale,
            env_name: 'FL_FLUTTER_L10N_STRINGS_LOCALE',
            description: 'Locale of the data in l10n_strings_file',
            optional: true,
          ),
          FastlaneCore::ConfigItem.new(
            key: :l10n_reformat_arb,
            env_name: 'FL_FLUTTER_L10N_REFORMAT_ARB',
            description: 'Reformat .arb files',
            optional: true,
            is_string: false,
            default_value: false,
          ),
          FastlaneCore::ConfigItem.new(
            key: :l10n_verify_arb,
            env_name: 'FL_FLUTTER_L10N_VERIFY_ARB',
            description: 'Verify that each .arb file includes all strings',
            optional: true,
            is_string: false,
            default_value: true,
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
