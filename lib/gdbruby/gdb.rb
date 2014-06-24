require 'open3'

class GDBRuby
  class GDB
    COMMAND_READ_BUFFER_SIZE = 1024
    attr_reader :exec_options

    def initialize(config)
      @config = config
      @exec_options = ['gdb', '-silent', '-nw', @config.exe, @config.core_or_pid]
    end

    def run
      @gdb_stdin, @gdb_stdout, @gdb_stderr = *Open3.popen3(*@exec_options)
      prepare
      begin
        yield
        detach
      ensure
        if @config.is_pid
          Process.kill('CONT', @config.core_or_pid.to_i)
        end
        @gdb_stdin.close
        @gdb_stdout.close
        @gdb_stderr.close
      end
    end

    def prepare
      cmd_exec('')
      cmd_exec('set pagination off')
    end

    def detach
      cmd_get_value("detach")
      cmd_get_value("quit")
    end

    def log_gdb(pre, message)
      return unless @config['verbose_gdb', false]
      message.each_line do |line|
        puts "#{pre}: #{line}"
      end
    end

    def cmd_get_pointer(cmd, type)
      response = cmd_exec(cmd)
      raise "Invalid pointer #{response}" unless response =~ /\(#{type} \*\) (0x[0-9a-f]+)/
      $1
    end

    def cmd_exec(cmd)
      log_gdb('C', cmd)
      if cmd
        send_cmd = cmd.empty? ? cmd : "#{cmd}\n"
        r = @gdb_stdin.syswrite(send_cmd)
        if r < send_cmd.length
          raise "failed to send: [#{cmd}]"
        end
      end

      responses = []
      while true
        # TODO: specify buffer size
        begin
          buf = @gdb_stdout.sysread(COMMAND_READ_BUFFER_SIZE)
        rescue
          break
        end
        responses << buf
        break if buf =~ /\(gdb\) $/
      end

      response = responses.join('')
      log_gdb('R', response)
      response
    end

    def cmd_get_value(cmd)
      response = cmd_exec(cmd)
      return '' unless response =~ /\A\$\d+ =\s+(.+)/

      value = $1
      if value =~ /0x\w+\s+\"(.+)\"/
        $1
      else
        value
      end
    end

  end
end
