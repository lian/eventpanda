module EventPanda

  # caller must ensure it is thread-safe.
  def self.defer(op = nil, callback = nil, &blk)
    unless @threadpool; require 'thread'
      @threadpool, @threadqueue, @resultqueue = [], ::Queue.new, ::Queue.new
      spawn_threadpool
    end
    @threadqueue << [op||blk, callback]
  end


  class << self
    attr_reader   :threadpool
    attr_accessor :threadpool_size
    threadpool_size = 10
  end
  @threadpool = nil

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
