module EventPanda

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


module EventPanda
  module Deferrable

    def callback(&block)
      return unless block
      if @deferred_status == :succeeded
        block.call(*@deferred_args)
      elsif @deferred_status != :failed
        (@callbacks ||= []).unshift(block)
      end; self
    end

    def errback(&block)
      return unless block
      if @deferred_status == :failed
        block.call(*@deferred_args)
      elsif @deferred_status != :succeeded
        (@errbacks ||= []).unshift(block)
      end; self
    end

    def cancel_callback(block)
      (@callbacks ||= []).delete(block)
    end

    def cancel_errback(block)
      (@errbacks ||= []).delete(block)
    end

    def set_deferred_status(status, *args)
      @deferred_args = args
      cancel_timeout
      case @deferred_status = status
      when :succeeded
        while cb = @callbacks.pop
          cb.call(*@deferred_args)
        end if @callbacks
        @errbacks.clear if @errbacks
      when :failed
        while eb = @errbacks.pop
          eb.call(*@deferred_args)
        end if @errbacks
        @callbacks.clear if @callbacks
      end
    end

    def timeout(seconds, *args)
      cancel_timeout; me = self
      @__timeout = EM.add_timer(seconds){ me.fail(*args) }; self
    end

    def cancel_timeout
      (@__timeout ||= nil) && (@__timeout.cancel; @__timeout=nil)
    end

    def succeed(*args); set_deferred_status(:succeeded, *args); end
    def fail(*args);    set_deferred_status :failed, *args;     end

    alias set_deferred_success succeed
    alias set_deferred_failure fail
  end

  class DefaultDeferrable
    include Deferrable
  end
end
