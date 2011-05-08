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

  def self.add_timer(i, cb=nil, &b); EventPanda::Timer.new(i, cb || b); end
  def self.add_periodic_timer(i, cb=nil, &b); EventPanda::PeriodicTimer.new(i, cb || b); end
end
