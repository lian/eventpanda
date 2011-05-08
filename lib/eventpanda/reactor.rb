# tries to implement lib/eventmachine.rb main API
module EventPanda

  class << self
    attr_reader :reactor_thread
  end

  @next_tick_mutex = Mutex.new
  @reactor_running = false
  @next_tick_queue = []
  @tails = []

  def self.reactor_running?; (@reactor_running || false); end
  def self.reactor_thread?; Thread.current == @reactor_thread; end

  def self.Callback(object = nil, method = nil, &blk)
    if object && method
      lambda{|*args| object.send(method, *args) }
    else
      object.respond_to?(:call) ? object : (blk || raise(ArgumentError))
    end
  end

  def self.next_tick(pr=nil, &block)
    raise ArgumentError, "no proc or block given" unless ((pr && pr.respond_to?(:call)) or block)
    @next_tick_mutex.synchronize{ @next_tick_queue << (pr || block) }
    signal_loopbreak if reactor_running?
  end

  def self.schedule(*a, &b)
    cb = Callback(*a, &b)
    (reactor_running? && reactor_thread?) ? cb.call : next_tick{ cb.call }
  end

  def self.add_shutdown_hook(&block); @tails << block; end
  def self.stop_event_loop; EventPanda.stop; end



  def self.initialize_event_machine
    Thread.current[:ev_base] ||= EventPanda.event_base_new
  end

  def self.run_machine
    EventPanda.event_base_loop(Thread.current[:ev_base], 0)
    true
  end

  def self.release_machine
    base = Thread.current[:ev_base]
    Thread.current[:ev_base] = nil
    EventPanda.event_base_free(base)
    base = nil; true
  end


  def self.run(blk=nil, tail=nil, &block)
    tail and @tails.unshift(tail)

    if reactor_running?
      (b = blk || block) and b.call # next_tick(b)
    else
      @conns, @acceptors, @timers = {}, {}, {}
      @wrapped_exception = nil
      @next_tick_queue ||= []; @tails ||= []

      begin # run loop
        @reactor_running = true
        initialize_event_machine

        (b = blk || block) and add_timer(0, b)
        if @next_tick_queue && !@next_tick_queue.empty?
          add_timer(0){ signal_loopbreak }
        end

        @reactor_thread = Thread.current
        run_machine

      ensure # cleanup
        @tails.pop.call until @tails.empty?

        begin
          release_machine
        ensure
          release_machine_threadpool
          @next_tick_queue = []
        end
        @reactor_running, @reactor_thread = false, nil
      end

      raise @wrapped_exception if @wrapped_exception
    end; true
  end

  def self.release_machine_threadpool
    if @threadpool
      @threadpool.each{|t| t.exit }
      @threadpool.each do |t|
        next unless t.alive?
        begin
          t.kill! # no kill! on 1.9 or rbx, and raises NotImplemented on jruby
        rescue NoMethodError, NotImplementedError
          t.kill # XXX t.join here?
        end
      end
      @threadqueue, @resultqueue, @threadpool = nil, nil, nil
    end
  end

  # loopback-signalled event.
  def self.signal_loopbreak # :nodoc:
    run_deferred_callbacks
  end

  def self.run_deferred_callbacks # :nodoc:
    # defer.rb implements this method.
  end

end

require 'eventpanda/defer.rb'
