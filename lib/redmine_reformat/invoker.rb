module RedmineReformat

  class Invoker
    PARALLEL = 12

    def self.run
      STDOUT.sync = true
      STDERR.sync = true

      progress_rcv = IO.pipe
      progress_resp = IO.pipe
      pipes = PARALLEL.times.collect{IO.pipe}
      pids = PARALLEL.times.collect do |i|
        Process.fork do
          progress_rcv[0].close
          progress_resp[1].close
          progress_ipc = Ipc.new("Worker #{i} Progress",
            progress_resp[0], progress_rcv[1])
          worker_ipc = Ipc.new("Worker #{i}",
            pipes[i][0], pipes[(i + 1) % PARALLEL][1])
          pipes.flatten.each do |fd|
            fd.close unless worker_ipc.use_fd?(fd)
          end
          progress = ReformatWorkerProgress.new(i, PARALLEL, progress_ipc)
          wexn = ReformatWorkerExecution.new(i, PARALLEL, worker_ipc, progress)
          TextileToMarkdown::ConvertRedmine.call(wexn)
          exit 0
        end
      end
      progress_rcv[1].close
      progress_resp[0].close
      pipes.flatten.each do |fd|
        fd.close
      end
      progress_srv_ipc = Ipc.new("Progress collector",
        progress_rcv[0], progress_resp[1])
      progress = ReformatProgress.new
      progress.server(progress_srv_ipc)
      Process.waitall
    end
  end
end
