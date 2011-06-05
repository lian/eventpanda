require_relative 'spec_helper.rb'

require 'eventpanda'

describe 'EventPanda::Deferrable' do

  class Later
    include EM::Deferrable
  end

  it 'timeout without args' do
    proc{
      EM.run {
        df = Later.new
        df.timeout(0)
        df.errback { EM.stop }
        EM.add_timer(0.01) { flunk "Deferrable was not timed out." }
      }
    }.should.not.raise NoMethodError
  end

  it 'timeout with args' do
   args = nil

   EM.run {
      df = Later.new
      df.timeout(0, :timeout, :foo)
      df.errback do |type, name|
        args = [type, name]
        EM.stop
      end

      EM.add_timer(0.01) { flunk "Deferrable was not timed out." }
    }

    args.should == [:timeout, :foo]
  end

end
