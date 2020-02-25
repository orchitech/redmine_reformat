require 'json'

task reformat: :environment do
  setup_logger
  opts = {
    workers: ENV['workers'],
    dryrun: ![nil, '', '0', 'false', 'no'].include?(ENV['dryrun']),
    converters_json: ENV['converters_json'],
    to_formatting: ENV['to_formatting']
  }
  invoker = RedmineReformat::Invoker.new(opts)
  print_reformat_setup_summary(STDERR, invoker, opts[:converters_json])
  invoker.run
end

def setup_logger()
  Rails.logger = Logger.new(STDERR, level: Logger::INFO)
end

def print_reformat_setup_summary(io, invoker, converters_json)
  convcfg = JSON.parse(converters_json) if converters_json
  convcfg = if convcfg
    JSON.pretty_generate(convcfg)
  else
    '(use default converters)'
  end
  to_formatting = invoker.to_formatting || '(keep text_formatting setting)'
  io.puts "Running Redmine Reformat"
  io.puts "- to_formatting: #{to_formatting}"
  io.puts "- dryrun: #{invoker.dryrun}"
  io.puts "- converters: #{convcfg}"
  io.puts "- workers: #{invoker.workers}"
end
