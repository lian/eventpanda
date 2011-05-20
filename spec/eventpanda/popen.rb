require_relative 'spec_helper.rb'
require 'eventpanda'


describe 'EventPanda #popen' do

  it "#invoke_popen" do
    cmd = "ruby -e'puts \"hello\"'"
    fd = EM.invoke_popen(cmd)
    fd.subprocess_cmd.should == Shellwords.shellwords(cmd)
    fd.subprocess_pid.should != 0
    fd.alive?.should == true
    fd.get_subprocess_status.should == nil
    fd.read_pipe.should == "hello\n"
    fd.read_pipe.should == ""
    fd.get_subprocess_status.exitstatus.should == 0
    fd.exitstatus.should == 0
    fd.read_pipe.should == ""
    fd.alive?.should == false
  end


  it "#popen" do
    out = []

    class RubyCounter < EM::Connection
      def initialize(a)
        @a = a
      end
      def post_init
        send_data "2\n"
      end
      def receive_data(data)
        @a << "ruby sent me: #{data}"
      end
      def unbind
        @a << "ruby died with exit status: #{get_status.exitstatus}"
      end
    end


    EM.run{
      EM.popen("ruby -e' $stdout.sync = true; gets.to_i.times{ |i| puts i+1; sleep 1 } '", RubyCounter, out)
    }.should == true

    out.should == [
      "ruby sent me: 1\n",
      "ruby sent me: 2\n",
      "ruby died with exit status: 0"
    ]
  end

end
