module FryingPan
  require "sinatra"

  class HTTPGateway < Sinatra::Base
    DEFAULT_PORT = 80
    DEFAULT_PUBLIC_FOLDER = File.dirname(__FILE__) + "/../../extra/public/gw"
    set :port, DEFAULT_PORT
    set :bind, "0.0.0.0"
    set :public_folder, DEFAULT_PUBLIC_FOLDER
    disable :logging
    @@event_handler = nil

    def self.default_options
      {
        :port => DEFAULT_PORT,
        :public_folder => DEFAULT_PUBLIC_FOLDER,
      }
    end

    def self.run! args={}
      @@args = args
      @@port = args[:port] || DEFAULT_PORT
      @@public_folder = args[:public_folder] || DEFAULT_PUBLIC_FOLDER

      set :port, @@port
      set :public_folder, @@public_folder

      super
    end

    def self.register_handler &block
      @@event_handler = block
    end

    def self.handle_request method, request
      addr = request.env["REMOTE_ADDR"]
      uri = request.env["REQUEST_URI"]
      agent = request.env["HTTP_USER_AGENT"]

      if @@event_handler
        @@event_handler.call(method, addr, uri, agent)
      else
        p "no handler: addr=#{addr}, uri=#{uri}, agent=#{agent}"
      end
    end

    get "/favicon.ico" do
      headers "Server" => "FryingPan Server"
      # no favicon
      404
    end

    get "/*" do
      HTTPGateway.handle_request(:get, request)

      headers "Server" => "FryingPan Server"

      redirect to "/index.html"
    end

    post "/*" do
      HTTPGateway.handle_request(:post, request)

      headers "Server" => "FryingPan Server"

      "This is not Free Wi-Fi"
    end
  end
end

if __FILE__ == $0
  th = nil
  Signal.trap("INT") {|signo|
    unless FryingPan::HTTPGateway.running?
      p "http gateway is already dead?"
    end

    p "quiting gateway"
    FryingPan::HTTPGateway.quit!
    p "th => #{th}"
    th.kill unless th.nil?
    p "done trap"
  }

  FryingPan::HTTPGateway.register_handler do |method, addr, uri, agent|
    p "IN handler: #{method}, #{addr}, #{uri}, #{agent}"
  end

  th = Thread.new do
    FryingPan::HTTPGateway.run!({:port=>11185})
  end

  th.join
  p "halt"
end
