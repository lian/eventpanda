# tries to implement lib/eventmachine.rb main API
module EventPanda

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

  def self.cancel_timer(t)
    t.respond_to?(:cancel) && t.cancel
  end

  def self.add_shutdown_hook(&block); @tails << block; end

  def self.stop_event_loop
    @reactor_running = false
    Libevent.event_base_loopbreak(Thread.current[:ev_base])
  end

  def self.initialize_event_loop
    Thread.current[:ev_base] ||= Libevent.event_base_new
  end

  def self.run_event_loop
    while @reactor_running
      Libevent.event_base_loop(Thread.current[:ev_base], 0)
    end; true
  end

  def self.release_event_loop
    base = Thread.current[:ev_base]
    Thread.current[:ev_base] = nil
    Libevent.event_base_free(base)
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
        initialize_event_loop

        (b = blk || block) and add_timer(0, b)
        if @next_tick_queue && !@next_tick_queue.empty?
          add_timer(0){ signal_loopbreak }
        end

        @reactor_thread = Thread.current
        run_event_loop

      ensure # cleanup
        @tails.pop.call until @tails.empty?

        begin
          release_event_loop
        ensure
          release_event_loop_threadpool
          @next_tick_queue = []
        end
        @reactor_running, @reactor_thread = false, nil
      end

      raise @wrapped_exception if @wrapped_exception
    end; true
  end


  # loopback-signalled event.
  def self.signal_loopbreak # :nodoc:
    run_deferred_callbacks
  end


  # caller must ensure it is thread-safe.
  def self.defer(op = nil, callback = nil, &blk)
    unless @threadpool; require 'thread'
      @threadpool, @threadqueue, @resultqueue = [], ::Queue.new, ::Queue.new
      spawn_threadpool
    end
    @threadqueue << [op||blk, callback]
  end


  @threadpool_size = 10

  def self.spawn_threadpool # :nodoc:
    until @threadpool.size == @threadpool_size.to_i
      @threadpool << Thread.new do
        Thread.current.abort_on_exception = true
        while true
          op, cb = *@threadqueue.pop
          @resultqueue << [op.call, cb]
          EventPanda.signal_loopbreak
        end
      end
    end
  end

  def self.release_event_loop_threadpool
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

  # called by running code from #defer or #next_tick
  def self.run_deferred_callbacks # :nodoc:
    @resultqueue && until @resultqueue.empty?
      result, cb = @resultqueue.pop
      cb && cb.call(result)
    end

    @next_tick_mutex.synchronize{
      jobs, @next_tick_queue = @next_tick_queue, []; jobs
    }.each{|j| j.call }
  end
end
