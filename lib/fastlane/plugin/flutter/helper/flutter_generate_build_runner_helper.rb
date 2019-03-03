require 'yaml'

module Fastlane
  module Helper
    class FlutterGenerateBuildRunnerHelper
      def self.build
        Helper::FlutterHelper.flutter(
          *%w(packages pub run build_runner build --delete-conflicting-outputs),
          log: false,
        )
      end
    end
  end
end
