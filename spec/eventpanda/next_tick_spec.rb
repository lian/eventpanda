require_relative 'spec_helper.rb'

require 'eventpanda'

describe 'EventPanda#next_tick' do

  it "tick arg" do
    t = nil

    pr = proc { t = true; EM.stop }
    EM.run {
      EM.next_tick(pr)
    }

    t.should == true
  end

  it "tick block" do
    t = nil

    EM.run {
      EM.next_tick{ t = true; EM.stop }
    }

    t.should == true
  end

  it 'pre run queue' do
    x = false
    EM.next_tick{ EM.stop; x = true }
    EM.run{ EM.add_timer(0.01){ EM.stop } }
    x.should == true
  end

  it 'cleanup after stop' do
    x = true
    EM.run{
      EM.next_tick{
        EM.stop
        EM.next_tick{ x=false }
      }
    }
    EM.run{
      EM.next_tick{ EM.stop }
    }
    x.should == true
  end

  it 'run run 2' do
    t = nil
    a = proc{ EM.stop }
    b = proc{ t = true }
    EM.run(a, b)
    t.should == true
  end

  it 'run run 3' do
    a = []
    EM.run{
      EM.run(proc{EM.stop}, proc{a << 2})
      a << 1
    }
    a.should == [1,2]
  end


  it 'schedule on reactor thread' do
    x = false
    EM.run{
      EM.schedule{ x = true }
      EM.stop
    }
    x.should == true
  end

  it 'schedule from thread' do
    x = false
    EM.run do
      Thread.new{ EM.schedule{ x = true } }.join
      #x.should == false # FIXME
      EM.next_tick{ EM.stop }
    end
    x.should == true
  end

end
