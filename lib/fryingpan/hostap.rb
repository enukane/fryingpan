module FryingPan
  require "erb"
  require "tempfile"
  require "open3"

  class HostAP
    HOSTAPD_CONF_FMT=<<__HOSTAPD_CONF__
ssid=<%= @ssid %>
interface=<%= @ifname %>
driver=nl80211
hw_mode=<%= @hostapd_mode %>
channel=<%= @channel %>
__HOSTAPD_CONF__

    CHAN24 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
    CHAN5  = [36, 40, 44, 48,
              52, 56, 60, 64,
              100, 104, 108, 112, 116,
              120, 124, 128, 132, 136, 140,
              149, 153, 157, 161, 165]

    MODE24 = "g"
    MODE5  = "a"

    def self.default_options
      {
        :ssid => "Out of Fire into the Frying pan",
        :ifname => "wlan0",
        :channel => 1,
        :debug => false,
      }
    end

    def self.verify_options opts
      self.default_options.keys.each do |key|
        raise "HostAP requires #{key}" if opts[key].nil?
      end

      if !CHAN24.include?(opts[:channel]) and !CHAN5.include?(opts[:channel])
        raise "HostAP requires valid channel (channel=#{opts[:channel]})"
      end
    end

    def dp fmt
      return unless @debug
      print "[DEBUG] #{fmt}\n"
    end

    def initialize args={}
      opts = (HostAP.default_options).merge(args)
      HostAP.verify_options(opts)

      dp "args => '#{args}'"

      @ssid = opts[:ssid]
      @ifname = opts[:ifname]
      @channel = opts[:channel]
      @debug = opts[:debug]

      @hostapd_mode = CHAN24.include?(@channel) ? MODE24 : MODE5

      @th_hostapd = nil
    end

    def alive?
      return false if @th_hostapd.nil?
      return @th_hostapd.alive?
    end

    def start
      dp "cmd START"
      unless @th_hostapd.nil?
        dp "actual start skipped (thread is already initialized)"
        return false
      end

      @conf_file = create_hostapd_config()
      dp "config path = '#{@conf_file.path}'"
      start_hostapd(@conf_file.path)

      dp "cmd START completed"
      return true
    rescue => e
      # hostapd failed?
      raise "hostapd: start failed (#{e})"
    end

    def stop
      dp "cmd STOP"
      stop_hostapd()
      @conf_file.close
    end

    def create_hostapd_config
      tmp_conf = Tempfile.new("hostap#{@ifname}", nil, "w")

      erb = ERB.new(HOSTAPD_CONF_FMT)

      conf_str = erb.result(binding)
      dp "generated conf:'\n#{conf_str}\n'"

      tmp_conf.write(conf_str)
      tmp_conf.fsync
      dp "hostapd config:'\n#{File.open(tmp_conf.path).read}\n'"

      return tmp_conf
    end

    def start_hostapd conf_path
      # could exit and return immediately
      pid_file = Tempfile.new("hostap#{@ifname}")

      cmdline = "hostapd -P /var/run/hostap.#{@ifname}.pid #{conf_path}"
      dp "start hostapd cmdline='#{cmdline}'"
      stdin, stdout, stderr, @th_hostapd = *Open3.popen3(cmdline)

      unless @th_hostapd.alive?
        raise "hostapd execution failed (#{stdout.read})"
      end

      return true
    end

    def stop_hostapd
      if @th_hostapd.nil? or @th_hostapd.stop?
        # already dead
        return false
      end

      Process.kill("INT", @th_hostapd.pid)
      return true
    end
  end
end

if __FILE__ == $0
  require "optparse"

  opt = OptionParser.new
  OPTS = FryingPan::HostAP.default_options

  opt.on("-s", "--ssid [SSID=#{OPTS[:ssid]}]", "SSID for AP") {|v|
    OPTS[:ssid] = v
  }

  opt.on("-i", "--interface [IFNAME=#{OPTS[:ifname]}", "interface to use") {|v|
    OPTS[:ifname] = v
  }

  opt.on("-c", "--channel [CHANNEL=#{OPTS[:channel]}", "channel") {|v|
    OPTS[:channel] = v.to_i
  }

  opt.on("-d", "--debug", "debug on") {|v|
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

  hostap = FryingPan::HostAP.new(OPTS)

  hostap.start

  Signal.trap("INT") {|signo|
    print "STOPPING hostap\n"
    hostap.stop
    print "STOPPED hostap\n"
  }

  while hostap.alive?
    sleep 1
  end

  print "TERMINATED hostap\n"

  exit 0
end
