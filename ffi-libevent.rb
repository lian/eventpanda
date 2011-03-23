require 'ffi'

module EventPanda
  extend FFI::Library
  ffi_lib 'event'
  attach_function :event_init, [], :int
  attach_function :event_dispatch, [], :int
  attach_function :evbuffer_new, [], :pointer

  attach_function :evhttp_start, [:string, :int], :pointer
  callback :evhttp_callback, [:pointer, :pointer], :void
  attach_function :evhttp_set_gencb, [:pointer, :evhttp_callback, :pointer], :int

  attach_function :evbuffer_add_printf, [:pointer, :string], :int
  attach_function :evhttp_send_reply, [:pointer, :int, :string, :pointer], :int
  attach_function :evbuffer_free, [:pointer], :int


  attach_function :event_base_new, [], :pointer
  attach_function :event_base_free, [:pointer], :void
  attach_function :event_base_get_method, [:pointer], :string

  attach_function :event_base_dispatch, [:pointer], :int

  callback :callback, [:pointer, :pointer], :void
  attach_function :event_new, [:pointer, :int, :short, :callback], :pointer
  attach_function :event_add, [:pointer, :pointer], :int
  attach_function :event_assign, [:pointer, :pointer, :int, :int, :callback], :pointer

  attach_function :event_del, [:pointer], :int
  attach_function :event_free, [:pointer], :int

  EVLOOP_ONCE     = 1
  EVLOOP_NONBLOCK = 2
  EV_TIMEOUT = 1
  EV_READ = 2
  EV_PERSIST = 10
  attach_function :event_base_loop, [:pointer, :int], :int
end


module EventPanda

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
      super(interval, @fire, base || Thread.current[:ev_base])
    end
  end


  def self.run(&block)
    base = Thread.current[:ev_base] ||= EventPanda.event_base_new
    block.call if block; EventPanda.event_base_dispatch(base)
  end
end; EM = EventPanda


EM.run do
  t1 = EM::Timer.new(2){ p "foo" }
  t1.cancel

  i = 0
  t2 = EM::Timer.new(1){ p "baz"; t2.schedule! if (i+=1) < 3 }

  n = 0
  timer = EM::PeriodicTimer.new(1) do
    puts "the time is #{Time.now}"
    timer.cancel if (n+=1) > 2
  end
end


__END__
ev1, tv = nil, nil

cb_func = Proc.new{|*a| Event.event_add(ev1, tv); p ['callback', Time.now.tv_sec] }

base = Event.event_base_new
ev1 = Event.event_new(base, -1, 0, cb_func)

tv = FFI::MemoryPointer.new(:int, 2).put_array_of_int(0, [0, 10])
Event.event_add(ev1, tv)

Event.event_base_dispatch(base)
#10.times{ Event.event_base_loop(base, 2); sleep(1.2) }


__END__
p base = Event.event_base_new
p Event.event_base_get_method(base)

2.times{
  #p Event.event_base_loop(base, 2)

  p Event.event_base_loop(base, 0)
}

Event.event_base_free(base)

__END__
if $0 == __FILE__
  Event.event_init

  request_handler = Proc.new{|req, arg|
    buf = Event.evbuffer_new
    Event.evbuffer_add_printf(buf, "Thanks for the request!")
    Event.evhttp_send_reply(req, 200, "Client", buf)
    Event.evbuffer_free(buf)
  }

  http = Event.evhttp_start('127.0.0.1', 4500)
  Event.evhttp_set_gencb(http, request_handler, nil)

  Event.event_dispatch
end
