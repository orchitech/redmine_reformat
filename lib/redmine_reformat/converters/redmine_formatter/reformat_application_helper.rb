# frozen_string_literal: true

require 'singleton'
require 'action_view'
require 'json'
require 'application_helper'

module RedmineReformat::Converters::RedmineFormatter

  class ReformatApplicationHelper
    include Singleton
    include ERB::Util
    include ActionView::Helpers::TextHelper
    include ActionView::Helpers::SanitizeHelper
    include ActionView::Helpers::UrlHelper
    include Rails.application.routes.url_helpers
    include ApplicationHelper

    def initialize
      User.current = nil
      unless ApplicationHelper.included_modules.include? ApplicationHelperPatch
        ApplicationHelper.send(:include, ApplicationHelperPatch)
      end
    end
  end

  module ApplicationHelperPatch
    def self.included(base)
      base.send(:include, InstanceMethods)
      base.class_eval do
        alias_method :parse_redmine_links, :dummy_parse_links
        alias_method :parse_wiki_links, :dummy_parse_links
        alias_method :catch_macros, :dummy_catch_macros
        alias_method :replace_toc, :dummy_replace_toc

        attr_accessor :reformat_opts

        # make macros rendered as
        # <code>[!]{{</code><code>"body as json string"</code><code>}}</code>
        def reformat_catch_macros_encode(text)
          text.gsub!(ApplicationHelper::MACROS_RE) do
            all, macro = $1, $4.downcase
            if macro_exists?(macro) || all =~ ApplicationHelper::MACRO_SUB_RE
              # rather re-match own regexp to make group references less fragile
              all.sub(/\A(!?\{\{)(.*)(\}\})\Z/m) do
                op, body, cl = $~[1..3]
                wop = reformat_delim_code_wrap(op)
                wbody = reformat_code_wrap(reformat_enc_macro_body(body))
                wcl = reformat_delim_code_wrap(cl)
                "#{wop}#{wbody}#{wcl}"
              end
            else
              all
            end
          end
          {}
        end

        def reformat_enc_macro_body(text)
          text.to_json.gsub(/[\p{Space}@`<>]/m) do |c|
            c.codepoints.map{|p| sprintf('\\u%04X', p)}.join('')
          end
        end

        def reformat_code_wrap(str)
          cl = nil
          op = case Setting.text_formatting
          when 'textile'
            '@'
          when 'markdown', 'common_mark', 'commonmark'
            '`'
          else
            cl = '</code>'
            '<code>'
          end
          cl = cl || op
          "#{op}#{str}#{cl}"
        end

        def reformat_delim_code_wrap(str)
          tag = case Setting.text_formatting
          when 'markdown'
            # Redcarpet in default Redmine config eats <code> tag
            # Consumers should deal with nested <code> for custom Redcarpet config
            '`'
          else
            ''
          end
          "<code>#{tag}#{str}#{tag}</code>"
        end
      end
    end

    module InstanceMethods
      def dummy_parse_links(text, project, obj, attr, only_path, options)
        # keep link-like constructs untouched
      end

      def dummy_catch_macros(text)
        case reformat_opts[:macros]
        when :encode
          reformat_catch_macros_encode(text)
        when :keep
          {}
        else
          raise "RedmineFormatter: invalid 'macros' option value: '#{reformat_opts[:macros]}'"
        end
      end

      def dummy_replace_toc(text, headings)
        # keep toc macro unexpanded
      end
    end
  end
end
