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
      EventPanda.bufferevent_free(@bev); unbind
      @free_cb && @free_cb.call(self)
    end

    def send_data(data)
      length = data.size
      (length = @bev_tmp.size; chunk = true) if length > @bev_tmp.size
      EventPanda.bufferevent_write(@bev, @bev_tmp.put_string(0, data), length)
      send_data(data[length..-1]) if chunk
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
  end

  module Connection_Pipe_Methods
    def close_connection
      unbind
      @pipe_socket.closed? || @pipe_socket.close
      @free_cb && @free_cb.call(self)
    end

    def socket; @pipe_socket; end

    def get_status; @_unbind_process_status; end

    def alive?
      !(@_unbind_process_status = @pipe.get_process_status)
    end

    def send_data(data)
      @pipe_socket.write(data)
    end
  end



  # EventPanda::Connection Base
  class Connection
    def init_connection(fd, sockaddr, bev, free_cb=nil)
      @free_cb = free_cb

      if sockaddr
        extend Connection_BEV_Methods # libevent using bufferevent.

        @fd, @sockaddr, @bev = fd, sockaddr, bev
        init_bev if @bev

      else # is a pipe (bev == PipeDescriptor)
        extend Connection_Pipe_Methods

        @sockaddr = []
        @fd, @pipe_socket, @pipe = bev.socket.fileno, bev.socket, bev
        post_init
      end

      self
    end

    def initialize(*args); end
    def post_init; end
    def receive_data(data); end
    def unbind; end

    # autoloads SSL methods
    def method_missing(*a) # :nodoc:
      (a.first == :start_tls) ? \
      (extend EventPanda::SSL::ConnectionMethods; send(*a)) : super(*a)
    end

  end # Connection

  autoload :SSL, File.expand_path( File.join(File.dirname(__FILE__), 'ssl') )

end # EventPanda
