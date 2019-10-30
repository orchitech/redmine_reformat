module RedmineReformat
  class Execution
    class DummyIpc
      def initialize()
        @queue = []
      end

      def index
        0
      end

      def count
        1
      end

      def send(type, item = nil, count1 = 0, count2 = 0)
        @queue.push([type.to_sym, item.to_s, count1.to_i, count2.to_i])
      end

      def recv(expected = nil)
        res = @queue.shift
        fail 'Unexpected EOF' unless res
        if expected
          type = res.shift
          fail "Unexpected message type '#{type}'" if type != expected
        end
        res
      end

      def close
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
