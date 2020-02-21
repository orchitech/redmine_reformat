# frozen_string_literal: true

require 'net/http/persistent'

module RedmineReformat::Converters::Ws
  class Converter
    def initialize(url)
      @uri = URI(url)
      @http = Net::HTTP::Persistent.new name: url.to_s
      @http.retry_change_requests = true
    end

    # convert by posting to a web service and reading the response
    def convert(text, reference = nil)
      req = Net::HTTP::Post.new(@uri)
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
