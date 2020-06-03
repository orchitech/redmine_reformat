# frozen_string_literal: true

require 'net/http/persistent'

module RedmineReformat::Converters::Ws
  class Converter
    def initialize(url, opts = {})
      @uri = URI(url)
      @http = Net::HTTP::Persistent.new name: url.to_s
      method = opts.fetch(:method, :PUT).to_sym
      @request_class = case method
      when :POST
        Net::HTTP::Post
      when :PUT
        Net::HTTP::Put
      else
        raise "Unsupported request method '#{method}'."
      end
    end

    # convert by posting to a web service and reading the response
    def convert(text, ctx = nil)
      reference = ctx && ctx.ref
      req = @request_class.new(@uri)
      req['Content-Type'] = 'text/plain; charset=UTF-8'
      req.body = text
      res = @http.request @uri, req
      unless res.code == '200'
        raise "Request to #{@uri} failed for '#{reference}' [code=#{res.code}, msg=#{res.msg}]."
      end
      res.body
    end
  end
end
