module EventPanda

=begin
  # figure how to implement #schedule and #next_tick right. works for now.
  def self.schedule(&b);  EventPanda::Timer.new(0, b); end
  def self.next_tick(&b); EventPanda::Timer.new(0, b); end


  # Utility method for coercing arguments to an object that responds to #call
  # Accepts an object and a method name to send to, or a block, or an object
  # that responds to call.
  #
  #  cb = EM.Callback{ |msg| puts(msg) }
  #  cb.call('hello world')
  #
  #  cb = EM.Callback(Object, :puts)
  #  cb.call('hello world')
  #
  #  cb = EM.Callback(proc{ |msg| puts(msg) })
  #  cb.call('hello world')
  #
  def self.Callback(object = nil, method = nil, &blk)
    if object && method
      lambda { |*args| object.send method, *args }
    else
      object.respond_to?(:call) ? object : (blk || raise(ArgumentError))
    end
  end
=end


  # A cross thread, reactor scheduled, linear queue.
  #
  # This class provides a simple "Queue" like abstraction on top of the reactor
  # scheduler. It services two primary purposes:
  # * API sugar for stateful protocols
  # * Pushing processing onto the same thread as the reactor
  #
  #  q = EM::Queue.new
  #  q.push('one', 'two', 'three')
  #  3.times do
  #    q.pop{ |msg| puts(msg) }
  #  end
  #
  class Queue
    # Create a new queue
    def initialize
      @items = []
      @popq  = []
    end

    # Pop items off the queue, running the block on the reactor thread. The pop
    # will not happen immediately, but at some point in the future, either in 
    # the next tick, if the queue has data, or when the queue is populated.
    def pop(*a, &b)
      cb = EM::Callback(*a, &b)
      EM.schedule do
        if @items.empty?
          @popq << cb
        else
          cb.call @items.shift
        end
      end
      nil # Always returns nil
    end

    # Push items onto the queue in the reactor thread. The items will not appear
    # in the queue immediately, but will be scheduled for addition during the 
    # next reactor tick.
    def push(*items)
      EM.schedule do
        @items.push(*items)
        @popq.shift.call @items.shift until @items.empty? || @popq.empty?
      end
    end
    alias :<< :push


    # N.B. This is a peek, it's not thread safe, and may only tend toward 
    # accuracy.
    def empty?
      @items.empty?
    end

    # N.B. This is a peek, it's not thread safe, and may only tend toward 
    # accuracy.
    def size
      @items.size
    end
  end # Queue



  # Provides a simple interface to push items to a number of subscribers. The
  # channel will schedule all operations on the main reactor thread for thread
  # safe reactor operations.
  #
  # This provides a convenient way for connections to consume messages from 
  # long running code in defer, without threading issues.
  #
  #  channel = EM::Channel.new
  #  sid = channel.subscribe{ |msg| p [:got, msg] }
  #  channel.push('hello world')
  #  channel.unsubscribe(sid)
  #
  class Channel
    # Create a new channel
    def initialize
      @subs = {}
      @uid = 0
    end

    # Takes any arguments suitable for EM::Callback() and returns a subscriber
    # id for use when unsubscribing.
    def subscribe(*a, &b)
      name = gen_id
      EM.schedule { @subs[name] = EM::Callback(*a, &b) }
      name
    end

    # Removes this subscriber from the list.
    def unsubscribe(name)
      #EM.schedule { @subs.delete name }
      EM.add_timer(1) { @subs.delete name }
    end

    # Add items to the channel, which are pushed out to all subscribers.
    def push(*items)
      items = items.dup
      EM.schedule { @subs.values.each { |s| items.each { |i| s.call i } } }
    end
    alias << push

    # Receive exactly one message from the channel.
    def pop(*a, &b)
      #EM.schedule {
        name = subscribe do |*args|
          #unsubscribe(name)
          @subs.delete name # instead of #unsubscribe
          EM::Callback(*a, &b).call(*args)
        end
      #}
    end

    private
    def gen_id # :nodoc:
      @uid += 1
    end
  end # Channel

end
