require 'ffi'
require 'socket'

module EventPanda
  extend FFI::Library
  ffi_lib 'event'

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

  # evhttp
  #   request_handler = Proc.new{|req, arg|
  #     buf = Event.evbuffer_new
  #     Event.evbuffer_add_printf(buf, "Thanks for the request!")
  #     Event.evhttp_send_reply(req, 200, "Client", buf)
  #     Event.evbuffer_free(buf)
  #   }
  #   http = Event.evhttp_start('127.0.0.1', 8000)
  #   Event.evhttp_set_gencb(http, request_handler, nil)
  attach_function :evhttp_start, [:string, :int], :pointer
  callback :evhttp_callback, [:pointer, :pointer], :void
  attach_function :evhttp_set_gencb, [:pointer, :evhttp_callback, :pointer], :int
  attach_function :evhttp_send_reply, [:pointer, :int, :string, :pointer], :int


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
      @signature = EventPanda.event_new(base || Thread.current[:ev_base], -1, 0, callback || block)
      @tv = FFI::MemoryPointer.new(:int, 2).put_array_of_int(0, [interval || 0, 0])
      schedule!
    end

    def schedule!
      EventPanda.event_add(@signature, @tv) if @signature
    end

    def cancel
      #EventPanda.event_del(@signature)
      EventPanda.event_free(@signature)
      s = @signature.dup; @signature = nil; s
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
      @fire = proc{ @callback.call; schedule! }
      super(interval, @fire, base)
    end
  end

  def self.add_timer(i, &b); EventPanda::Timer.new(i, b); end
  def self.add_periodic_timer(i, &b); EventPanda::PeriodicTimer.new(i, b); end
end


module EventPanda # tcp server

  def self.start_server(host, port, klass, *args)
    base = Thread.current[:ev_base]

    read_cb_copy = Proc.new{|bev, ctx|
      #p "receive_data (copy)"
      input = EM.bufferevent_get_input(bev)
      output = EM.bufferevent_get_output(bev)

      EM.evbuffer_add_printf(output, "echo:\n")
      EM.evbuffer_add_buffer(output, input)
    }

    read_cb_line = Proc.new{|bev, ctx|
      #p "receive_data (line)"
      input = EM.bufferevent_get_input(bev)
      output = EM.bufferevent_get_output(bev)

      while line = EM.evbuffer_readline(input)
        p [Time.now.tv_sec, line]
        EM.evbuffer_add_printf(output, "echo:\n")
        EM.evbuffer_add_printf(output, line + "\n")
      end
    }

    event_cb = Proc.new{|bev, events, ctx| p "bev_event_cb" }


    accept_error_cb = Proc.new{|listener, ctx|
      p "accept connection error"
      EM.event_base_loopexit(base)
    }

    accept_conn_cb = Proc.new{|listener, fd, sockaddr_ptr, socklen, ctx|
      sockaddr = Socket.unpack_sockaddr_in(sockaddr_ptr.get_array_of_uint8(0, socklen).pack("C*")).reverse
      p ["new connection", sockaddr, fd]

      base = EM.evconnlistener_get_base(listener)
      bev = EM.bufferevent_socket_new(base, fd, EM::BEV_OPT_CLOSE_ON_FREE)

      EM.bufferevent_setcb(bev, read_cb_line, nil, event_cb, nil);
      EM.bufferevent_enable(bev, EM::EV_READ|EM::EV_WRITE)
    }


    sin = Socket.sockaddr_in(port.to_s, host.to_s)
    sin_ptr, sin_size = FFI::MemoryPointer.from_string(sin), sin.size

    listener = EM.evconnlistener_new_bind(base, accept_conn_cb, nil,
      EM::LEV_OPT_CLOSE_ON_FREE|EM::LEV_OPT_REUSEABLE, -1, sin_ptr, sin_size)
    EM.evconnlistener_set_error_cb(listener, accept_error_cb)

    listener
  end
end


module FFI::OpenSSL
  extend FFI::Library
  ffi_lib 'ssl'

  attach_function :SSL_library_init, [], :int
  attach_function :ERR_load_crypto_strings, [], :void
  attach_function :SSL_load_error_strings, [], :void
  #attach_function :OpenSSL_add_all_algorithms, [], :int
  attach_function :RAND_poll, [], :int
  attach_function :SSLv23_server_method, [], :pointer
  attach_function :SSL_CTX_new, [:pointer], :pointer
  attach_function :SSL_CTX_use_certificate_file, [:pointer, :string, :int], :int
  attach_function :SSL_CTX_use_PrivateKey_file, [:pointer, :string, :int], :int
  attach_function :SSL_CTX_set_verify, [:pointer, :uint, :pointer], :void
  callback        :SSLX_CTX_verify_callback, [:pointer, :pointer], :void
  attach_function :SSL_CTX_set_cert_verify_callback, [:pointer, :SSLX_CTX_verify_callback, :pointer], :void

  SSL_FILETYPE_PEM = 1
  SSL_VERIFY_NONE = 0
  SSL_VERIFY_PEER = 1
  SSL_VERIFY_FAIL_IF_NO_PEER_CERT = 2

  def self.init
    FFI::OpenSSL.SSL_library_init
    FFI::OpenSSL.ERR_load_crypto_strings
    FFI::OpenSSL.SSL_load_error_strings
    #p FFI::OpenSSL.OpenSSL_add_all_algorithms
    FFI::OpenSSL.RAND_poll

    p sctx = FFI::OpenSSL.SSL_CTX_new(FFI::OpenSSL.SSLv23_server_method)

    p FFI::OpenSSL.SSL_CTX_use_certificate_file(sctx, "crt.pem", FFI::OpenSSL::SSL_FILETYPE_PEM)
    p FFI::OpenSSL.SSL_CTX_use_PrivateKey_file(sctx, "pvk.pem", FFI::OpenSSL::SSL_FILETYPE_PEM)

    #FFI::OpenSSL.SSL_CTX_set_verify(sctx, FFI::OpenSSL::SSL_VERIFY_NONE, nil)
    FFI::OpenSSL.SSL_CTX_set_verify(sctx, FFI::OpenSSL::SSL_VERIFY_PEER|FFI::OpenSSL::SSL_VERIFY_FAIL_IF_NO_PEER_CERT, nil)

    verify_callback = Proc.new{|x509_ctx, arg| p ['verify callback'] }
    FFI::OpenSSL.SSL_CTX_set_cert_verify_callback(sctx, verify_callback, nil)
    true
  end
end




if $0 == __FILE__
  EM.run do

    timer = EM::PeriodicTimer.new(3){  p [Time.now.tv_sec] }

    class C
      def receive_data(data)
      end
    end

    EM.start_server('127.0.0.1', 4000, C)

  end
end
