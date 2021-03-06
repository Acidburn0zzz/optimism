class Optimism
  module Require
    extend Optimism::Util::Concern

    module ClassMethods
      # Load configuration from file
      #
      # use $: and support home path like '~/.foorc'.
      # by default, it ignore missing files.
      #
      # @example
      #
      #   Optimism.require "foo"
      #
      #   Optimism.require *%w[
      #     /etc/foo
      #     ~/.foorc
      #   ]
      #
      #   # add to an existing configuration object.
      #   Rc = Optimism.new
      #   Rc.a.b << Optimism("my.age = 1")  #=> Rc.a.b.my.age is 1
      #
      #   # call with block
      #   ENV["AGE"] = "1"
      #   Rc = Optimism.require_env("AGE") { |age| age.to_i }
      #   p Rc.age #=> 1
      #
      #   # option :mixin => :ignore is ignore already exisiting value.
      #   # a.rb
      #     a.b = 1
      #     a.c = "foo"
      #   # b.rb
      #     a.b = 2
      #     a.d = "bar"
      #   Optimism.require %w(a b), :mixin => :ignore 
      #   #=>
      #     a.b is 1
      #     a.c is "foo"
      #     a.d is "bar"
      #   
      # @overload require_file(*paths, o={})
      #   @param [String] *paths
      #   @param [Hash] opts other options pass to Optimism.new
      #   @option opts [Boolean] :merge (:replace) :replace :ignore
      #   @return [Optimism]
      def require_file(*paths)
        paths, optimism_opts = Util.extract_options(paths, merge: :replace)
        opts = [:merge, :raise].each.with_object({}){|n, m|
          m[n] = optimism_opts.delete(n)
        }

        o = Optimism.new(nil, namespace: optimism_opts.delete(:namespace))
        paths.each { |name|
          path = find_file(name)
          if path.empty? 
            opts[:raise] ? raise(EMissingFile, "can't find file -- #{name.inspect}") : next
          end

          optimism_opts[:parser] = Optimism.extension[File.extname(path)] 
          optimism_opts[:filename] = path

          o2 = Optimism.new(File.read(path), optimism_opts)

          case opts[:merge] 
          when :replace
            o << o2 
          when :ignore
            o2 << o
            o = o2
          end
        }

        o
      end

      # same as require_file with raising error.
      #
      # @raise EMissingFile
      #
      # @see require_file
      def require_file!(*paths)
        paths, opts = Util.extract_options(paths)
        opts[:raise] = true
        require_file(*paths, opts)
      end

      alias require require_file
      alias require! require_file!

      # load configuration from environment variables.
      # @see require_file
      #
      # @example
      # 
      #  ENV["A"] = "1"
      #  ENV["OPTIMISM_A] = "a"
      #  ENV["OPTIMISM_B_C] = "b"
      #
      #  # default is case_insensive
      #  require_env("A")                      -> Optimism({a: 1})
      #  require_env("A", case_sensive: true)  -> Optimism({A: 1})
      #
      #  # with Regexp
      #  require_env(/OPTIMISM_(.*)/)                 -> Optimism({a: "a", b_c: "b"})
      #  require_env(/OPTIMISM_(.*), :split => "_")   -> Optimism({a: "a", b: {c: "b"}})
      #
      # @overload require_env(*envs, opts={}, &blk)
      #   @param [String, Regexp] envs
      #   @param [Hash] opts
      #   @option opts [String] :namespace
      #   @option opts [String] :default # see #initiliaze
      #   @option opts [String, Regexp] :split
      #   @option opts [Boolean] :case_sensive (false)
      #   @return [Optimism] def require_env(*args, &blk)
      def require_env(*args, &blk)
        # e.g. OPTIMISM_A OPTIMISM_B for /OPTIMISM_(.*)/
        # args => { 'A' => 'value' }
        Hash === args.last ? opts = args.pop : opts = {}

        envs = {}
        args.each do |env|
          case env
          when Regexp
            ENV.each { |key, value|
              next unless key.match(env)
              envs[$1] = key
            }
          when String
            envs[env] = env
          else
            raise ArgumentError, "only String and Regexp -- #{env}(#{env.class})"
          end
        end

        opts[:split] ||= /\Z/

        o = Optimism.new(nil, default: opts[:defualt])
        envs.each { |path, env|
          path = opts[:case_sensive] ? path : path.downcase
          path = path.split(opts[:split]).join('.')
          value = blk ? blk.call(ENV[env]) : ENV[env]
          o._store path, value
        }

        o._walk!('-'+opts[:namespace], :build => true) if opts[:namespace]

        o
      end

      # get configuration from user input. 
      # @ see require_input
      #
      # @example
      #   
      #   o = require_input("what's your name?", "my.name", default: "foo")
      #   o.my.name #=> get from user input or "foo"
      #
      # @param [String] msg print message to stdin.
      # @param [String] key
      # @param [Hash] opts
      # @option opts [Object] :namespace
      # @option opts [Object] :default use this default if user doesn't input anything.
      # @return [Optimism]
      def require_input(msg, path, o={}, &blk)
        default = o[:default] ? "(#{o[:default]})"  : ""
        print msg+default
        value = gets.strip
        value = value.empty? ? o[:default] : value
        value = blk ? blk.call(value) : value
        rc = Optimism.new
        rc._store path, value

        rc._root
      end

    private

      # Find a file.
      #
      # @param opts [Hash] options
      #
      # @example
      #
      #   file_file("does_not_exists")              -> ""
      #
      # @return [String] 
      def find_file(name, opts={})
        path = ""

        # ~/.gutenrc  or ./relative/path or ../relative/path
        if name =~ %r!^~|^\.\.?/!
          file = File.expand_path(name)
          path = file if File.exists?(file)

        # /absolute/path/to/rc
        elsif File.absolute_path(name, ".") == name # rbx need "."
          path = name if File.exists?(name)

        # name
        else
          path = $:.find.with_object("") { |p, memo|

            (Optimism.extension.keys+[""]).find { |ext|
              file = File.join(p, name+ext)
              if File.exists? file
                memo.replace file
                true
              end
            }
          }
        end

        path
      end
    end

    # a shortcut for Require#require_input
    # @see Require#require_input
    # @see Optimism#_walk
    #
    # @example
    #
    #  o = Optimism do
    #    _.my.age = 1
    #  end
    #  o._require_input("how old are you?", "my.age") # use a default value with 1
    #
    # @param [Hash] opts
    # @option opts [Object] :default default value
    def _require_input(msg, fullpath, opts={}, &blk)
      opts[:default] ||= _fetch(fullpath, nil)
      self << Optimism.require_input(msg, fullpath, opts, &blk)
      self
    end
  end
end
