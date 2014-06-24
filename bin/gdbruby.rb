#!/usr/bin/env ruby
# vim: set expandtab ts=2 sw=2 nowrap ft=ruby ff=unix : */

# gdbruby.rb - shows the call trace of a running ruby process
#
# Ruby porting of gdbperl.pl.
# gdbperl.pl is made by ahiguchi.
# https://github.com/ahiguti/gdbperl
#
# Copyright (c) Tasuku SUENAGA a.k.a. gunyarakun
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#   Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#   Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#   Neither the name of the author nor the names of its contributors
#      may be used to endorse or promote products derived from this software
#      without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# Usage: gdbruby.rb PROCESS_ID [ruby_EXECUTABLE] [OPTION=VALUE [...]]
#        gdbruby.rb CORE_FILE ruby_EXECUTABLE [OPTION=VALUE [...]]

require 'gdbruby'
require 'gdbruby/config'

config = GDBRuby::Config.new(ARGV)
gdbruby = GDBRuby.new(config)
gdbruby.trace

# vim: set expandtab ts=2 sw=2 nowrap ft=ruby ff=unix :
