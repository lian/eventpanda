require 'shellwords'
require 'socket'
require 'fcntl'

module EventPanda

  @conn_pipes = {}

  def self.add_connection_pipe(conn)
    @conn_pipes[conn.socket] = conn

    unless @conn_pipes_queue
        @conn_pipes_queue = PeriodicTimer.new(0.30){
          if r = Kernel.select(@conn_pipes.keys, nil, nil, 0)
            r[0].each{|socket|
              begin
              @conn_pipes[socket]
                .receive_data( socket.read_nonblock(4096) )
              rescue EOFError
              end
            }
          end
        }

        @conn_pipes_queue_flush = PeriodicTimer.new(1.00){
          @conn_pipes.each{|k,c|
            next if c.alive?
            c.close_connection
          }
          flush_conn_pipes!
        }
    end
  end

  def self.flush_conn_pipes!
    if @conn_pipes.size == 0
      [@conn_pipes_queue, @conn_pipes_queue_flush].each{|i| i.cancel }
      @conn_pipes_queue, @conn_pipes_queue_flush = nil, nil
    end
  end


  def self.popen(cmd, klass=nil, *args)
    free_cb = proc{|conn| @conn_pipes.delete(conn.socket) }

    s = invoke_popen( cmd )
    c = (klass || Connection).new(*args).init_connection(-1, nil, s, free_cb)
    add_connection_pipe(c)

    yield(c) if block_given?
    c
  end


  def self.invoke_popen(cmd_str)
    cmd = if cmd_str.is_a?(Array)
      cmd_str
    else
      Shellwords.shellwords( cmd_str )
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
      exec(*cmd) # exec command here.
      exit -1
    }

    if pid > 0
      sockets[1].close
      pipe = PipeDescriptor.new(sockets[0], pid, cmd)
    else
      sockets.each{|s| s.close }
      raise "no fork"
    end
  end


  module C
    extend FFI::Library
    ffi_lib 'c'
    attach_function :dup2, [:int, :int], :int
  end

  class PipeDescriptor
    attr_reader :socket

    def initialize(socket, forked_pid, invoked_cmd)
      @socket, @pid = socket, forked_pid
      @subprocess_command = invoked_cmd
    end

    def get_subprocess_cmd; @subprocess_command; end
    def get_subprocess_pid; @pid; end

    def get_process_status
      return @process_status if @process_status
      pid, status = Process.waitpid2(@pid, Process::WNOHANG)
      status ? (@socket.close; @process_status = status) : nil
    end

    def read
      @socket.closed? ? '' : @socket.read
    end

    def alive?
      Process.waitpid(@pid, Process::WNOHANG) ? false : true
    rescue Errno::ECHILD
      false
    end

    def exitstatus
      (s = get_process_status) ? s.exitstatus : nil
    end
  end # PipeDescriptor

end # EventPanda
