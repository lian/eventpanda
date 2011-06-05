require_relative 'spec_helper.rb'

require 'eventpanda'

describe 'EventPanda#reactor_running?' do

  it '#reactor_running?' do
    EM.reactor_running?.should == false

    r = false
    EM.run {
      r = EM.reactor_running?
      EM.stop
    }
    r.should == true
  end

end
