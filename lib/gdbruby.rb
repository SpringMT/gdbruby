require 'gdbruby/gdb'
require 'gdbruby/ruby_internal'

class GDBRuby
  MAX_FRAMES = 30

  def initialize(config)
    @config = config
  end

  def trace
    @gdb = GDBRuby::GDB.new(@config)
    @ri  = GDBRuby::RubyInternal.new(@gdb)
    puts "command:\n#{@gdb.exec_options.join(' ')}"
    puts ''
    @gdb.run do
      show_environ if @config['env', true]
      show_ruby_version
      show_backtrace
    end
  end

  def show_environ
    i = 0
    puts "environ:"
    while true
      response = @gdb.cmd_get_value("p ((char **)environ)[#{i}]")
      break if response.empty? or response == '0x0'
      puts response
      i += 1
    end
    puts ''
  end

  def get_map_of_ruby_thread_pointer_to_gdb_thread_id
    # After 'set pagination off' is executed,
    # thread info is one line per thread.
    map = {}
    @gdb.cmd_exec('info threads').each_line do |line|
      if line =~ /\A[\s\*]+(\d+)/
        gdb_thread_id = $1
        @gdb.cmd_exec("thread #{gdb_thread_id}")
        @gdb.cmd_exec("backtrace").each_line do |bt_line|
          if bt_line =~ /\(th=(0x[0-9a-f]+)/
            ruby_thread_pointer = $1
            map[ruby_thread_pointer] = gdb_thread_id
            break
          end
        end
      end
    end
    map
  end

  def get_ruby_frame(frame_count)
    # Accessor
    cfp = "(ruby_current_thread->cfp + #{frame_count})"
    iseq = "#{cfp}->iseq"

    # Check iseq
    iseq_ptr = @gdb.cmd_get_pointer("p #{iseq}", 'rb_iseq_t')
    if iseq_ptr.hex != 0
      # TODO: check cfp->pc is null or not

      iseq_type = @gdb.cmd_get_value("p #{iseq}->type").intern

      case iseq_type
      when :ISEQ_TYPE_TOP
        return
      end

      # Ruby function
      @prev_location = {
        :cfp => cfp,
        :iseq => iseq,
      }
      file_path = @ri.rstring_ptr(@gdb.cmd_get_value("p #{iseq}->location.absolute_path"))
      if file_path.empty?
        file_path = @ri.rstring_ptr(@gdb.cmd_get_value("p #{iseq}->location.path"))
      end
      label = @ri.rstring_ptr(@gdb.cmd_get_value("p #{iseq}->location.label"))
      base_label = @ri.rstring_ptr(@gdb.cmd_get_value("p #{iseq}->location.base_label"))
      line_no = @ri.rb_vm_get_sourceline(cfp, iseq)

      self_value = @gdb.cmd_get_value("p #{cfp}->self")
      self_type = @ri.rb_type(self_value)
      self_name = self_type == 'RUBY_T_CLASS' ? @gdb.cmd_get_value("p rb_class2name(#{cfp}->self)") : ''

      func_prefix = "#{self_name}#" unless self_name.empty?

      {
        :callee => label.empty? ? '(unknown)' : "#{func_prefix}#{label}",
        :args => '', # TODO: implement
        :source_path_line => "#{file_path}:#{line_no}",
      }
    elsif @ri.rubyvm_cfunc_frame_p(cfp)
      # C function

      mid = @gdb.cmd_get_value("p #{cfp}->me->def ? #{cfp}->me->def->original_id : #{cfp}->me->called_id")
      label = @ri.rb_id2str(mid)
      if @prev_location
        cfp = @prev_location[:cfp]
        iseq = @prev_location[:iseq]

        file_path = @ri.rstring_ptr(@gdb.cmd_get_value("p #{iseq}->location.absolute_path"))
        if file_path.empty?
          file_path = @ri.rstring_ptr(@gdb.cmd_get_value("p #{iseq}->location.path"))
        end
        line_no = @ri.rb_vm_get_sourceline(cfp, iseq)
      end

      {
        :callee => label,
        :args => '', # TODO: implement
        :source_path_line => "#{file_path}:#{line_no}",
      }
    end
  end

  def check_ruby_version
    @ruby_version = @gdb.cmd_get_value('p ruby_version')
    case @ruby_version.intern
    when :'2.0.0'
    end
    raise "unknown ruby version" unless @ruby_version
  end

  def show_ruby_version
    check_ruby_version
    puts 'ruby_version:'
    puts @ruby_version
    puts ''
  end

  def show_backtrace
    # TODO: List threads with ruby_current_vm->living_threads and dump all threads.
    #       Now, we dump only ruby_current_thread which is equivalent to ruby_current_vm->running_thread.

    thread_map = get_map_of_ruby_thread_pointer_to_gdb_thread_id

    # Detect ruby running thread and change gdb thread to it
    current_thread_pointer = @gdb.cmd_get_pointer('p ruby_current_thread', 'rb_thread_t')
    gdb_thread_id = thread_map[current_thread_pointer]
    raise 'Cannot find current thread id in gdb' if gdb_thread_id.nil?
    @gdb.cmd_exec("thread #{gdb_thread_id}")

    # Show C backtrace
    if @config['c_trace', true]
      response = @gdb.cmd_exec('bt')
      puts 'c_backtrace:'
      response.each_line do |line|
        break if line == '(gdb) '
        puts line
      end
      puts ''
    end

    # Show Ruby backtrace
    puts 'ruby_backtrace:'
    cfp_count = @gdb.cmd_get_value('p (rb_control_frame_t *)(ruby_current_thread->stack + ruby_current_thread->stack_size) - ruby_current_thread->cfp').to_i

    frame_infos = []
    @prev_location = nil
    # NOTE: @prev_location may not be set properly when limited by MAX_FRAMES
    ([MAX_FRAMES, cfp_count].min - 1).downto(0).each do |count|
      frame_info = get_ruby_frame(count)
      frame_infos << frame_info if frame_info
    end
    frame_infos.reverse.each_with_index do |fi, i|
      puts "[#{frame_infos.length - i}] #{fi[:callee]}(#{fi[:args]}) <- #{fi[:source_path_line]}"
    end
  end

end

