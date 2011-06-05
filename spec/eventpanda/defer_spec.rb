require_relative 'spec_helper.rb'

require 'eventpanda'

describe 'EventPanda#defer' do

  it "#defer" do
    n, n_times = 0, 20
    EM.run {
      n_times.times {
        work_proc = proc { n += 1 }
        callback = proc { EM.stop if n == n_times }
        EM.defer(work_proc, callback)
      }
    }
    n.should == n_times
  end

end
