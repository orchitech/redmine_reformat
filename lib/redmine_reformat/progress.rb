# frozen_string_literal: true

module RedmineReformat
  class ReformatProgress
    def initialize
      @totals = Hash.new
      @subtotals = Hash.new {|h,k| h[k] = 0}
      @progress = Hash.new {|h,k| h[k] = 0}
    end

    def subtotal(item)
      @subtotals[item]
    end

    def total(item)
      @totals[item]
    end

    def start(item, jobtotal, total)
      if @totals[item] && @totals[item] != total
        raise "Unexpected total count reported for #{item}"
      elsif @totals[item].nil?
        @totals[item] = total
      end
      n = @subtotals[item] += jobtotal
      raise "#{item}: job subtotal > total " if @subtotals[item] > n
    end

    PERIOD = 1000
    def progress(item, increment)
      oldn = @progress[item]
      newn = @progress[item] = oldn + increment
      raise "#{item}: progress > subtotal" if newn > @subtotals[item]
      return unless reporting? && increment > 0
      if newn == @totals[item] || (newn / PERIOD) > (oldn / PERIOD)
        report(item)
      end
    end

    def finish
      STDERR.puts("Progress monitoring finished.")
    end

    def reporting?
      true
    end

    def report(item)
      STDERR.puts("#{item}: #{@progress[item]} / #{@totals[item]}")
    end

    def complete?
      item_jobs_started? && item_jobs_complete?
    end

    def item_jobs_started?
      @subtotals == @totals
    end

    def items_completion
      c = n = 0
      @subtotals.each do |item, subtotal|
        n += 1
        c += 1 if @progress[item] == @subtotals[item]
      end
      [c, n]
    end

    def item_jobs_complete?
      c, n = items_completion
      c == n
    end

    def server(ipc)
      while msg = ipc.recv do
        type, item, n1, n2 = msg
        case type
        when :start
          start(item, n1, n2)
        when :progress
          progress(item, n1)
        when :items_completion
          c, n = items_completion
          ipc.send(:items_completion_res, nil, c, n)
        when :finish
          return
        else
          raise "Unexpected message type '#{type}'"
        end
      end
    end
  end

  class ReformatWorkerProgress < ReformatProgress
    def initialize(ipc)
      super()
      @ipc = ipc
    end

    def start(item, jobcount, count)
      super
      @ipc.send(:start, item, jobcount, count)
    end

    def progress(item, count)
      super
      @ipc.send(:progress, item, count)
    end

    def finish
      @ipc.send(:finish)
    end

    def complete?
      return false unless super
      @ipc.send(:items_completion)
      ign, c, n = @ipc.recv(:items_completion_res)
      c == n
    end

    def item_jobs_started?
      # single worker
      true
    end

    def reporting?
      false
    end
  end
end
