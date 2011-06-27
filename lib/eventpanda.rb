require 'eventpanda/ffi-libevent'

require 'eventpanda/reactor'
require 'eventpanda/deferrable.rb'
require 'eventpanda/timer'
require 'eventpanda/connection'
require 'eventpanda/pipe'
require 'eventpanda/version'

require 'eventpanda/em/eventmachine' if ENV['SKIP_EM']


module EventPanda
  def self.stop
    cleanup_libevent_sockets!
    @reactor_running = false
    EventPanda.stop_event_loop
  end

  def self.cleanup_libevent_sockets!
    TCP::Client.cleanup_sockets
    TCP::Server.cleanup_sockets
  end

  def self.epoll
    # libevent uses epoll if found. you can configure it
    # to specifically ask for it though. implement later..
  end

  def self.start_server(host, port, handler, *args, &blk)
    EventPanda::TCP::Server.new(Thread.current[:ev_base], host, port, handler, *args, &blk)
  end

  def self.connect(host, port, handler, *args, &blk)
    EventPanda::TCP::Client.new(Thread.current[:ev_base], host, port, handler, *args, &blk)
  end

  ::EM = ::EventMachine = EventPanda
end

module EventPanda
module TCP

  class Server
    attr_reader :connections

    def initialize(base, host, port, handler, *connection_args, &connection_init)
      self.class.sockets << self
      @sin = FFI::MemoryPointer.from_string(Socket.sockaddr_in(port.to_s, host.to_s))

      @connections = []
      @conn = { :handler => handler, :args => connection_args, :init => connection_init }

      @listen = Libevent.evconnlistener_new_bind(base, @accept_cb = method(:accept_connection), nil,
        Libevent::LEV_OPT_CLOSE_ON_FREE|Libevent::LEV_OPT_REUSEABLE, -1, @sin, @sin.size)
      Libevent.evconnlistener_set_error_cb(@listen, @error_cb = method(:accept_error))

      @signal_tick = EM::PeriodicTimer.new(2.5){ :nop } # catch signals, wakeup libevent loop.
    end

    def accept_error(lisener, ctx)
      p "accept connection error"
    end

    def accept_connection(listener, fd, sockaddr_ptr, socklen, ctx)
      bev  = Libevent.bufferevent_socket_new(Libevent.evconnlistener_get_base(listener), fd,
               Libevent::BEV_OPT_CLOSE_ON_FREE|Libevent::BEV_OPT_DEFER_CALLBACKS)

      free_cb = proc{|conn| @connections.delete(conn) }

      unless bev.null?
        sockaddr = sockaddr_ptr.read_string(socklen)
        conn = @conn[:handler].new(*@conn[:args]).init_connection(fd, sockaddr, bev, free_cb)
        @connections << conn

        @conn[:init].call(conn) if @conn[:init].respond_to?(:call)
        conn.post_init
      end
    end

    def close_connection
      @connections.each{|c| c.close_connection }
      @signal_tick.cancel
      Libevent.evconnlistener_free(@listen); @listen = nil
    end

    def self.sockets; Thread.current[:ev_tcp_server_sockets] ||= []; end
    def self.cleanup_sockets; sockets.each{|c| c.close_connection }; end
  end


  class Client
    def self.new(base, host, port, handler, *connection_args, &connection_init)
      bev = Libevent.bufferevent_socket_new(base, -1,
              Libevent::BEV_OPT_CLOSE_ON_FREE|Libevent::BEV_OPT_DEFER_CALLBACKS)

      free_cb = proc{|conn| self.sockets.delete(conn) }

      unless bev.null?
        conn = handler.new(*connection_args).init_connection(-1, [host, port], bev, free_cb)

        sin = FFI::MemoryPointer.from_string(Socket.sockaddr_in(port.to_s, host.to_s))
        Libevent.bufferevent_socket_connect(bev, sin, sin.size)
        self.sockets << conn

        connection_init.call(conn) if connection_init
        conn
      end
    end

    def self.sockets; Thread.current[:ev_tcp_client_sockets] ||= []; end
    def self.cleanup_sockets; sockets.each{|c| c.close_connection }; end
  end

end # TCP
end # EventPanda
