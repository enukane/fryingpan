module FryingPan
  require "fryingpan/hostap"
  require "fryingpan/dhcp"
  require "fryingpan/iwevent"
  require "fryingpan/httpgw"
  require "fryingpan/log"

  class Daemon
    DEFAULT_IFNAME="wlan0"
    DEFAULT_SSID="Not Free Wi-Fi"
    DEFAULT_CHANNEL=1
    DEFAULT_LOG_PATH="/log"
    DEFAULT_HTTP_PORT=80
    DEFAULT_CONTROL_PORT=8080

    DEFAULT_DEBUG=false


    def self.default_options
      {
        :ifname => DEFAULT_IFNAME,
        :ssid => DEFAULT_SSID,
        :channel => 1,
        :log_path => DEFAULT_LOG_PATH,
        :http_port => DEFAULT_HTTP_PORT,
        :control_port => DEFAULT_CONTROL_PORT,

        :debug => DEFAULT_DEBUG,
      }
    end

    def self.verify_options args={}
      self.default_options.keys.each do |key|
        raise "missing #{key} (args=#{args})" if args[key].nil?
      end

      unless args[:channel].is_a?(Fixnum)
        raise "channel is not number (channel=#{args[:channel]})"
      end

      unless args[:http_port].is_a?(Fixnum)
        raise "http_port is not number (http_port=#{args[:http_port]})"
      end

      unless args[:control_port].is_a?(Fixnum)
        raise "control_port is not number (control_port=#{args[:control_port]})"
      end
    end

    def initialize args={}
      Daemon.verify_options(args)

      @args = args
      @ifname = args[:ifname]
      @ssid = args[:ssid]
      @channel = args[:channel]
      @log_path = args[:log_path]
      @http_port = args[:http_port]

      @debug = args[:debug]

      @stop_requested = false
    end

    def run
      # setup system
      prepare_system

      # setup hostap
      prepare_hostap

      # setup dhcp
      prepare_dhcp

      # setup iwevent
      prepare_iwevent

      # setup httpgw
      prepare_httpgw
    end

    def stop
      @stop_requested = true

      @hostap.stop if @hostap
      @dhcp.stop if @dhcp
      @iwevent.stop if @iwevent
      if @th_httpgw
        @th_httpgw.kill
        FryingPan::HTTPGateway.quit!
        @th_httpgw = nil
      end
    end

    def status
      # TODO:
    end

    def prepare_system
      # XXX: should revert all these change

      # disable ipv4 forwarding
      unless system("sysctl -w net.ipv4.conf.#{@ifname}.forwarding=0")
        raise "failed to disable ipv4 forwarding"
      end

      # disable ipv6 forwarding
      unless system("sysctl -w net.ipv4.conf.#{@ifname}.forwarding=0")
        raise "failed to disable ipv4 forwarding"
      end
    end

    def prepare_hostap
      opts = FryingPan::HostAP.default_options
      opts.merge!(@args)

      @hostap = FryingPan::HostAP.new(opts)
      @hostap.start
    end

    def prepare_dhcp
      opts = FryingPan::DHCPd.default_options
      opts.merge!(@args)

      @dhcp = FryingPan::DHCPd.new(opts)

      @dhcp.register_dhcp_event do |type, ifname, macaddr, ipaddr, hostname|
        #  TODO:
        $log.info "DHCP:\t#{type} at #{ifname} from #{macaddr} (hostname=#{hostname}) assigned #{ipaddr}"
      end

      @dhcp.register_dns_event do |type, name, record, ipaddr|
        # TODO:
        $log.info "DNS:\t#{type} name=#{name} record=#{record} from #{ipaddr}"
      end

      @dhcp.run(true) # async
    end

    def prepare_iwevent
      @iwevent = FryingPan::IWevent.new

      # connected
      @iwevent.register_connected do |time, ifname, addr|
        # TODO:
        $log.info "WLAN-A:\t#{addr} leaves from #(ifname) (time=#{time})"
      end

      # disconnected
      @iwevent.register_disconnected do |time, ifname, addr|
        # TODO:
        $log.info "WLAN-D:\t#{addr} leaves from #(ifname) (time=#{time})"
      end

      @iwevent.run(true) # async
    end

    def prepare_httpgw
      opts = FryingPan::HTTPGateway.default_options
      opts[:port] = @http_port

      FryingPan::HTTPGateway.register_handler do |method, addr, uri, agent|
        # TODO:
        $log.info "HTTP:\t#{addr} does #{method} to #{uri} (agent=#{agent})"
      end

      @th_httpgw = Thread.new do
        FryingPan::HTTPGateway.run!(opts)
      end
    end

  end
end
