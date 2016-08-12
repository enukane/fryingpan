module FryingPan
  require "fryingpan/command/fryingpand"
  require "fryingpan/hostap"
  require "fryingpan/dhcp"
  require "fryingpan/iwevent"
  require "fryingpan/httpgw"
  require "fryingpan/log"

  require "sinatra/base"
  require "json"

  class APIServer < Sinatra::Base
    DEFAULT_CONTROL_PORT=8080
    DEFAULT_PUBLIC_FOLDER = File.dirname(__FILE__) + "/../../extra/public/ctrl"


    # set :bind, "127.0.0.1"  # only for myself
    set :port, DEFAULT_CONTROL_PORT
    set :public_folder, DEFAULT_PUBLIC_FOLDER

    @@args = {}
    @@port = DEFAULT_PUBLIC_FOLDER
    @@daemon = nil

    def self.default_options
      return FryingPan::Daemon.default_options
    end

    def self.run! args={}
      args = self.default_options.merge(args)
      @@args = args

      @@port = args[:control_port] || DEFAULT_CONTROL_PORT
      set :port, @@port

      super
    end

    get "/" do
      redirect to ("/index.html")
    end

    get "/api/v1/status" do
      if @@daemon
        return JSON.dump(@@daemon.status)
      else
        status 404
      end
    end

    post "/api/v1/start" do
      #  {
      #     :channel => n
      #  }

      begin
        data = request.body.read
        json = JSON.parse(data)
        if @@daemon
          raise "still running"
        end

        # TODO: start daemon
        opts = FryingPan::Daemon.default_options
        opts[:ssid] = @@args[:ssid]
        opts[:ifname] = @@args[:ifname]
        opts[:channel] = json[:channel] || @@args[:channel]
        opts[:log_path] = @@args[:log_path]

        @@daemon = FryingPan::Daemon.new(opts)

        @@daemon.run

        status 200
        "success"
      rescue => e
        $log.err "failed to start daemon (#{e})"

        status 500
        "failed (#{e})"
      end
    end

    post "/api/v1/stop" do
      begin
        unless @@daemon
          raise "not running"
        end

        # TODO: stop daemon
        @@daemon.stop
        @@daemon = nil

        status 200
        "success"
      rescue => e
        $log.err "failed to stop daemon (#{e})"

        status 500
        "failed (#{e})"
      end
    end

  end
end

