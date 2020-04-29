# frozen_string_literal: true

module RedmineReformat::Converters::LinkRewriter
  class Converter
    include RedmineReformat::Helpers
    Utils = RedmineReformat::Converters::Utils

    def initialize(wiki_link_rewrites)
      @wiki_link_rewrites = Hash[
        wiki_link_rewrites.map{|(k, v)| [Utils.to_i_or_s(k), v]}
      ]
      @mark_key = SecureRandom.hex(8)
      @wiki_link_mark_re = /#{@mark_key}-(\d+)-/
      @wiki_link_enc_mark_re = /#{@mark_key}&\#45;(\d+)&\#45;/
    end

    # returns HTML obtained from internal Redmine's formatter
    def convert(text, ctx)
      formatting = Setting.text_formatting
      lbrack = Utils.markup_char_re('[', formatting)
      rbrack = Utils.markup_char_re(']', formatting)
      colon = Utils.markup_char_re(':', formatting)

      # mark wiki link candidates with unique placeholders
      mark = 0
      text = text.gsub(/#{lbrack}{2}(?=[^\r\n\|])/) do |m|
        mark += 1
        "#{m}#{@mark_key}&#45;#{mark}&#45;"
      end

      # let renderer analyze wiki links
      helper_opts = {wiki_link_mark_re: @wiki_link_mark_re, macros: :keep}
      metadata = {}
      with_application_helper(helper_opts, ctx, metadata) do |helper|
        textilizable_opts = {only_path: true, headings: false}
        helper.textilizable(text, textilizable_opts)
      end
      wiki_links = metadata[:wiki_links]

      # perform rewriting
      text.gsub!(/(#{lbrack}{2})#{@wiki_link_enc_mark_re}([^\r\n]+?)(#{rbrack}{2})/) do
        op, mark, link, cl = $~[1..4]
        all = $&
        meta = wiki_links[mark]
        next all unless meta[:type] == :valid
        rewrite =
          @wiki_link_rewrites.fetch(meta[:link_project_id],
          @wiki_link_rewrites.fetch(meta[:link_project_identifier], nil))
        next all unless rewrite

        if meta[:link_project_literal]
          link.sub!(/^.*?#{colon}/, '')
        end
        link = "#{rewrite[:page_prefix]}#{link}"
        link_project = meta[:link_project_literal]
        link_project = rewrite[:project] if rewrite.key? :project
        project_sep = ':' if link_project
        "#{op}#{link_project}#{project_sep}#{link}#{cl}"
      end

      # clean up remaining wiki link marks
      text.gsub!(@wiki_link_enc_mark_re, '')
      text
    end
  end
end
