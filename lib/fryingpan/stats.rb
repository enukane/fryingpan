module FryingPan
  require "fryingpan/log"
  require "fryingpan/stats"
  require "json"

  class Stats
    EVENT_TYPE_WLAN_ASSOC=:assoc
    EVENT_TYPE_WLAN_DISASSOC=:disassoc
    EVENT_TYPE_DHCP_ASSIGN=:dhcp_assign
    EVENT_TYPE_DNS_QUERY=:dns_query
    EVENT_TYPE_HTTP_ACCESS=:http_access

    def initialize args={}
      now = Time.now
      basename = now.strftime("%Y%m%d%H%M%S")
      @fname = basename + ".json"

      @mactable = {}

      @info_table = {}

      @mutex = Mutex.new
    end

    def status
      return @info_table
    end

    def add_event args={}
      $log.info(JSON.dump(args))

      @mutex.synchronize {
        case args[:type]
        when EVENT_TYPE_WLAN_ASSOC
          add_event_wlan(args)
        when EVENT_TYPE_WLAN_DISASSOC
          add_event_wlan(args)
        when EVENT_TYPE_DHCP_ASSIGN
          add_event_dhcp(args)
        when EVENT_TYPE_DNS_QUERY
          add_event_dns(args)
        when EVENT_TYPE_HTTP_ACCESS
          add_event_http(args)
        else
          $log.warn("unknown event '#{args[:type]}' (#{JSON.dump(args)})")
        end
      }
    end

    def dump
      obj = status()
    end

    def add_event_wlan args
      # type, ifname, macaddr
      info = get_info_entry(args[:macaddr])
      return unless info

      case args[:type]
      when EVENT_TYPE_WLAN_ASSOC
        info[:wlan_assoc_count] += 1
      when EVENT_TYPE_WLAN_DISASSOC
        info[:wlan_disassoc_count] += 1
      end

      update_info_entry(args[:macaddr], info)
    end

    def add_event_dhcp args
      # type, dhcp_type, ifname, macaddr, ipaddr, hostname
      macaddr = args[:macaddr]
      ipaddr = args[:ipaddr]
      hostname = args[:hostname]

      info = get_info_entry(macaddr)
      return unless info

      info[:dhcp_event_count] += 1

      unless args[:dhcp_type] == :ack
        update_info_entry(macaddr, info)
        return
      end

      if macaddr && ipaddr
        update_mactable(macaddr, ipaddr)
      end

      info[:dhcp_ack_count] += 1
      if ipaddr
        info[:dhcp_assigned_ipaddrs] << ipaddr
      end
      if hostname
        info[:dhcp_hostnames] << hostname
      end

      info[:dhcp_assigned_ipaddrs].uniq!
      info[:dhcp_hostnames].uniq!

      update_info_entry(macaddr, info)
    end

    def add_event_dns args
      # type, name, record, ipaddr
      name = args[:name]
      ipaddr = args[:ipaddr]
      macaddr = ipaddr2macaddr(ipaddr)
      info = get_info_entry(macaddr)
      return unless info

      info[:dns_query_count] += 1
      if name
        info[:dns_queried_names] << name
      end
      info[:dns_queried_names].uniq!

      update_info_entry(macaddr, info)
    end

    def add_event_http args
      # type, ipaddr, uri, agent
      ipaddr = args[:ipaddr]
      uri = args[:uri]
      agent = args[:agent]

      macaddr = ipaddr2macaddr(ipaddr)
      info = get_info_entry(macaddr)
      return unless info

      info[:http_access_count] += 1
      if uri
        info[:http_accessed_uris] << uri
      end
      info[:http_accessed_uris].uniq!

      if agent
        info[:http_agents] << agent
      end
      info[:http_agents].uniq!

      update_info_entry(macaddr, info)
    end

    def get_info_entry macaddr
      return nil if macaddr == nil
      if @info_table[macaddr] == nil
        @info_table[macaddr] = {
          :last_update => 0,
          # counter
          :wlan_assoc_count => 0,
          :wlan_disassoc_count => 0,
          :dhcp_event_count => 0,
          :dhcp_ack_count => 0,
          :dns_query_count => 0,
          :http_access_count => 0,
          # dhcp
          :dhcp_assigned_ipaddrs => [],
          :dhcp_hostnames => [],
          # dns
          :dns_queried_names => [],
          # http
          :http_accessed_uris => [],
          :http_agents => [],
        }
      end

      return @info_table[macaddr]
    end

    def update_info_entry macaddr, info
      @info_table[macaddr] = info
      @info_table[macaddr][:last_update] = Time.now.to_i
    end

    def update_mactable macaddr, ipaddr
      @mactable[macaddr] = ipaddr
    end

    def macaddr2ipaddr macaddr
      return @mactable[_macaddr]
    end

    def ipaddr2macaddr ipaddr
      @mactable.each do |_macaddr, _ipaddr|
        return _macaddr if ipaddr == _ipaddr
      end
      return nil
    end
  end
end
