require_relative 'spec_helper.rb'

require 'eventpanda'

describe 'EventPanda basic specs' do

  it "run and stop" do
    EM.run{ }.should == true
    EM.run{ EM.stop }.should == true
  end

  it "run and gc" do
    EM.run{ GC.start; EM.stop }.should == true
  end


  it "run and gc server" do
    EM.run{
      EM.start_server('127.0.0.1', 4045, EM::Connection)
      EM.start_server('127.0.0.1', 4046, EM::Connection)

      GC.start

      EM.add_timer(1){ EM.stop }

      GC.start
    }.should == true
  end


  it "run and gc - 1" do
    EM.run{
      EM.connect('127.0.0.1', 4045, EM::Connection)

      EM.add_timer(1){ EM.stop }
    }.should == true
  end


  it "run and gc - 2" do
    EM.run{
      EM.add_timer(2){ EM.stop }

      GC.start

      EM.connect('127.0.0.1', 4045, EM::Connection)

    }.should == true
  end

  it "run and gc - 3" do
    count = 0

    EM.run{
      EM.add_timer(2){ GC.start; EM.stop }

      GC.start

      200.times{
        count += 1
        EM.connect('127.0.0.1', 4045, EM::Connection)
      }

      #p ['pid', Process.pid]; gets.chomp
    }

    count.should == 200
  end

end
