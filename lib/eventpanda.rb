require 'eventpanda/ffi-libevent'

require 'eventpanda/reactor'
require 'eventpanda/timer'
require 'eventpanda/connection'
require 'eventpanda/pipe'
require 'eventpanda/version'

require 'eventpanda/em/eventmachine' if ENV['SKIP_EM']


module EventPanda
  def self.stop
    cleanup_libevent_sockets!
    @reactor_running = false
    EventPanda.event_base_loopbreak(Thread.current[:ev_base])
  end

  def self.cleanup_libevent_sockets!
    # close client connections
    EventPanda::TCP::Client.locked.each(&:close_connection)
    EventPanda::TCP::Client.locked.clear

    # close listener sockets and its client connections
    if Thread.current[:ev_base_lvs]
      Thread.current[:ev_base_lvs].each{|i|
        i.connections.each(&:close_connection)
        i.close!
      }
    end
  end

  def self.epoll
    # libevent uses epoll if found. you can configure it
    # to specifically ask for it though. implement later..
  end

  ::EM = ::EventMachine = EventPanda
end



module EventPanda
  def self.start_server(host, port, handler, *args, &blk)
    (Thread.current[:ev_base_lvs] ||= []) <<
      EventPanda::TCP::Server.new(Thread.current[:ev_base], host, port, handler, *args, &blk)
  end

  def self.connect(host, port, handler, *args, &blk)
    EventPanda::TCP::Client.create_connection(Thread.current[:ev_base], host, port, handler, *args, &blk)
  end
end


module EventPanda
module TCP
  class Server
    attr_reader :connections

    def initialize(base, host, port, handler, *connection_args, &connection_init)
      @host, @port = host, port
      @base = base || Thread.current[:ev_base]

      @connections = []
      @conn = {
        :handler => handler,
        :args    => connection_args,
        :init    => connection_init,
      }

      start_listen!
    end

    def start_listen!
      @sin = Socket.sockaddr_in(@port.to_s, @host.to_s)
      @sin_ptr, @sin_size = FFI::MemoryPointer.from_string(@sin), @sin.size

      @listen = EventPanda.evconnlistener_new_bind(@base, @accept_cb = method(:accept_connection), nil,
        EventPanda::LEV_OPT_CLOSE_ON_FREE|EventPanda::LEV_OPT_REUSEABLE, -1, @sin_ptr, @sin_size)
      EventPanda.evconnlistener_set_error_cb(@listen, @error_cb = method(:accept_error))
      @listen_signal_tick = EM::PeriodicTimer.new(2.5){ :nop } # catch signals, wakeup libevent loop.
    end

    def accept_error(lisener, ctx)
      p "accept connection error"
      #EM.event_base_loopexit(base)
    end

    def accept_connection(listener, fd, sockaddr_ptr, socklen, ctx)
      sockaddr = sockaddr_ptr.read_string(socklen)
      #p ["new connection", fd, Socket.unpack_sockaddr_in(sockaddr)]

      base = EventPanda.evconnlistener_get_base(listener)
      bev  = EventPanda.bufferevent_socket_new(base, fd,
               EventPanda::BEV_OPT_CLOSE_ON_FREE|EventPanda::BEV_OPT_DEFER_CALLBACKS)

      free_cb = proc{|conn| @connections.delete(conn) }

      if !bev.null?
        conn = @conn[:handler].new(*@conn[:args]).init_connection(fd, sockaddr, bev, free_cb)
        @connections << conn

        @conn[:init].call(conn) if @conn[:init].respond_to?(:call)
        conn.post_init
      end
    end

    def close! # shutdown tcp server
      @listen_signal_tick.cancel
      EventPanda.evconnlistener_free(@listen); @listen = nil
    end
  end


  class Client
    def self.create_connection(base, host, port, handler, *connection_args, &connection_init)
      sin  = Socket.sockaddr_in(port.to_s, host.to_s)
      sin_ptr, sin_size = FFI::MemoryPointer.from_string(sin), sin.size

      bev = EventPanda.bufferevent_socket_new(base, -1,
              EventPanda::BEV_OPT_CLOSE_ON_FREE|EventPanda::BEV_OPT_DEFER_CALLBACKS)

      free_cb = proc{|conn| @locked.delete(conn) }

      if !bev.null?
        conn = handler.new(*connection_args).init_connection(-1, [host, port], bev, free_cb)
        EventPanda.bufferevent_socket_connect(bev, sin_ptr, sin_size)
        @locked << conn

        connection_init.call(conn) if connection_init
        conn
      end
    end

    @locked = []; def self.locked; @locked; end
  end
end # TCP
end # EventPanda
