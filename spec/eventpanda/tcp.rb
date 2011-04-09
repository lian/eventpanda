require_relative 'spec_helper.rb'

require 'eventpanda'


class TestServer < EM::Connection
  def receive_data(data)
    send_data(data)
  end
end

class TestClient < EM::Connection
  def post_init
    send_data("echo\n")
  end

  def receive_data(data)
    p [@fd, data]
    close_connection
  end
end


describe 'EventPanda::TCP' do

  it "run and gc - 3" do
    count = 0
    EM.run{
      EM.add_timer(5){ GC.start; EM.stop }
      GC.start

      EM.start_server('127.0.0.1', 4045, TestServer)

      200.times{ count += 1
        EM.connect('127.0.0.1', 4045, TestClient)
      }
    }
    count.should == 200
  end

end
