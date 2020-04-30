# frozen_string_literal: true

require 'singleton'
require 'action_view'
require 'json'
require 'application_helper'

module RedmineReformat::Helpers
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
        alias_method :parse_redmine_links, :reformat_parse_redmine_links
        alias_method :parse_wiki_links, :reformat_parse_wiki_links
        alias_method :inject_macros, :reformat_inject_macros
        alias_method :replace_toc, :dummy_replace_toc
        attr_accessor :reformat_opts, :reformat_metadata
        attr_reader :reformat_ctx

        def reformat_ctx=(ctx)
          @reformat_ctx = ctx
          @project = ctx && ctx.project
        end

        # make macros rendered as
        # <code>[!]{{</code><code>"body as json string"</code><code>}}</code>
        def reformat_enc_macro(full_macro)
          # rather re-match own regexp to make group references less fragile
          full_macro.sub(/\A(!?\{\{)(.*)(\}\})\Z/m) do
            op, body, cl = $~[1..3]
            wop = reformat_code_wrap(op)
            wbody = reformat_code_wrap(reformat_enc_macro_body(body))
            wcl = reformat_code_wrap(cl)
            "#{wop}#{wbody}#{wcl}"
          end
        end

        def reformat_enc_macro_body(text)
          text.to_json.gsub(/[\p{Space}@`<>]/m) do |c|
            c.codepoints.map{|p| sprintf('\\u%04X', p)}.join('')
          end
        end

        def reformat_code_wrap(str)
          "<code>#{h(str)}</code>"
        end
      end
    end

    module InstanceMethods

      # No use case atm => not yet implemented
      REFORMAT_PARSE_REDMINE_LINKS_SUPPORT = false

      def reformat_parse_redmine_links(text, default_project, obj, attr, only_path, options)
        return unless REFORMAT_PARSE_REDMINE_LINKS_SUPPORT
        text.gsub!(ApplicationHelper::LINKS_RE) do |_|
          tag_content = $~[:tag_content]
          leading = $~[:leading]
          esc = $~[:esc]
          project_prefix = $~[:project_prefix]
          project_identifier = $~[:project_identifier]
          prefix = $~[:prefix]
          repo_prefix = $~[:repo_prefix]
          repo_identifier = $~[:repo_identifier]
          sep = $~[:sep1] || $~[:sep2] || $~[:sep3] || $~[:sep4]
          identifier = $~[:identifier1] || $~[:identifier2] || $~[:identifier3]
          comment_suffix = $~[:comment_suffix]
          comment_id = $~[:comment_id]

          if tag_content
            $&
          else
            link = nil
            if esc.nil?
              if prefix.nil? && sep == 'r'
                link = true
              elsif sep == '#' || sep == '##'
                oid = identifier.to_i
                case prefix
                when nil
                  if oid.to_s == identifier
                    link = true
                  elsif identifier == 'note'
                    link = true
                  end
                when 'document', 'version', 'message', 'forum', 'news', 'project', 'user'
                  link = true
                end
              elsif sep == ':'
                case prefix
                when 'document', 'version', 'forum', 'news', 'commit', 'source', 'export', 'attachment', 'project', 'user'
                    link = true
                end
              elsif sep == "@"
                link = true
              end
            end
            if link || esc
              thelink = "#{esc}#{project_prefix}#{prefix}#{repo_prefix}#{sep}#{identifier}#{comment_suffix}"
            end
            $&
          end
        end
      end

      def reformat_parse_wiki_links(text, project, obj, attr, only_path, options)
        mark_re = reformat_opts[:wiki_link_mark_re]
        return if mark_re.nil?
        reformat_metadata[:wiki_links] ||= Hash.new {|h, k| h[k] = {}}
        wiki_links = reformat_metadata[:wiki_links]

        text.scan(/(!)?(\[\[([^\n\|]+?)(\|([^\n\|]+?))?\]\])/) do
          esc, all, page, title = $1, $2, $3, $5
          link_project = project
          page = CGI.unescapeHTML(page)

          mark = page.match(mark_re) do |m|
            page = m.pre_match + m.post_match
            m[1]
          end
          next unless mark

          wiki_link = wiki_links[mark]
          wiki_link[:title] = title
          if project
            wiki_link[:project_id] = project.id
            wiki_link[:project_identifier] = project.identifier
          end

          if esc
            wiki_links[:type] = :escaped
            wiki_links[:esc] = esc
            next
          end

          if page =~ /^\#(.+)$/
            wiki_link[:type] = :anchor
            wiki_link[:anchor] = page
            next
          end

          # project-qualified link
          if page =~ /^([^\:]+)\:(.*)$/
            identifier, page = $1, $2
            link_project = Project.find_by_identifier(identifier) || Project.find_by_name(identifier)
            wiki_link[:link_project_identifier] = identifier
            wiki_link[:link_project_literal] = identifier
          end

          # extract anchor
          if page =~ /^(.+?)\#(.+)$/
            page, anchor = $1, $2
            wiki_link[:anchor] = anchor
          end

          wiki_link[:page] = page
          if link_project
            wiki_link[:link_project_id] = link_project.id
            wiki_link[:link_project_identifier] = link_project.identifier
          end

          unless link_project && link_project.wiki
            wiki_link[:type] = :invalid_project
            next
          end

          wiki_page = link_project.wiki.find_page(page)
          if wiki_page
            wiki_link[:type] = :valid
          else
            wiki_link[:type] = :invalid_page
          end
        end
      end

      def reformat_inject_macros(text, obj, macros, execute=true, options={})
        text.gsub!(ApplicationHelper::MACRO_SUB_RE) do
          all, index = $1, $2.to_i
          orig = macros.delete(index)
          if execute && orig && orig =~ ApplicationHelper::MACROS_RE
            esc, all, macro, args, block = $2, $3, $4.downcase, $6.to_s, $7.try(:strip)
            # TODO: make this configurable
            if esc.nil? && macro == 'collapse'
              exec_macro_args = [macro, obj, args, block]
              # redmine < 4.1 compatibility
              exec_macro_args << options unless options.nil? || options.empty?
              h(exec_macro(*exec_macro_args) || all)
            else
              case reformat_opts[:macros]
              when :encode
                "#{esc}#{reformat_enc_macro(all)}"
              when :keep
                h(all)
              else
                raise "RedmineFormatter: invalid 'macros' option value: '#{reformat_opts[:macros]}'"
              end
            end
          elsif orig
            h(orig)
          else
            h(all)
          end
        end
      end

      def dummy_replace_toc(text, headings)
        # keep toc macro unexpanded
      end
    end
  end
end
