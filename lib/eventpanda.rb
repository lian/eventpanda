require 'ffi'
require 'socket'

module EventPanda
  extend FFI::Library
  #ffi_lib 'event'
  ffi_lib 'event_core'

  EVLOOP_ONCE     = 1
  EVLOOP_NONBLOCK = 2

  # event base loop
  attach_function :event_base_new, [], :pointer
  attach_function :event_base_free, [:pointer], :void
  attach_function :event_base_get_method, [:pointer], :string
  #attach_function :event_init, [], :int
  #attach_function :event_dispatch, [], :int
  attach_function :event_base_dispatch, [:pointer], :int
  attach_function :event_base_loop, [:pointer, :int], :int
  attach_function :event_base_loopexit, [:pointer, :pointer], :int
  attach_function :event_base_loopbreak, [:pointer], :int

  # events/timers
  callback :event_callback, [:pointer, :pointer], :void
  attach_function :event_new, [:pointer, :int, :short, :event_callback], :pointer
  attach_function :event_add, [:pointer, :pointer], :int
  attach_function :event_assign, [:pointer, :pointer, :int, :int, :event_callback], :pointer
  attach_function :event_del, [:pointer], :int
  attach_function :event_free, [:pointer], :int

  # evbuffers
  attach_function :evbuffer_new, [], :pointer
  attach_function :evbuffer_free, [:pointer], :int
  attach_function :evbuffer_add_printf, [:pointer, :string], :int
  attach_function :evbuffer_add_buffer, [:pointer, :pointer], :int
  attach_function :evbuffer_readline, [:pointer], :string

  # start server
  callback :accept_error_cb, [:pointer, :pointer], :void
  callback :accept_connection_cb, [:pointer, :uint, :pointer, :int, :pointer], :void
  attach_function :evconnlistener_set_error_cb, [:pointer, :accept_error_cb], :int
  attach_function :evconnlistener_new_bind, [:pointer, :accept_connection_cb, :pointer, :uint, :int, :pointer, :int], :pointer
  attach_function :evconnlistener_free, [:pointer], :void
  attach_function :evconnlistener_enable, [:pointer], :int
  attach_function :evconnlistener_disable, [:pointer], :int

  # new connection
  attach_function :evconnlistener_get_base, [:pointer], :pointer
  attach_function :bufferevent_socket_new, [:pointer, :uint, :int], :pointer

  # connection callbacks
  callback :bev_data_cb,  [:pointer, :pointer], :void
  callback :bev_event_cb, [:pointer, :short, :pointer], :void
  attach_function :bufferevent_setcb, [:pointer, :bev_data_cb, :bev_data_cb, :bev_event_cb, :pointer], :void
  attach_function :bufferevent_enable, [:pointer, :short], :int
  attach_function :bufferevent_disable, [:pointer], :int
  attach_function :bufferevent_get_input, [:pointer], :pointer
  attach_function :bufferevent_get_output, [:pointer], :pointer

  # evhttp (disabled for now)
  #attach_function :evhttp_start, [:string, :int], :pointer
  #callback :evhttp_callback, [:pointer, :pointer], :void
  #attach_function :evhttp_set_gencb, [:pointer, :evhttp_callback, :pointer], :int
  #attach_function :evhttp_send_reply, [:pointer, :int, :string, :pointer], :int

  attach_function :evbuffer_write, [:pointer, :uint], :int
  attach_function :evbuffer_write_atmost, [:pointer, :uint, :uint], :int
  attach_function :evbuffer_read, [:pointer, :uint, :int], :int
  attach_function :evbuffer_get_length, [:pointer], :int

  attach_function :bufferevent_read, [:pointer, :pointer, :uint], :int
  attach_function :bufferevent_write, [:pointer, :pointer, :uint], :int

  attach_function :bufferevent_socket_connect, [:pointer, :pointer, :uint], :int
  attach_function :event_get_fd, [:pointer], :int
  attach_function :bufferevent_getfd, [:pointer], :int
  attach_function :bufferevent_free, [:pointer], :int


  BUFFEREVENT_SSL_ACCEPTING = 2
  BEV_OPT_DEFER_CALLBACKS = 4

  LEV_OPT_CLOSE_ON_FREE = 2
  LEV_OPT_REUSEABLE     = 8
  BEV_OPT_CLOSE_ON_FREE = 1
  EV_TIMEOUT = 1
  EV_READ = 2
  EV_WRITE = 4
  EV_PERSIST = 10


  # bufferevent thread locking
  # @ffi_lib_flags = FFI::DynamicLibrary::RTLD_LAZY | FFI::DynamicLibrary::RTLD_GLOBAL
  # ffi_lib 'event_core', 'event_pthreads'
  # @ffi_lib_flags = nil
  # attach_function :bufferevent_lock, [:pointer], :int


  def self.run(&block)
    Thread.current[:ev_base] ||= EventPanda.event_base_new
    base = Thread.current[:ev_base]
    
    block.call if block
    EventPanda.event_base_loop(Thread.current[:ev_base], 0)

    Thread.current[:ev_base] = nil
    #EventPanda.event_base_free(base); base = nil
    true
  end

  def self.stop
    close_running_listeners!
    EventPanda.event_base_loopexit(Thread.current[:ev_base], nil)
  end

  def self.close_running_listeners!
    if Thread.current[:ev_base_lvs]
      Thread.current[:ev_base_lvs].each(&:close!)
      Thread.current[:ev_base_lvs].clear
    end
    #Thread.current[:ev_base_cvs].each(&:close_connection)
    #Thread.current[:ev_base_cvs].clear
  end

  ::EM = EventPanda
end


module EventPanda # Timers

  # Creates a one-time timer
  #
  #  timer = EventPanda::Timer.new(5) do
  #    # this will never fire because we cancel it
  #  end
  #  timer.cancel
  #
  class Timer
    def initialize(interval, callback=nil, base=nil, &block)
      @block = callback || block
      @signature = EventPanda.event_new(base || Thread.current[:ev_base], -1, 0, @block)
      @tv = FFI::MemoryPointer.new(:int, 2).put_array_of_int(0, [interval || 0, 0])
      schedule!
    end

    def schedule!
      EventPanda.event_add(@signature, @tv) if @signature
    end

    def cancel
      EventPanda.event_free(@signature)
      @signature, @tv, @block = nil, nil, nil
    end
  end

  # Creates a periodic timer
  #
  #  n = 0
  #  timer = EventPanda::PeriodicTimer.new(5) do
  #    puts "the time is #{Time.now}"
  #    timer.cancel if (n+=1) > 5
  #  end
  #
  class PeriodicTimer < Timer
    def initialize(interval, callback=nil, base=nil, &block)
      @callback = callback || block
      @cb = proc{ @callback.call; schedule! }
      super(interval, @cb, base)
    end
  end

  def self.add_timer(i, &b); EventPanda::Timer.new(i, b); end
  def self.add_periodic_timer(i, &b); EventPanda::PeriodicTimer.new(i, b); end
end


module EventPanda

  class Connection
    def init_connection(fd, sockaddr, bev)
      @fd, @sockaddr, @bev = fd, sockaddr, bev
      init_bev if @bev
      self
    end

    def init_bev
      EventPanda.bufferevent_setcb(@bev,
        @_data_cb = method(:_data_cb), nil, @_event_cb = method(:_event_cb), nil)
      EventPanda.bufferevent_enable(@bev, EventPanda::EV_READ|EventPanda::EV_WRITE)

      @bev_input  = EventPanda.bufferevent_get_input(@bev)
      @bev_output = EventPanda.bufferevent_get_output(@bev)
      @bev_tmp    = FFI::MemoryPointer.new(:uint8, 4096 / 2)
    end

    def initialize(*args); end
    def post_init; end
    def receive_data(data); end
    def unbind; end

    def close_connection
      EventPanda.bufferevent_free(@bev); unbind
    end

    def send_data(data)
      length = data.size
      #length = @bev_tmp.size if length > @bev_tmp.size
      EventPanda.bufferevent_write(@bev, @bev_tmp.put_string(0, data), length)
    end

    def _data_cb(bev, ctx)
      length = EventPanda.evbuffer_get_length(@bev_input)
      #length = @bev_tmp.size if length > @bev_tmp.size
      EventPanda.bufferevent_read(@bev, @bev_tmp, length)
      receive_data(@bev_tmp.read_string(length))
    end

    def _event_cb(bev, events, ctx)
      case events
        when 128 # connected (happens only with #connect or ssl)
          unless @use_ssl # with ssl dont run post_init again. accept_connection does this.
            @fd = EventPanda.bufferevent_getfd(@bev) # update fd ivar
            post_init
          end
          #init_ssl_for_connection if @use_ssl # post_init can set @use_ssl
        when 32  # ssl connection closed
          unbind
        when 33  # ?
          p ["event_cb", events]
          # close_connection
        when 17  # connection closed
          unbind
        else
          p ["unkown event_cb", events]
          #close_connection
      end
    end

    def method_missing(*a)
      if a.first == :start_tls
        self.extend EventPanda::SSL::ConnectionMethods
        send(*a)
      else
        super(*a)
      end
    end
  end

  autoload :SSL, "eventpanda/ssl"

  attach_function :event_enable_debug_mode, [], :void

  module TCP
  class Server
    def initialize(base, host, port, klass, klass_args)
      @klass, @klass_args = klass, klass_args
      @host, @port = host, port

      @sin = Socket.sockaddr_in(port.to_s, host.to_s)
      @sin_ptr, @sin_size = FFI::MemoryPointer.from_string(@sin), @sin.size

      @base = base || Thread.current[:ev_base]
      @listen = EventPanda.evconnlistener_new_bind(@base, method(:accept_connection), nil,
        EventPanda::LEV_OPT_CLOSE_ON_FREE|EventPanda::LEV_OPT_REUSEABLE, -1, @sin_ptr, @sin_size)
      EventPanda.evconnlistener_set_error_cb(@listen, method(:accept_error))

      #Thread.current[:ev_base_lvs] ||= []
      #Thread.current[:ev_base_lvs] << self
    end

    def accept_error(lisener, ctx)
      p "accept connection error"
      #EM.event_base_loopexit(base)
    end

    def accept_connection(listener, fd, sockaddr_ptr, socklen, ctx)
      sockaddr = Socket.unpack_sockaddr_in(sockaddr_ptr.get_array_of_uint8(0, socklen).pack("C*")).reverse
      p ["new connection", fd, sockaddr]

#=begin
      base = EventPanda.evconnlistener_get_base(listener)
      bev  = EventPanda.bufferevent_socket_new(base, fd, EventPanda::BEV_OPT_CLOSE_ON_FREE)

      if !bev.null?
        conn = @klass.new(*@klass_args).init_connection(fd, sockaddr, bev)
        conn.post_init
        conn
      end
#=end
    end

    def close! # shutdown tcp server
      EventPanda.evconnlistener_free(@listen); @listen = nil
    end
  end


  class Client
    attr_reader :conn
    def initialize(base, host, port, klass, klass_args)
      @base = base || Thread.current[:ev_base]
      @sin  = Socket.sockaddr_in(port.to_s, host.to_s)
      @sin_ptr, @sin_size = FFI::MemoryPointer.from_string(@sin), @sin.size

      @bev = EventPanda.bufferevent_socket_new(@base, -1,
        EventPanda::BEV_OPT_CLOSE_ON_FREE)
      #EventPanda.bufferevent_enable(@bev, EventPanda::EV_READ|EventPanda::EV_WRITE)
      #EventPanda.bufferevent_lock(@bev)

      if !@bev.null?
        @conn = klass.new(*klass_args).init_connection(-1, [host, port], @bev)
        #EM.add_timer(0){
          EventPanda.bufferevent_socket_connect(@bev, @sin_ptr, @sin_size)
        #}
        @conn
      end
    end
  end
  end

  def self.start_server(host, port, klass, *args)
    EventPanda::TCP::Server.new(Thread.current[:ev_base], host, port, klass, args)
  end

  def self.connect(host, port, klass, *args)
    EventPanda::TCP::Client.new(Thread.current[:ev_base], host, port, klass, args)
  end

end


if $0 == __FILE__
  EM.run do

    timer = EM::PeriodicTimer.new(1){  p [Time.now.tv_sec] }


    class SSL_TestServer < EM::Connection
      def post_init
        p ['server post_init', @fd, @sockaddr, 'new client connection']
        start_tls(
          :private_key_file => File.join(File.dirname(__FILE__), '../spec/eventpanda/client.key'),
          :cert_chain_file  => File.join(File.dirname(__FILE__), '../spec/eventpanda/client.crt')
        )
      end

      def receive_data(data)
        p ['server receive_data', @fd, @sockaddr, data]
        send_data(data)
      end

      def unbind
        p ['server unbind', @fd, @sockaddr]
      end
    end

    EM.start_server("127.0.0.1", 4000, SSL_TestServer)
  end
end



__END__
if $0 == __FILE__
  EM.run do

    timer = EM::PeriodicTimer.new(1){  p [Time.now.tv_sec] }

    class TestServer < EM::Connection
      def post_init
        p ['server post_init', @fd, @sockaddr, 'got new client connection']
      end

      def receive_data(data)
        p ['server receive_data', @fd, @sockaddr, data]
        send_data(data)
      end

      def unbind
        p ['server unbind', @fd, @sockaddr]

        EM::add_timer(3){ EM.stop }
      end
    end

    class TestClient < EM::Connection
      def post_init
        p ['client post_init', @fd, @sockaddr]
        send_data("hi\n")
      end

      def receive_data(data)
        p ['client receive_data', @fd, @sockaddr, data]
        close_connection
      end

      def unbind
        p ['client unbind', @fd, @sockaddr]
      end
    end

    EM.start_server('127.0.0.1', 4000, TestServer)

    EM.connect('127.0.0.1', 4000, TestClient)
  end
end
