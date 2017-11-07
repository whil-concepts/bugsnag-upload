module Fastlane
  module Actions
    class BugsnagNotifyBuildAction < Action

      def self.run(params)
        require "json"

        if !params[:config_file].nil?
          if lane_context[:PLATFORM_NAME] === :android
            options = get_android_options(params)
          else
            options = get_ios_options(params)
          end
        else
          options = {}
        end

        git_options = get_git_options()
        options.merge!(git_options)

        # Overwrite automated options with configured if set
        options[:apiKey] = params[:api_key] unless params[:api_key].nil?
        options[:appVersion] = params[:app_version] unless params[:app_version].nil?
        options[:releaseStage] = params[:release_stage] unless params[:release_stage].nil?
        options[:repository] = params[:repository] unless params[:repository].nil?
        options[:revision] = params[:revision] unless params[:revision].nil?
        options[:provider] = params[:provider] unless params[:provider].nil?

        options.reject {|k,v| v == nil}

        if options[:apiKey].nil?
          raise ArgumentError.new "The deployment must be provided with a Bugsnag API KEY, through the configuration file or the api_key option"
        end
        send_notification(params[:endpoint], ::JSON.dump(options))
      end

      def self.description
        "Notifies Bugsnag of a build"
      end

      def self.authors
        ["cawllec"]
      end

      def self.return_value
        nil
      end

      def self.details
        "Notifies Bugsnag of build data including app version, git respository, release stage, and revision when a build action is run"
      end

      def self.is_supported?(platform)
        [:ios, :mac, :android].include?(platform)
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :config_file,
                                       description: "AppManifest.xml/Info.plist location",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :api_key,
                                       description: "Bugsnag API Key",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :app_version,
                                       description: "App version being built",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :release_stage,
                                       description: "Release stage being built, i.e. staging, production",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :repository,
                                       description: "The git repository URL for this application",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :revision,
                                       description: "The source control revision id",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :provider,
                                       description: "The name of the source control provider, only required for on-premise services",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :endpoint,
                                       description: "Bugsnag deployment endpoint",
                                       optional: true,
                                       default_value: "https://build.bugsnag.com")
        ]
      end

      private

      def self.get_android_options(params)
        require "xmlsimple"
        config_file = params[:config_file]
        begin
          config_hash = XmlSimple.xml_in(config_file)
        rescue ArgumentError => e
          raise ArgumentError.new "AndroidManifest.xml file not found, please point to your AndroidManifest file"
        end
        
        meta_data = map_meta_data(get_meta_data(config_hash))

        options = {}

        # Get API_KEY
        if meta_data.key?("com.bugsnag.android.API_KEY")
          options[:apiKey] = meta_data["com.bugsnag.android.API_KEY"]
        end

        # Get APP_VERSION
        if meta_data.key?("com.bugsnag.android.APP_VERSION")
          options[:appVersion] = meta_data["com.bugsnag.android.APP_VERSION"]
        end

        # Get RELEASE_STAGE
        if meta_data.key?("com.bugsnag.android.RELEASE_STAGE")
          options[:releaseStage] = meta_data["com.bugsnag.android.RELEASE_STAGE"]
        end

        options
      end

      def self.get_meta_data(object, output = [])
        if object.is_a?(Array)
          object.each do |item|
            output = get_meta_data(item, output)
          end
        elsif object.is_a?(Hash)
          object.each do |key, value|
            if key === "meta-data"
              output << value
            elsif value.is_a?(Array) || value.is_a?(Hash)
              output = get_meta_data(value, output)
            end
          end
        end
        output.flatten
      end

      def self.get_ios_options(params)
        config_file = params[:config_file]
        options = {}
        api_key = Fastlane::Actions::GetInfoPlistValue.run(path: config_file, key: "BugsnagAPIKey")
        if !api_key.nil?
          options[:apiKey] = api_key
        end
      end

      def self.get_git_options()
        require "git"
        options = {}
        begin
          repo = Git.open(Dir.pwd)
          options[:respository] = repo.branches['origin/master'].remote.url
          options[:branch] = repo.branch.full
        rescue ArgumentError => e
        end
        options
      end

      def self.map_meta_data(meta_data)
        output = {}
        meta_data.each do |hash|
          output[hash["android:name"]] = hash["android:value"]
        end
        output
      end

      def self.send_notification(url, body)
        require "net/http"
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 15
        http.open_timeout = 15

        http.use_ssl = uri.scheme == "https"

        uri.path == "" ? "/" : uri.path
        request = Net::HTTP::Post.new(uri, {"Content-Type" => "application/json"})
        request.body = body
        http.request(request)
        puts "Build notification sent to Bugsnag"
      end
    end
  end
end
