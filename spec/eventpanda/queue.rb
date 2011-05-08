require_relative 'spec_helper.rb'

require 'eventpanda'
require 'eventpanda/queue'

describe 'EventPanda::Queue' do

  it "push" do
    s = 0
    EM.run{
      q = EM::Queue.new
      q.push(:foo)
      q.push(:baz)
      EM.next_tick{ s = q.size; EM.stop }
    }
    s.should == 2
  end

  it "pop" do
    x,y,z = nil
    EM.run do
      q = EM::Queue.new
      q.push(1,2,3)
      q.pop { |v| x = v }
      q.pop { |v| y = v }
      q.pop { |v| z = v; EM.stop }
    end
    x.should == 1
    y.should == 2
    z.should == 3
  end

  it 'thread push and pop' do
    q = EM::Queue.new

    Thread.new { q.push(1,2,3) }.join
    q.empty?.should == true

    EM.run { EM.next_tick { EM.stop } }
    q.size.should == 3

    x = nil
    Thread.new { q.pop { |v| x = v } }.join
    x.should == nil
    EM.run { EM.next_tick { EM.stop } }
    x.should == 1
  end

end


describe 'EventPanda::Channel' do

  it 'subscribe' do
    s = 0
    EM.run do
      c = EM::Channel.new
      c.subscribe { |v| s = v; EM.stop }
      c << 1
    end
    s.should == 1
  end

  it 'unsubscribe' do
    s = 0
    EM.run do
      c = EM::Channel.new
      subscription = c.subscribe { |v| s = v }
      c.unsubscribe(subscription)
      c << 1
      EM.next_tick { EM.stop }
    end
    s.should == 1 # shouldn't this be zero? if so change #unsubscribe back.
  end

  it 'pop' do
    s = 0
    EM.run do
      c = EM::Channel.new
      c.pop{ |v| s = v }
      c << 1
      c << 2
      EM.next_tick { EM.stop }
    end
    s.should == 1
  end

  it 'thread push' do
    out = []
    c = EM::Channel.new
    c.subscribe { |v| out << v }
    Thread.new { c.push(1,2,3) }.join
    out.empty?.should == true

    EM.run { EM.next_tick { EM.stop } }

    out.should == [1,2,3]
  end

  it 'thread callback' do
    out = []
    c = EM::Channel.new
    Thread.new { c.subscribe { |v| out << v } }.join
    c.push(1,2,3)
    out.empty?.should == true

    EM.run { EM.next_tick { EM.stop } }

    out.should == [1,2,3]
  end

end
