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

  # new connection
  attach_function :evconnlistener_get_base, [:pointer], :pointer
  attach_function :bufferevent_socket_new, [:pointer, :uint, :int], :pointer

  # connection callbacks
  callback :bev_data_cb,  [:pointer, :pointer], :void
  callback :bev_event_cb, [:pointer, :short, :pointer], :void
  attach_function :bufferevent_setcb, [:pointer, :bev_data_cb, :bev_data_cb, :bev_event_cb, :pointer], :void
  attach_function :bufferevent_enable, [:pointer, :short], :int
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


  # libevent_openssl requires a symbol from libevent_core.so. we load them as global so they see each other.
  def self.ffi_lib_global(*names)
    @ffi_lib_flags = FFI::DynamicLibrary::RTLD_LAZY | FFI::DynamicLibrary::RTLD_GLOBAL # instead of RTLD::LOCAL
    ffi_lib(*names)
  end
  ffi_lib_global 'event_core', 'event_openssl'
  attach_function :bufferevent_openssl_socket_new, [:pointer, :uint, :pointer, :uint, :uint], :pointer


  LEV_OPT_CLOSE_ON_FREE = 2
  LEV_OPT_REUSEABLE     = 8
  BEV_OPT_CLOSE_ON_FREE = 1
  EV_TIMEOUT = 1
  EV_READ = 2
  EV_WRITE = 4
  EV_PERSIST = 10


  def self.run(&block)
    base = Thread.current[:ev_base] ||= EventPanda.event_base_new
    block.call(base) if block
    EventPanda.event_base_dispatch(base)
    #loop{ Event.event_base_loop(base, 2); sleep(0.01) }
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
      cb = proc{ @callback.call; schedule! }
      super(interval, cb, base)
    end
  end

  def self.add_timer(i, &b); EventPanda::Timer.new(i, b); end
  def self.add_periodic_timer(i, &b); EventPanda::PeriodicTimer.new(i, b); end
end


module EventPanda

  class Connection
    def initialize(*args)
      #p args
    end

    def init_connection(fd, sockaddr, bev)
      @fd, @sockaddr, @bev = fd, sockaddr, bev
      init_bev if @bev
      self
    end

    def init_bev
      EventPanda.bufferevent_setcb(@bev, method(:read_cb), nil, method(:event_cb), nil)
      EventPanda.bufferevent_enable(@bev, EventPanda::EV_READ|EventPanda::EV_WRITE)

      @bev_input  = EventPanda.bufferevent_get_input(@bev)
      @bev_output = EventPanda.bufferevent_get_output(@bev)
      @bev_tmp    = FFI::MemoryPointer.new(:uint8, 4096 / 2)
    end

    def post_init; end

    def close_connection
      unbind; EventPanda.bufferevent_free(@bev)
    end

    def send_data(data)
      length = data.size
      #length = @bev_tmp.size if length > @bev_tmp.size
      EventPanda.bufferevent_write(@bev, @bev_tmp.put_string(0, data), length)
    end

    def read_cb(bev, ctx)
      length = EventPanda.evbuffer_get_length(@bev_input)
      #length = @bev_tmp.size if length > @bev_tmp.size
      EventPanda.bufferevent_read(@bev, @bev_tmp, length)
      receive_data(@bev_tmp.read_string(length))
    end

    def event_cb(bev, events, ctx)
      case events
        when 128 # connected (happens only with #connect or ssl)
          unless @use_ssl # with ssl dont run post_init again. accept_connection does this.
            @fd = EventPanda.bufferevent_getfd(@bev) # update fd ivar
            post_init
          end
          #init_ssl_for_connection if @use_ssl # post_init can set @use_ssl
        when 32  # ssl connection closed
          unbind
        when 17  # connection closed
          unbind
        else p ["unkown ssl event_cb", events]
      end
    end

    def start_tls(verify=false)
      raise 'implement start_tls'
    end
  end


  class TcpServer
    def initialize(base, host, port, klass, klass_args)
      @klass, @klass_args = klass, klass_args
      @host, @port = host, port

      sin = Socket.sockaddr_in(port.to_s, host.to_s)
      sin_ptr, sin_size = FFI::MemoryPointer.from_string(sin), sin.size

      _base = base || Thread.current[:ev_base]
      @listen = EventPanda.evconnlistener_new_bind(_base, method(:accept_connection), nil,
      EventPanda::LEV_OPT_CLOSE_ON_FREE|EventPanda::LEV_OPT_REUSEABLE, -1, sin_ptr, sin_size)
      EventPanda.evconnlistener_set_error_cb(@listen, method(:accept_error))
    end

    def accept_error(lisener, ctx)
      p "accept connection error"
      #EM.event_base_loopexit(base)
    end

    def accept_connection(listener, fd, sockaddr_ptr, socklen, ctx)
      sockaddr = Socket.unpack_sockaddr_in(sockaddr_ptr.get_array_of_uint8(0, socklen).pack("C*")).reverse
      p ["new connection", fd, sockaddr]

      base = EventPanda.evconnlistener_get_base(listener)
      bev  = EventPanda.bufferevent_socket_new(base, fd, EventPanda::BEV_OPT_CLOSE_ON_FREE)

      if !bev.null?
        conn = @klass.new(*@klass_args).init_connection(fd, sockaddr, bev)
        conn.post_init
        conn
      end
    end
  end

  def self.start_server(host, port, klass, *args)
    EventPanda::TcpServer.new(Thread.current[:ev_base], host, port, klass, args)
  end


  module SSL
    extend FFI::Library
    ffi_lib 'ssl'

    attach_function :SSL_library_init, [], :int
    attach_function :ERR_load_crypto_strings, [], :void
    attach_function :SSL_load_error_strings, [], :void
    attach_function :RAND_poll, [], :int
    attach_function :SSLv23_server_method, [], :pointer
    attach_function :SSL_CTX_new, [:pointer], :pointer
    attach_function :SSL_new, [:pointer], :pointer
    attach_function :SSL_use_certificate_file, [:pointer, :string, :int], :int
    attach_function :SSL_use_PrivateKey_file, [:pointer, :string, :int], :int

    SSL_FILETYPE_PEM = 1
    SSL_VERIFY_NONE = 0
    SSL_VERIFY_PEER = 1
    SSL_VERIFY_FAIL_IF_NO_PEER_CERT = 2

    def self.init
      return if Thread.current[:ssl_ctx]
      SSL.SSL_library_init
      SSL.ERR_load_crypto_strings
      SSL.SSL_load_error_strings
      #p SSL.OpenSSL_add_all_algorithms
      SSL.RAND_poll

      Thread.current[:ssl_ctx] = SSL.SSL_CTX_new(SSL.SSLv23_server_method)
    end

    def self.get_ctx; Thread.current[:ssl_ctx] ||= (init; SSL_CTX_new(SSLv23_server_method())); end
  end

  BUFFEREVENT_SSL_ACCEPTING = 2
  BEV_OPT_DEFER_CALLBACKS = 4

  class TcpServer_SSL < TcpServer
    def accept_connection(listener, fd, sockaddr_ptr, socklen, ctx)
      sockaddr = Socket.unpack_sockaddr_in(sockaddr_ptr.get_array_of_uint8(0, socklen).pack("C*")).reverse
      p ["new ssl connection", fd, sockaddr]

      base = EventPanda.evconnlistener_get_base(listener)

      ssl = SSL.SSL_new(EventPanda::SSL.get_ctx)
      raise "ssl error (SSL_new pointer is null)" if ssl.null?

      SSL.SSL_use_certificate_file(ssl, "client.crt", SSL::SSL_FILETYPE_PEM)
      SSL.SSL_use_PrivateKey_file(ssl, "client.key", SSL::SSL_FILETYPE_PEM)

      bev = EventPanda.bufferevent_openssl_socket_new(Thread.current[:ev_base], fd, ssl,
        EventPanda::BUFFEREVENT_SSL_ACCEPTING, EventPanda::BEV_OPT_CLOSE_ON_FREE|EventPanda::BEV_OPT_DEFER_CALLBACKS)

      if !bev.null?
        conn = @klass.new(*@klass_args).init_connection(fd, sockaddr, bev)
        conn.post_init
        conn.instance_eval{ @use_ssl = true }
        conn
      end
    end
  end


  def self.start_server_ssl(host, port, klass, *args)
    EventPanda::TcpServer_SSL.new(Thread.current[:ev_base], host, port, klass, args)
  end


  class TcpConnection
    def self.create(base, host, port, klass, klass_args)
      sin = Socket.sockaddr_in(port.to_s, host.to_s)
      sin_ptr, sin_size = FFI::MemoryPointer.from_string(sin), sin.size
      _base = base || Thread.current[:ev_base]

      bev = EventPanda.bufferevent_socket_new(_base, -1, EventPanda::BEV_OPT_CLOSE_ON_FREE)

      if !bev.null?
        conn = klass.new(*klass_args).init_connection(-1, [host, port], bev)
        EventPanda.bufferevent_socket_connect(bev, sin_ptr, sin_size)
      end
    end
  end

  def self.connect(host, port, klass, *args)
    EventPanda::TcpConnection.create(Thread.current[:ev_base], host, port, klass, args)
  end

  def self.stop(base=nil, interval=nil)
    EventPanda.event_base_loopexit(base || Thread.current[:ev_base], nil)
  end
end


if $0 == __FILE__
  EM.run do

    timer = EM::PeriodicTimer.new(1){  p [Time.now.tv_sec] }


    # place a client.crt and client.key files inside your directory and run eventpanda.rb
    # then try to connect with % openssl s_client -connect localhost:4000
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
      end
    end

    EM.start_server_ssl("127.0.0.1", 4000, TestServer)
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
