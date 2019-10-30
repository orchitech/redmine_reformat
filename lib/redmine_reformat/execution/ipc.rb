module RedmineReformat
  class Execution
    class Ipc
      attr_reader :index, :count

      def initialize(name, pipes, index)
        @rfd = pipes[index][0]
        @rfd.sync = true
        @wfd = pipes[(index + 1) % pipes.length][1]
        @wfd.sync = true
        @index = index
        @count = pipes.length
        pipes.flatten.each do |fd|
          fd.close unless use_fd?(fd)
        end
      end

      def send(type, item = nil, count1 = 0, count2 = 0)
        sepitem = " #{item}" if item
        msg = "#{type} #{count1} #{count2}#{sepitem}\n"
        @wfd.write(msg)
      end

      def recv(expected = nil)
        msg = @rfd.gets(chomp: true)
        fail 'Unexpected EOF' unless msg
        msg.match(/\A(\w+) (\d+) (\d+)(?: (.*))?\Z/) do
          res = $1.to_sym, $4, $2.to_i, $3.to_i
          if expected
            type = res.shift
            fail "Unexpected message '#{msg}'" if type != expected
          end
          return res
        end
        fail "Invalid message '#{msg}'"
      end

      def use_fd?(fd)
        [@rfd, @wfd].include?(fd)
      end

      def close
        @rfd.close
        @wfd.close
      end

      private
      def fail(reason)
        STDERR.puts("#{@name} terminated: #{reason}")
        close
        exit 1
      end
    end
  end
end
