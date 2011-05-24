require 'eventpanda/ffi-libevent'

require 'eventpanda/reactor'
require 'eventpanda/timer'
require 'eventpanda/connection'
require 'eventpanda/pipe'
require 'eventpanda/version'


module EventPanda
  def self.stop
    cleanup_libevent_sockets!
    EventPanda.event_base_loopexit(Thread.current[:ev_base], nil)
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

  ::EM = EventPanda
end


module EventPanda
  def self.start_server(host, port, klass, *args)
    Thread.current[:ev_base_lvs] ||= []
    Thread.current[:ev_base_lvs] <<
      EventPanda::TCP::Server.new(Thread.current[:ev_base], host, port, klass, args)
  end

  def self.connect(host, port, klass, *args)
    EventPanda::TCP::Client.create_connection(Thread.current[:ev_base], host, port, klass, args)
  end
end


module EventPanda
module TCP
  class Server
    def initialize(base, host, port, klass, klass_args)
      @klass, @klass_args = klass, klass_args
      @host, @port = host, port

      @sin = Socket.sockaddr_in(port.to_s, host.to_s)
      @sin_ptr, @sin_size = FFI::MemoryPointer.from_string(@sin), @sin.size

      @base = base || Thread.current[:ev_base]
      @listen = EventPanda.evconnlistener_new_bind(@base, @accept_cb = method(:accept_connection), nil,
        EventPanda::LEV_OPT_CLOSE_ON_FREE|EventPanda::LEV_OPT_REUSEABLE, -1, @sin_ptr, @sin_size)
      EventPanda.evconnlistener_set_error_cb(@listen, @error_cb = method(:accept_error))

      @connections = []
    end

    attr_reader :connections

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
        conn = @klass.new(*@klass_args).init_connection(fd, sockaddr, bev, free_cb)
        @connections << conn
        conn.post_init
      end
    end

    def close! # shutdown tcp server
      EventPanda.evconnlistener_free(@listen); @listen = nil
    end
  end


  class Client
    def self.create_connection(base, host, port, klass, klass_args)
      sin  = Socket.sockaddr_in(port.to_s, host.to_s)
      sin_ptr, sin_size = FFI::MemoryPointer.from_string(sin), sin.size

      bev = EventPanda.bufferevent_socket_new(base, -1,
              EventPanda::BEV_OPT_CLOSE_ON_FREE|EventPanda::BEV_OPT_DEFER_CALLBACKS)

      free_cb = proc{|conn| @locked.delete(conn) }

      if !bev.null?
        conn = klass.new(*klass_args).init_connection(-1, [host, port], bev, free_cb)
        EventPanda.bufferevent_socket_connect(bev, sin_ptr, sin_size)

        @locked << conn
        conn
      end
    end

    @locked = []; def self.locked; @locked; end
  end
end # TCP
end # EventPanda
