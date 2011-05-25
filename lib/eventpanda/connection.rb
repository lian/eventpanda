module EventPanda

  module Connection_BEV_Methods
    def init_bev
      EventPanda.bufferevent_setcb(@bev,
        @_data_cb = method(:_data_cb), nil, @_event_cb = method(:_event_cb), nil)
      EventPanda.bufferevent_enable(@bev, EventPanda::EV_READ|EventPanda::EV_WRITE)

      @bev_input  = EventPanda.bufferevent_get_input(@bev)
      #@bev_output = EventPanda.bufferevent_get_output(@bev)
      @bev_tmp    = FFI::MemoryPointer.new(:uint8, 4096)
    end

    def close_connection
      @__closed ? (return nil) : @__closed=true
      EventPanda.bufferevent_free(@bev)
      unbind
      @__free_cb && @__free_cb.call(self)
    end

    def send_data(data)
      length = data.size
      (length = @bev_tmp.size; chunk = true) if length > @bev_tmp.size
      EventPanda.bufferevent_write(@bev, @bev_tmp.put_string(0, data), length)

      if chunk
        send_data(data[length..-1])
      else
        close_connection if @close_after_writing
      end
    end

    def _data_cb(bev, ctx)
      length = EventPanda.evbuffer_get_length(@bev_input)
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
          # unbind
          close_connection
        when 33  # ?
          p ["event_cb", events]
          # close_connection
        when 17  # connection closed
          # unbind
          close_connection
        else
          p ["unkown event_cb", events]
          #close_connection
      end
    end

    def __init_module(fd, sockaddr, bev, free_cb=nil)
      @fd, @sockaddr, @bev = fd, sockaddr, bev
      @__free_cb = free_cb
      init_bev if @bev
    end
  end

  module Connection_Pipe_Methods
    def close_connection
      unbind
      @__socket.closed? || @__socket.close
      @__free_cb && @__free_cb.call(@__socket)
    end

    def socket; @__socket; end
    def get_status; @__subprocess_status; end

    def alive?
      !(@__subprocess_status = @__socket.get_subprocess_status)
    end

    def on_subprocess_exit(status)
      @__subprocess_status = status
      close_connection
    end

    def send_data(data)
      @__socket.write(data)
    end

    def __init_module(fd, sockaddr, bev, free_cb=nil)
      @__socket  = bev
      @__free_cb = free_cb
      @sockaddr  = ""
      post_init
    end
  end



  # EventPanda::Connection Base
  class Connection
    def init_connection(fd, sockaddr, bev, free_cb=nil)
      if sockaddr
        # libevent using bufferevent.
        extend Connection_BEV_Methods
        __init_module(fd, sockaddr, bev, free_cb)
      else
        # bev == ::Socket with PipeHelperMethods Module
        extend Connection_Pipe_Methods
        __init_module(fd, sockaddr, bev, free_cb)
      end
      self
    end

    def initialize(*args); end
    def post_init; end
    def receive_data(data); end
    def unbind; end

    def get_peername; @sockaddr; end
    def close_connection_after_writing; @close_after_writing = true; end

    def comm_inactivity_timeout
      # TODO
    end

    def comm_inactivity_timeout= value
      # TODO
    end

    def method_missing(*a) # :nodoc:
      # autoload ssl methods
      (a.first == :start_tls) ? \
      (extend EventPanda::SSL::ConnectionMethods; send(*a)) : super(*a)
    end
  end # Connection


  autoload :SSL, File.expand_path( File.join(File.dirname(__FILE__), 'ssl') )

end # EventPanda
