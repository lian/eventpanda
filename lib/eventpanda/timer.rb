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
      sec, msec = interval.divmod(1.0); msec = (msec*1000).to_i
      @block = callback || block
      @signature = Libevent.event_new(base || Thread.current[:ev_base], -1, 0, @block)
      @tv = FFI::MemoryPointer.new(:int, 2).put_array_of_int(0, [sec, msec])
      schedule!
    end

    def schedule!
      Libevent.event_add(@signature, @tv) if @signature
    end

    def cancel
      Libevent.event_free(@signature)
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

  def self.add_timer(i, cb=nil, &b); Timer.new(i, cb || b); end
  def self.add_periodic_timer(i, cb=nil, &b); PeriodicTimer.new(i, cb || b); end
end
