describe Fastlane::Actions::FlutterAction do
  describe '#run:format' do
    it 'runs a "flutter format" command' do
      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with('flutter', 'format', '.')

      Fastlane::Actions::FlutterAction.run(action: 'format')
    end
  end

  describe '#run:l10n' do
    it 'runs Dart intl generators for the first time' do
      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with(*%w(flutter pub pub run intl_translation:extract_to_arb
                 --output-dir=lib/l10n lib/localization.dart))

      expect(Dir).to receive(:glob).
        with('lib/l10n/intl_*.arb').
        and_return(%w(lib/l10n/intl_en.arb lib/l10n/intl_messages.arb))

      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with(*%w(flutter pub pub run intl_translation:generate_from_arb
                 --output-dir=lib/l10n --no-use-deferred-loading
                 lib/localization.dart lib/l10n/intl_en.arb))

      Fastlane::Actions::FlutterAction.run(
        action: 'l10n',
        l10n_strings_file: 'lib/localization.dart'
      )
    end

    it 'runs Dart intl generators with custom locale' do
      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with(*%w(flutter pub pub run intl_translation:extract_to_arb
                 --output-dir=lib/l10n --locale=en lib/localization.dart))

      expect(Dir).to receive(:glob).
        with('lib/l10n/intl_*.arb').
        and_return(%w(lib/l10n/intl_de.arb lib/l10n/intl_messages.arb))

      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with(*%w(flutter pub pub run intl_translation:generate_from_arb
                 --output-dir=lib/l10n --no-use-deferred-loading
                 lib/localization.dart lib/l10n/intl_de.arb
                 lib/l10n/intl_messages.arb))

      Fastlane::Actions::FlutterAction.run(
        action: 'l10n',
        l10n_strings_file: 'lib/localization.dart',
        l10n_strings_locale: 'en',
      )
    end

    it 'runs Dart intl generators and restores timestamp' do
      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with(*%w(flutter pub pub run intl_translation:extract_to_arb
                 --output-dir=lib/l10n lib/localization.dart))

      expect(File).to receive(:exist?).
        with('lib/l10n/intl_messages.arb').
        and_return(true)

      first_read = true
      expect(File).to receive(:read).twice.with('lib/l10n/intl_messages.arb') do
        if first_read
          first_read = false
          '{"@@last_modified": 1, "foo": "bar"}'
        else
          '{"@@last_modified": 2, "foo": "bar"}'
        end
      end

      expect(File).to receive(:write).with(
        'lib/l10n/intl_messages.arb',
        '{"@@last_modified": 1, "foo": "bar"}'
      )

      expect(Dir).to receive(:glob).
        with('lib/l10n/intl_*.arb').
        and_return(%w(lib/l10n/intl_en.arb lib/l10n/intl_messages.arb))

      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with(*%w(flutter pub pub run intl_translation:generate_from_arb
                 --output-dir=lib/l10n --no-use-deferred-loading
                 lib/localization.dart lib/l10n/intl_en.arb))

      Fastlane::Actions::FlutterAction.run(
        action: 'l10n',
        l10n_strings_file: 'lib/localization.dart'
      )
    end

    it 'runs Dart intl generators and keeps changes' do
      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with(*%w(flutter pub pub run intl_translation:extract_to_arb
                 --output-dir=lib/l10n lib/localization.dart))

      expect(File).to receive(:exist?).
        with('lib/l10n/intl_messages.arb').
        and_return(true)

      first_read = true
      expect(File).to receive(:read).twice.with('lib/l10n/intl_messages.arb') do
        if first_read
          first_read = false
          '{"@@last_modified": 1, "foo": "bar"}'
        else
          '{"@@last_modified": 2, "foo": "baz"}'
        end
      end

      expect(File).not_to receive(:write)

      expect(Dir).to receive(:glob).
        with('lib/l10n/intl_*.arb').
        and_return(%w(lib/l10n/intl_en.arb lib/l10n/intl_messages.arb))

      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with(*%w(flutter pub pub run intl_translation:generate_from_arb
                 --output-dir=lib/l10n --no-use-deferred-loading
                 lib/localization.dart lib/l10n/intl_en.arb))

      Fastlane::Actions::FlutterAction.run(
        action: 'l10n',
        l10n_strings_file: 'lib/localization.dart'
      )
    end

    it 'reports errors for missing or unused translation strings' do
      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with(*%w(flutter pub pub run intl_translation:extract_to_arb
                 --output-dir=lib/l10n lib/localization.dart))

      expect(File).to receive(:exist?).
        with('lib/l10n/intl_messages.arb').
        and_return(true)

      expect(File).to receive(:read).
        at_least(:once).
        with('lib/l10n/intl_messages.arb') do
          '{"@@last_modified": 1, "foo": "bar", "@foo": "not significant"}'
        end
      expect(File).to receive(:read).
        at_least(:once).
        with('lib/l10n/intl_de.arb') do
          '{"@@last_modified": 1, "baz": ""}'
        end

      expect(File).to receive(:write)

      expect(Dir).to receive(:glob).
        with('lib/l10n/intl_*.arb').
        and_return(%w(lib/l10n/intl_de.arb lib/l10n/intl_messages.arb))

      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with(*%w(flutter pub pub run intl_translation:generate_from_arb
                 --output-dir=lib/l10n --no-use-deferred-loading
                 lib/localization.dart lib/l10n/intl_de.arb))

      expect(FastlaneCore::UI).to receive(:error).
        with('Translation string(s): foo; are missing')
      expect(FastlaneCore::UI).to receive(:error).
        with('Translation string(s): baz; are unused')
      expect(FastlaneCore::UI).to receive(:user_error!).
        with('Found inconsistencies in ARB files')

      Fastlane::Actions::FlutterAction.run(
        action: 'l10n',
        l10n_strings_file: 'lib/localization.dart',
        l10n_verify_arb: true,
      )
    end
  end

  describe '#run:build' do
    it 'gets build name and number from VCS' do
      expect(Fastlane::Actions).to receive(:sh).
        with('git', 'rev-list', '--count', 'HEAD').
        and_return('743')
      expect(Fastlane::Actions).to receive(:sh).
        with('git', 'describe', '--tags', '--dirty=*').
        and_return('2.4.2-10-gbadf00d*')
      # TODO(dotdoom): test further with ".and_yield".
      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with('flutter', 'build', 'apk',
             '--build-number', '800',
             '--build-name', '2.4.2-10-gbadf00d*')
      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with('flutter', 'build', 'ios',
             '--build-number', '800',
             '--build-name', '2.4.2-10-gbadf00d*')

      Fastlane::Actions::FlutterAction.run(
        action: 'build',
        codesign: true,
        build_number_override: 'vcs+57',
        build_name_override: 'vcs*',
      )
    end

    it 'allows building for iOS without codesigning' do
      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with('flutter', 'build', 'apk')
      expect(Fastlane::Actions::FlutterAction).to receive(:sh).
        with('flutter', 'build', 'ios', '--no-codesign')

      Fastlane::Actions::FlutterAction.run(
        action: 'build',
        codesign: false,
      )
    end
  end
end
