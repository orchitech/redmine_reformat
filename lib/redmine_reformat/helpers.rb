# frozen_string_literal: true

require_relative 'helpers/reformat_application_helper'

module RedmineReformat
  module Helpers
    def with_application_helper(opts, ctx, metadata = {}, &block)
      helper = ReformatApplicationHelper.instance
      before_opts = helper.reformat_opts
      before_ctx = helper.reformat_ctx
      before_metadata = helper.reformat_metadata
      begin
        helper.reformat_opts = opts
        helper.reformat_ctx = ctx
        helper.reformat_metadata = metadata
        yield helper, metadata
      ensure
        helper.reformat_opts = before_opts
        helper.reformat_ctx = before_ctx
        helper.reformat_metadata = before_metadata
      end
    end
  end
end
