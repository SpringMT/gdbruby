class GDBRuby
  class Config
    attr_reader :core_or_pid, :exe, :is_pid

    def initialize(argvs)
      @config_map = {}
      @argv = []

      argvs.each do |argv|
        if argv =~ /^(\w+)=(.+)$/
          @config_map[$1] = $2
        else
          @argv << argv
        end
      end
      parse_argv
    end

    def parse_argv
      @core_or_pid = @argv[0]

      unless @core_or_pid
        message =
          "Usage: #{$0} PROCESS_ID [ruby_EXECUTABLE] [OPTION=VALUE [...]]\n" +
          "Usage: #{$0} CORE_FILE ruby_EXECUTABLE [OPTION=VALUE [...]]\n"
        puts message
        exit 1
      end

      exe = @argv[1]

      @is_pid = (@core_or_pid =~ /^\d+$/)
      if @is_pid
        if exe.nil?
          begin
            if RUBY_PLATFORM =~ /linux/
              exe = File.readlink("/proc/#{@core_or_pid}/exe")
            end
          rescue
          end
        end

        if exe.nil?
          exe = `rbenv which ruby`
          exe = `which ruby` unless FileTest.exist?(exe)
          exe.chomp!
        end
      end

      raise "failed to detect ruby executable" unless exe
      @exe = exe
    end

    def [](key, default_value = nil)
      if @config_map.has_key?(key)
        return case default_value
        when TrueClass, FalseClass
          not (@config_map[key].empty? || @config_map[key] == '0')
        when Numeric
          @config_map[key].to_i
        else
          @config_map[key]
        end
      end
      default_value
    end
  end
end


