require_relative 'spec_helper.rb'

require 'eventpanda'

describe 'EventPanda#add_shutdown_hook' do

  it '#add_shutdown_hook' do
    r = false
    EM.run{
      EM.add_shutdown_hook{ r = true }
      EM.stop
    }
    r.should == true

    # order
    r = []
    EM.run{
      EM.add_shutdown_hook{ r << 2 }
      EM.add_shutdown_hook{ r << 1 }
      EM.stop
    }
    r.should == [1, 2]
  end

end
