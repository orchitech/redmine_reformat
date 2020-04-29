# frozen_string_literal: true

require 'webrick'
require 'redmine_reformat/converters'
require 'redmine_reformat/setting_patch'

module RedmineReformat
  class Microservice
    Converters = RedmineReformat::Converters
    ConfiguredConverters = RedmineReformat::Converters::ConfiguredConverters
    CTX_DEFAULTS = {
      item: 'microservice',
      id: 0,
      project_id: 0,
    }
    # request counter
    cattr_accessor :counter
    @@counter = 0

    def initialize(to_formatting: nil, converters_json: nil, port: 3030, from_formatting: nil, workers: 1)
      @port = port
      @converter = Converters::from_json(converters_json) if converters_json
      @converter ||= ConfiguredConverters.new(Execution::DEFAULT_CONVERTER_CONFIG)
      @convopts = {
        to_formatting: to_formatting,
        from_formatting: from_formatting,
      }
    end

    def run
      STDOUT.sync = true
      STDERR.sync = true
      self.class.apply_setting_patch
      start_webrick do |server|
        server.mount('/', MicroserviceServlet, @converter, @convopts)
      end
    end

    private
    def self.apply_setting_patch
      unless Setting.singleton_class.included_modules.include? SettingPatch
        Setting.singleton_class.prepend(SettingPatch)
      end
    end

    def start_webrick()
      server = WEBrick::HTTPServer.new({ Port: @port })
      yield server if block_given?
      ['INT', 'TERM'].each do |signal|
        trap(signal) { server.shutdown }
      end
      server.start
    end
  end

  class MicroserviceServlet < WEBrick::HTTPServlet::FileHandler
    HTTPStatus = WEBrick::HTTPStatus

    def initialize(server, converter, convopts)
      local_path = File.join(File.dirname(__FILE__), '../../assets/microservice')
      super(server, local_path)
      @converter = converter
      @params = convopts.merge(Microservice::CTX_DEFAULTS)
    end

    def do_POST(req, resp)
      p = ActiveSupport::HashWithIndifferentAccess.new(@params)
      params_override(p, WEBrick::HTTPUtils::parse_query(req.query_string))
      text = if req.content_type =~ /^application\/x-www-form-urlencoded/
        params_override(p, req.query)
        req.query['text']
      else
        req.body
      end
      raise HTTPStatus::BadRequest unless text && p[:to_formatting] && p[:from_formatting]
      Microservice.counter += 1
      ctx = Context.new(p.symbolize_keys)
      ctx.id = Microservice.counter if ctx.id.zero?
      converted = convert(text, ctx)
      raise HTTPStatus::NoContent unless converted
      resp['Content-Type'] = "text/plain; charset=UTF-8"
      resp.keep_alive = false
      resp.body = converted
    end

    private
    def params_override(params, override)
      params.merge! override.select { |k| params.keys.include?(k) }
      params[:id] = params[:id].to_i
      params[:project_id] = params[:project_id].to_i
    end

    def convert(text, ctx)
      converted = nil
      Project.transaction do
        Mailer.with_deliveries(false) do
          Setting.with_text_formatting(ctx.from_formatting) do
            converted = @converter.convert(text, ctx)
            raise ActiveRecord::Rollback
          end
        end
      end
      converted
    end
  end
end
