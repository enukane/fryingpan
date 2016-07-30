class FryingPan
  require "erb"
  require "thread"
  require "open3"
  require "tempfile"

  class DHCPd
    DNSMASQ_CONFIG_FMT=<<FMT
<% if @fake_name %>
address=/#/<%= @addr %>
<% end %>

dhcp-range=<%= @start_addr %>,<%= @end_addr %>,<%= @lease %>
dhcp-option=option:router,<%= @addr %>
FMT

    REG_DHCP_DISCOVER = /^dhsmasq-dhcp: +DHCPDISCOVER\((?<ifname>.+)\) +(?<macaddr>.+)$/
    REG_DHCP_REQUEST = /^dhsmasq-dhcp: +DHCPREQUEST\((?<ifname>.+)\) +(?<ipaddr>.+) +(?<macaddr>.+)$/
    REG_DHCP_ACK = /^dnsmasq-dhcp: +DHCPACK\((?<ifname>.+)\) +(?<ipaddr>.+) +(?<macaddr>.+) +(?<hostname>.+)/

    REG_QUERY = /^dnsmasq: query\[(?<record>.+)\] +(?<name>.+) +from +(?<ipaddr>.+)/

    def self.default_options
      {
        :ifname => "wlan0",
        :addr=> "172.16.0.1",
        :start_addr => "172.16.0.2",
        :end_addr => "172.16.255.254",
        :lease => "24h",
        :fake_name => true,
        :debug => false,
      }
    end

    def self.verify_options args={}
      self.default_options.keys.each do |key|
        raise "missing #{key} (args=#{args})" if args[key].nil?
      end
    end

    def dp fmt
      return unless @debug
      print "[DEBUG] #{fmt}\n"
    end

    def initialize args={}
      args = DHCPd.default_options.merge(args)
      DHCPd.verify_options(args)

      @ifname = args[:ifname]
      @addr = args[:addr]
      @start_addr = args[:start_addr]
      @end_addr = args[:end_addr]
      @lease = args[:lease]
      @fake_name = args[:fake_name]
      @debug = args[:debug]
    end

    def run async=false
      @stop_requested = false

      @th_do_run = Thread.new do
        conf_file = create_config_file
        dp "conf_file path => #{conf_file.path}"
        start_dnsmasq(conf_file.path)
      end

      unless async
        @th_do_run.join
      end
    end

    def stop
      stop_dnsmasq
    end

    def register_dhcp_event &block
      @dhcp_event_handler = block
    end

    def register_dns_event &block
      @dns_event_handler = block
    end

    private
    def create_config_file
      tmp_conf = Tempfile.new("dnsmasq#{@ifname}", nil, "w")

      erb = ERB.new(DNSMASQ_CONFIG_FMT)
      conf_str = erb.result(binding)

      dp "config file => '\n#{conf_str}\n'"

      tmp_conf.write(conf_str)
      tmp_conf.fsync

      return tmp_conf
    end

    def start_dnsmasq conf_path
      stdin, stdout, stderr, @th_dnsmasq = *Open3.popen3(
        "dnsmasq -d -I lo -z -h -i #{@ifname} -C #{conf_path} -q"
      )

      unless @th_dnsmasq.alive?
        raise "dnsmasq execution failed (#{stdout.read}, #{stderr.read})"
      end

      dp "dnsmasq at PID #{@th_dnsmasq.pid}"

      while !@stop_requested and @th_dnsmasq.alive?
        line = stderr.gets
        if line.nil?
          sleep 1
          next
        end

        handle_line(line)
      end

      @th_dnsmasq = nil

      return
    end

    def stop_dnsmasq
      if @th_dnsmasq.nil? or @th_dnsmasq.stop?
        return false
      end

      Process.kill("INT", @th_dnsmasq.pid)
      return true
    end

    def handle_line line
      dp "LINE = '#{line.strip}'"
      case line
      when REG_DHCP_DISCOVER
        ifname = $1
        macaddr = $2
        handle_dhcp_event(:discover, ifname, macaddr, nil, nil)
      when REG_DHCP_REQUEST
        ifname = $1
        ipaddr = $2
        macaddr = $3
        handle_dhcp_event(:request, ifname, macaddr, ipaddr, nil)
      when REG_DHCP_ACK
        ifname = $1
        ipaddr = $2
        macaddr = $3
        hostnaem = $4
        handle_dhcp_event(:ack, ifname, macaddr, ipaddr, hosname)
      when REG_QUERY
        record = $1
        name = $2
        ipaddr = $3
        handle_dns_event(:query, name, record, ipaddr)
      end
    end

    def handle_dhcp_event type, ifname, macaddr, ipaddr, hostname
      return unless @dhcp_event_handler
      @dhcp_event_handler.call(type, ifname, macaddr, ipaddr, hostname)
    end

    def handle_dns_event type, name, record, ipaddr
      return unless @dns_event_handler
      @dns_event_handler.call(type, name, record, ipaddr)
    end

  end
end

if __FILE__ == $0
  require "optparse"

  opt = OptionParser.new
  OPTS = FryingPan::DHCPd.default_options

  opt.on("-i", "--interface [IFNAME=#{OPTS[:ifname]}]", "listen interface") {|v|
    OPTS[:ifname] = v
  }

  opt.on("-d", "--debug", "enable debug"){|v|
    OPTS[:debug] = true
  }

  (class<<self;self;end).module_eval do
    define_method(:usage) do |msg|
      puts opt.to_s
      puts "error: #{msg}" if msg
      exit 1
    end
  end

  begin
    rest = opt.parse(ARGV)
    if rest.length != 0
      usage nil
    end
  rescue
    usage $!.to_s
  end

  dhcpd = FryingPan::DHCPd.new(OPTS)

  dhcpd.register_dhcp_event do |type, ifname, macaddr, ipaddr, hostname|
    print "DHCP: type=#{type}, ifname=#{ifname}, macaddr=#{macaddr}, ipaddr=#{ipaddr} hostname=#{hostname}\n"
  end

  dhcpd.register_dns_event do |type, name, record, ipaddr|
    print "DNS:  type=#{type}, name=#{name}, record=#{record}, ipaddr=#{ipaddr}\n"
  end

  Signal.trap("INT") {|signo|
    print "STOPPING dhcpd\n"
    dhcpd.stop
    print "STOPPED dhcpd\n"
  }

  at_exit do
    dhcpd.stop
  end

  dhcpd.run

  exit 0
end
