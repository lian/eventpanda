module EventPanda

  class << self
    attr_reader :threadpool # :nodoc:
    attr_accessor :threadpool_size
    EventPanda.threadpool_size = 20
  end
  @threadpool = nil


  # note, caller needs to make sure its thread-safe
  def self.defer(op = nil, callback = nil, &blk)
    unless @threadpool
      require 'thread'
      @threadpool, @threadqueue, @resultqueue = [], ::Queue.new, ::Queue.new
      spawn_threadpool
    end

    @threadqueue << [op||blk,callback]
  end

  def self.spawn_threadpool # :nodoc:
    until @threadpool.size == @threadpool_size.to_i
      thread = Thread.new do
        Thread.current.abort_on_exception = true
        while true
          op, cback = *@threadqueue.pop
          result = op.call
          @resultqueue << [result, cback]
          EventPanda.signal_loopbreak
        end
      end
      @threadpool << thread
    end
  end


  # loopback-signalled event.
  #def self.signal_loopbreak
  #  # TODO
  #end

  #--
  # The is the responder for the loopback-signalled event.
  # It can be fired either by code running on a separate thread (EM#defer) or on
  # the main thread (EM#next_tick).
  # It will often happen that a next_tick handler will reschedule itself. We
  # consume a copy of the tick queue so that tick events scheduled by tick events
  # have to wait for the next pass through the reactor core.
  #
  def self.run_deferred_callbacks # :nodoc:
    until (@resultqueue ||= []).empty?
      result,cback = @resultqueue.pop
      cback.call result if cback
    end

    @next_tick_mutex.synchronize do
      jobs, @next_tick_queue = @next_tick_queue, []; jobs
    end.each{|j| j.call }
  end

end
