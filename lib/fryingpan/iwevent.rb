module FryingPan
  require "thread"
  require "open3"

  class IWevent
    REG=/^(?<timestamp>\d+\.\d+): (?<ifname>.+): (?<event>new|del) station (?<addr>.+)$/
    CMD="iw event -f -t"

    def initialize

      @stop_requested = false

      @connected_block = nil
      @disconnected_block = nil
    end

    def register_connected &block
      @connected_block = block
    end

    def register_disconnected &block
      @disconnected_block = block
    end

    def run async=false
      @stop_requested = false

      @th_do_run = Thread.new do
        do_run
      end

      unless async
        @th_do_run.join
      end
    end

    def do_run
      stdin, stdout, stderr, @th_iw = *Open3.popen3(CMD)

      if @th_iw.nil? or @th_iw.stop?
        raise "failed to execute iw event"
      end

      while !@stop_requested and @th_iw.alive?
        line = stdout.gets
        if line.nil?
          sleep 1
          next
        end

        match = line.match(REG)
        next unless match

        handle_event(match[:ifname], match[:timestamp], match[:event], match[:addr])
      end

      @th_iw = nil

      return
    end

    def stop
      @stop_requested = true
      if @th_iw and @th_
        begin
          Process.kill("INT", @th_iw.pid)
        rescue Errno::ESRCH
          # already dead, leave as is
        rescue => e
        end
      end
    end

    def handle_event ifname, timestamp, event, addr
      time = Time.at(timestamp.to_f)

      case event
      when "new"
        unless @connected_block.nil?
          @connected_block.call(time, ifname, addr)
        end
      when "del"
        unless @disconnected_block.nil?
          @disconnected_block.call(time, ifname, addr)
        end
      else
        p "unhandled event (ifname=#{ifname}, time=#{time}, event=#{event}, addr=#{addr}"
      end
    end
  end
end

if __FILE__ == $0
  iwevent = FryingPan::IWevent.new

  iwevent.register_connected do |time, ifname, addr|
    p "NEW: #{time} @#{ifname} = #{addr}"
  end

  iwevent.register_disconnected do |time, ifname, addr|
    p "DEL: #{time} @#{ifname} = #{addr}"
  end

  Signal.trap("INT") do |signo|
    print "stopping IWevent"
    iwevent.stop
  end

  iwevent.run

  exit 0
end
