require 'shellwords'
require 'socket'
require 'fcntl'

module EventPanda

  @pipe_sockets = []

  def self.add_pipe_socket(socket)
    # socket must include PipeHelperMethods
    @pipe_sockets << socket

    unless @__pipes_queue
        @__pipes_queue = PeriodicTimer.new(0.30){

          if r = Kernel.select(@pipe_sockets, nil, nil, 0)
            r[0].each{|socket|
              buf = ""
              begin
                loop{ buf += socket.read_nonblock(4096) }

              rescue EOFError
                buf[0] && socket.on_read( buf )
                status = socket.get_subprocess_status
                socket.on_close(status)

              rescue Errno::EAGAIN
                buf[0] && socket.on_read( buf )
              end
            }
          else
            (@__pipes_queue.cancel; @__pipes_queue=nil) if @pipe_sockets.size == 0
          end
        }
    end
  end


  def self.popen(cmd, klass=nil, *args)
    free_cb = proc{|socket| @pipe_sockets.delete(socket) }

    s = invoke_popen( cmd )
    c = (klass || Connection).new(*args).init_connection(-1, nil, s, free_cb)

    s.set_callbacks( c.method(:receive_data), c.method(:on_subprocess_exit) )
    add_pipe_socket(s)

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
      s = sockets[0]

      s.extend PipeHelperMethods
      s.init_pipe_helper(pid, cmd)
      s
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

  module PipeHelperMethods
    def init_pipe_helper(pid, invoked_cmd)
      @pid, @subprocess_command = pid, invoked_cmd
    end

    def set_callbacks(receive_cb, exit_cb)
      @__on_data, @__on_close = receive_cb, exit_cb
    end
    def on_read(data);    @__on_data.call(data);    end
    def on_close(status); @__on_close.call(status); end

    def read_pipe; closed? ? '' : read; end

    def subprocess_cmd; @subprocess_command; end
    def subprocess_pid; @pid; end

    def get_subprocess_status
      return @__status if @__status
      pid, status = Process.waitpid2(@pid, Process::WNOHANG)
      status ? (close; @__status = status) : nil
    end

    def alive?
      Process.waitpid(@pid, Process::WNOHANG) ? false : true
    rescue Errno::ECHILD
      false
    end

    def exitstatus
      (s = get_subprocess_status) ? s.exitstatus : nil
    end
  end

end # EventPanda
