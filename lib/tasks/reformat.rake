require 'pp'
require 'json'

namespace :reformat do
  desc "Converts richtext fields according to config in ENV"
  task convert: :environment do
    setup_logger
    opts = common_opts(ENV).merge({
      dryrun: ![nil, '', '0', 'false', 'no'].include?(ENV['dryrun']),
    })
    invoker = RedmineReformat::Invoker.new(opts)
    print_reformat_setup_summary(STDERR, opts)
    invoker.run
  end

  desc "Runs simple converter HTTP server"
  task microservice: :environment do
    setup_logger
    opts = common_opts(ENV).merge({
      port: (ENV['port'] || 3030).to_i,
      from_formatting: ENV['from_formatting'],
    })
    microservice = RedmineReformat::Microservice.new(opts)
    print_reformat_setup_summary(STDERR, opts)
    microservice.run
  end

  def setup_logger()
    Rails.logger = Logger.new(STDERR, level: Logger::INFO)
  end

  def common_opts(e)
    {
      converters_json: e['converters_json'],
      to_formatting: e['to_formatting'],
      workers: (ENV['workers'] || 1).to_i,
    }
  end

  def print_reformat_setup_summary(io, opts)
    printopts = opts.dup
    convcfg = opts[:converters_json] && JSON.parse(opts[:converters_json])
    convcfg = convcfg && JSON.pretty_generate(convcfg) || '(use default converters)'
    printopts[:converters_json] = convcfg
    io.puts "Running with setup:"
    PP.pp(printopts, io)
  end
end

task :reformat do
  abort "The task has been renamed. Please use `rake reformat:convert` instead."
end
