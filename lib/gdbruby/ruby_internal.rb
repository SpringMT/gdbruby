class GDBRuby
  class RubyInternal
    FL_USHIFT = 12
    FL_USER1 = 1 << (FL_USHIFT + 1)
    RSTRING_NOEMBED = FL_USER1

    VM_FRAME_MAGIC_CFUNC = 0x61
    VM_FRAME_MAGIC_MASK_BITS = 8
    VM_FRAME_MAGIC_MASK = ~(~0 << VM_FRAME_MAGIC_MASK_BITS)

    def initialize(gdb)
      @gdb = gdb
    end

    def ruby_vm_ifunc_p(pointer)
      # pointer is string like 0xaabbccdd
      @gdb.cmd_get_value("p (enum ruby_value_type)(((struct RBasic *)(#{pointer}))->flags & RUBY_T_MASK) == RUBY_T_NODE") != '0'
    end

    def ruby_vm_normal_iseq_p(pointer)
      @gdb.cmd_get_value("p #{pointer} && #{pointer} != 0") != '0' and not ruby_vm_ifunc_p(pointer)
    end

    def rb_vm_get_sourceline(cfp, iseq)
      if ruby_vm_normal_iseq_p(iseq)
        # calc_lineno()@vm_backtrace.c
        current_position = @gdb.cmd_get_value("p #{cfp}->pc - #{iseq}->iseq_encoded").to_i
        # rb_iseq_line_no()@iseq.c
        current_position -= 1 unless current_position == 0
        # find_line_no@iseq.c and get_line_info@iseq.c
        line_info_size = @gdb.cmd_get_value("p #{iseq}->line_info_size").to_i
        line_info_table = "#{iseq}->line_info_table"
        case line_info_size
        when 0
          return 0
        when 1
          return @gdb.cmd_get_value("p #{line_info_table}[0].line_no").to_i
        else
          (1..line_info_size).each do |i|
            position = @gdb.cmd_get_value("p #{line_info_table}[#{i}].position").to_i
            if position == current_position
              return @gdb.cmd_get_value("p #{line_info_table}[#{i}].line_no").to_i
            elsif position > current_position
              return @gdb.cmd_get_value("p #{line_info_table}[#{i - 1}].line_no").to_i
            end
          end
        end
      end
      0
    end

    # NOTE: This logic is slow because many commands are sent to gdb.
    #       Fetch consts with 'ptype enum ruby_value_type' first and
    #       check types in Ruby.
    def rb_type(value)
      type_str = nil
      # IMMEDIATE_P
      if @gdb.cmd_get_value("p (int)(#{value}) & RUBY_IMMEDIATE_MASK") != '0'
        # FIXNUM_P
        if @gdb.cmd_get_value("p (int)(#{value}) & RUBY_FIXNUM_FLAG") != '0'
          type_str = 'RUBY_T_FIXNUM'
        # FLONUM_P
        elsif @gdb.cmd_get_value("p ((int)(#{value}) & RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG") != '0'
          type_str = 'RUBY_T_FLONUM'
        elsif @gdb.cmd_get_value("p (#{value}) == RUBY_Qtrue") != '0'
          type_str = 'RUBY_T_TRUE'
        # SYMBOL_P
        elsif @gdb.cmd_get_value("p (VALUE)(#{value}) & ~(~(VALUE)0 << RUBY_SPECIAL_SHIFT) == RUBY_SYMBOL_FLAG") != '0'
          type_str = 'RUBY_T_SYMBOL'
        elsif @gdb.cmd_get_value("p (#{value}) == RUBY_Qundef") != '0'
          type_str = 'RUBY_T_UNDEF'
        end
      elsif @gdb.cmd_get_value("p (int)(#{value}) & RUBY_FIXNUM_FLAG") != '0'
        # special consts
        const = @gdb.cmd_get_value("p (enum ruby_special_consts)(#{value})")
        # TODO: change to map
        case const
        when 'RUBY_Qnil'
          type_str = 'RUBY_T_NIL'
        when 'RUBY_Qfalse'
          type_str = 'RUBY_T_FALSE'
        end
      else
        # builtin type
        type_str = @gdb.cmd_get_value("p (enum ruby_value_type)(((struct RBasic*)(#{value}))->flags & RUBY_T_MASK)")
      end
    end

    def rstring_ptr(value_pointer)
      no_embed = @gdb.cmd_get_value("p ((struct RBasic *)(#{value_pointer}))->flags & #{RSTRING_NOEMBED}")
      if no_embed == '0'
        # embedded in struct
        @gdb.cmd_get_value("p (char *)((struct RString *)(#{value_pointer}))->as.ary")
      else
        # heap pointer
        @gdb.cmd_get_value("p (char *)((struct RString *)(#{value_pointer}))->as.heap.ptr")
      end
    end

    def rubyvm_cfunc_frame_p(cfp)
      @gdb.cmd_get_value("p (#{cfp}->flag & #{VM_FRAME_MAGIC_MASK}) == #{VM_FRAME_MAGIC_CFUNC}") != '0'
    end

    def do_hash(key, table)
      # NOTE: table->type->hash is always st_numhash
      key
    end

    def st_lookup(table, key)
      hash_val = do_hash(key, table)

      raise if @gdb.cmd_get_value("p (#{table})->entries_packed") != '0'
      raise if @gdb.cmd_get_value("p (#{table})->type->hash == st_numhash") == '0'
      raise if @gdb.cmd_get_value("p (#{table})->type->compare == st_numcmp") == '0'

      # TODO: check table->entries_packed
      bin_pos = @gdb.cmd_get_value("p (#{hash_val}) % (#{table})->num_bins")

      ptr = find_entry(table, key, hash_val, bin_pos)

      if ptr.hex == 0
        nil
      else
        value = @gdb.cmd_get_value("p ((struct st_table_entry *)(#{ptr}))->record")
        value
      end
    end

    def ptr_not_equal(table, ptr, hash_val, key)
      ptr =~ /(0x[0-9a-f]+)\z/
      ptr_num = $1.hex
      t_hash = @gdb.cmd_get_value("p (#{ptr})->hash")
      t_key = @gdb.cmd_get_value("p (#{ptr})->key")
      # NOTE: table->type->compare is always st_numcmp
      ptr_num != 0 and (t_hash != hash_val or t_key != key)
    end

    def find_entry(table, key, hash_val, bin_pos)
      ptr = @gdb.cmd_get_value("p (#{table})->as.big.bins[#{bin_pos}]")
      if ptr_not_equal(table, ptr, hash_val, key)
        next_ptr = @gdb.cmd_get_value("p (#{ptr})->next")
        while ptr_not_equal(table, next_ptr, hash_val, key)
          ptr = next_ptr
          next_ptr = @gdb.cmd_get_value("p (#{ptr})->next")
        end
        ptr = next_ptr
      end
      ptr =~ /(0x[0-9a-f]+)\z/
      $1
    end

    def rb_id2str(id)
      rstring_ptr(st_lookup('global_symbols.id_str', id))
    end

  end
end

