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


  it "run simple client <-> server" do
    count = 0

    EM.run{
      #EM.add_timer(2){ GC.start }; #EM.stop }

      class Server < EM::Connection
        def post_init
          send_data "foo\n"
        end
      end

      class Client < EM::Connection
        def initialize(num)
          @num = num
        end

        def receive_data(data)
          close_connection
          EM.add_timer(2){ EM.stop } if @num == 400
        end
      end


      EM.start_server('127.0.0.1', 4045, Server)

      600.times{
        count += 1
        EM.connect('127.0.0.1', 4045, Client, count)
      }
    }

    count.should == 600
  end

end
