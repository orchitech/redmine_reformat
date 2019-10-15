require 'application_helper'

module TextileToMarkdown
  module ApplicationHelperPatch
    def self.included(base)
      base.send(:include, InstanceMethods)
      base.class_eval do
        alias_method :parse_redmine_links, :dummy_parse_links
        alias_method :parse_wiki_links, :dummy_parse_links
        alias_method :catch_macros, :dummy_catch_macros
        alias_method :replace_toc, :dummy_replace_toc
      end
    end
    module InstanceMethods
      def dummy_parse_links(text, project, obj, attr, only_path, options)
        # keep link-like constructs untouched
      end
      def dummy_catch_macros(text)
        # overlook all macros
        {}
      end
      def dummy_replace_toc(text, headings)
        # keep toc macro unexpanded
      end
    end
  end
end
