require 'shellwords'
require 'socket'
require 'fcntl'

module EventPanda

  @conn_pipes = []

  def self.add_connection_pipe(conn)
    @conn_pipes << conn

    unless @conn_pipes_queue
      #EventPanda.next_tick do
        @conn_pipes_queue = PeriodicTimer.new(0, nil, nil, 300){
          @conn_pipes.each{|c| c.read_data! }
        }

        @conn_pipes_queue_flush = PeriodicTimer.new(1, nil, nil, 500){
          @conn_pipes.each{|c|
            next if c.alive?

            c.close_connection
            @conn_pipes.delete(c)

            if @conn_pipes.size == 0
              [@conn_pipes_queue, @conn_pipes_queue_flush].each{|i| i.cancel }
              @conn_pipes_queue, @conn_pipes_queue_flush = nil, nil
            end
          }
        }
      #end
    end
  end


  def self.popen(cmd, klass=nil, *args)
    #free_cb = proc{|conn| @conns.delete(s); @conn_pipes[conn] }
    free_cb = proc{|conn| @conn_pipes.delete(conn) }

    s = invoke_popen( cmd )
    c = (klass || Connection).new(*args).init_connection(-1, nil, s, free_cb)

    add_connection_pipe(c)
    #@conns[s] = c

    yield(c) if block_given?
    c
  end


  def self.invoke_popen(cmd_str)
    cmd = if cmd_str.is_a?(Array)
      cmd_str
    else
      Shellwords.shellwords( cmd_str )
      #cmd.unshift( cmd.first ) if cmd.first; p cmd
    end

    sockets = ::Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0) 
    val = sockets[0].fcntl(Fcntl::F_GETFL, 0)
    unless sockets[0].fcntl(Fcntl::F_SETFL, val | Fcntl::O_NONBLOCK) == 0
      sockets.each{|s| s.close }; return nil
    end

    pid = fork{
      sockets[0].close
      C.dup2(sockets[1].fileno, $stdin.fileno)
      sockets[1].close
      C.dup2($stdin.fileno, $stdout.fileno)
      C.execvp(cmd) # exec command here.
      exit -1
    }

    if pid > 0
      sockets[1].close

      pd = PipeDescriptor.new(sockets[0], pid, cmd)
      #Add (pd); #output_binding = pd->GetBinding();
    else
      sockets.each{|s| s.close }
      raise "no fork"
    end
  end


  module C
    extend FFI::Library
    ffi_lib 'c'
    attach_function :dup2, [:int, :int], :int
    attach_function :ffi_execvp, :execvp, [:string, :pointer], :int

    def self.execvp(cmd)
      ptrs = cmd.map{|i| FFI::MemoryPointer.from_string(i) } + [nil]
      argv = FFI::MemoryPointer.new(:pointer, ptrs.length)
      ptrs.each_with_index{|p,i| argv[i].put_pointer(0,  p) }
      ffi_execvp(cmd[0], argv)
    end
  end

  class PipeDescriptor
    attr_reader :socket, :pid

    def initialize(socket, forked_pid, invoked_cmd)
      @socket, @pid = socket, forked_pid
      @subprocess_command = invoked_cmd
    end

    def read
      @socket.closed? ? '' : @socket.read
    end

    def get_subprocess_cmd; @subprocess_command; end
    def get_subprocess_pid; @pid; end

    def alive?
      Process.waitpid(@pid, Process::WNOHANG) ? false : true
    rescue Errno::ECHILD
      false
    end

    def get_process_status
      return @process_status if @process_status
      pid, status = Process.waitpid2(@pid, Process::WNOHANG)
      status ? (@socket.close; @process_status = status) : nil
    end

    def exitstatus
      (s = get_process_status) ? s.exitstatus : nil
    end
  end # PipeDescriptor

end # EventPanda
