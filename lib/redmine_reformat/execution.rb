require 'redmine_reformat/converters/configured_converters'

module RedmineReformat
  class Execution
    attr_accessor :dryrun, :converter, :to_formatting

    ConfiguredConverters = RedmineReformat::Converters::ConfiguredConverters

    def initialize(progress, ipc = nil)
      @ipc = ipc || DummyIpc.new
      @index = @ipc.index
      @wcount = @ipc.count
      @progress = progress
      @dryrun = false
      @converter = nil
      @to_formatting = nil
    end

    def master?
      @index == 0
    end

    def collector?
      @index == @wcount - 1
    end

    def start
      v = reduce_rendezvous(:start) {|v| v + 1}
      if v == @wcount
        @converter ||= ConfiguredConverters.new(DEFAULT_CONVERTER_CONFIG)
        STDERR.puts "All #{v}/#{@wcount} workers started." if master?
      else
        fail "#{t} failed, only #{v}/#{@wcount} workers confirmed start"
      end
    end

    def scope(item, scope)
      total = scope.count
      limit = (total + @wcount - 1) / @wcount
      offset = @index * limit

      model = if scope.is_a?(Class) then scope else scope.model end
      scope = scope.reorder(id: :asc)
      mymeta = model.select('MAX(id) max_id, MIN(id) min_id, COUNT(id) count_id')
        .from(scope.offset(offset).limit(limit).select(:id))
        .reorder(nil)
        .first

      @progress.start(item, mymeta.count_id, total)
      myscope = scope.where(id: mymeta.min_id..mymeta.max_id)
      myscope
    end

    def mytotal(item)
      @progress.subtotal(item)
    end

    def total(item)
      @progress.total(item)
    end

    def progress(item, increment)
      @progress.progress(item, increment)
    end

    def finish(result)
      # agree on execution result
      myv = result ? 1 : 0
      v = reduce_rendezvous(:finish) {|v| v + myv}
      STDERR.puts "#{v}/#{@wcount} workers finished successfuly." if master?
      return false unless v == @wcount

      # agree on completion
      v = reduce_rendezvous(:completion) do |v|
        v += @progress.complete? ? 1 : 0
      end
      STDERR.puts "#{v}/#{@wcount} workers confirmed completion." if master?
      v == @wcount
    end

    def tx_wait
      @ipc.recv(:tx_proceed) unless master?
      @progress.finish if master?
    end

    def tx_done
      @ipc.send(:tx_proceed) unless collector?
    end

    private
    def reduce_rendezvous(type, &block)
      v = c = 0
      ign, v, c = @ipc.recv(type) unless master?
      fail "#{type} reduce_rendezvous reducing failed" unless c == @index
      c += 1
      v = yield v
      @ipc.send(type, nil, v, c)
      ign, v, c = @ipc.recv(type)
      fail "#{type} reduce_rendezvous failed" unless c == @wcount
      @ipc.send(type, nil, v, c) unless collector?
      v
    end

    def fail(reason)
      STDERR.puts("Worker #{@index} terminated: #{reason}")
      @ipc.close
      exit 1
    end

    DEFAULT_CONVERTER_CONFIG = [
      {
        from_formatting: 'textile',
        to_formatting: ['markdown', 'common_mark'],
        converters: 'TextileToMarkdown',
      }, {
        from_formatting: 'markdown',
        to_formatting: 'common_mark',
        converters: ['MarkdownToCommonmark'],
        force_crlf: false,
        match_trailing_nl: false,
      },
    ]
  end
end
