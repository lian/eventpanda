require_relative 'spec_helper.rb'

require 'eventpanda'

describe 'EventPanda Timers' do

  it 'timer with block' do
    x = false
    EM.run {
      EM::Timer.new(0){
        x = true
        EM.stop
      }
    }
    x.should == true
  end

  it 'timer with proc' do
    x = false
    EM.run {
      EM::Timer.new(0, proc {
        x = true
        EM.stop
      })
    }
    x.should == true
  end

  it 'timer cancel' do
    proc{
      EM.run {
        timer = EM::Timer.new(0.01) { flunk "Timer was not cancelled." }
        timer.cancel

        EM.add_timer(0.02) { EM.stop }
      }
    }.should.not.raise NoMethodError
  end

  it 'periodic timer' do
    x = 0
    EM.run {
      EM::PeriodicTimer.new(0.01) do
        x += 1
        EM.stop if x == 4
      end
    }
    x.should ==  4
  end

  it 'add_periodic_timer' do
    x = 0
    EM.run {
      t = EM.add_periodic_timer(0.01) do
        x += 1
        EM.stop  if x == 4
      end
      t.respond_to?(:cancel).should == true
    }
    x.should == 4
  end

  it 'periodic timer cancel' do
    x = 0
    EM.run{
      pt = EM::PeriodicTimer.new(0.01){ x += 1 }
      pt.cancel
      EM::Timer.new(0.02){ EM.stop }
    }
    x.should == 0
  end


  it 'add_periodic_timer cancel' do
    x = 0
    EM.run{
      pt = EM.add_periodic_timer(0.01){ x += 1 }
      EM.cancel_timer(pt)
      EM.add_timer(0.02){ EM.stop }
    }
    x.should == 0
  end

  it 'periodic timer self cancel' do
    x = 0
    EM.run{
      pt = EM::PeriodicTimer.new(0){
        x += 1
        if x == 4
          pt.cancel
          EM.stop
        end
      }
    }
    x.should ==  4
  end

  # test_timer_change_max_outstanding

end
