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
