# frozen_string_literal: true

require 'set'
require 'open3'
require 'tempfile'
require 'timeout'
require 'textile_to_markdown/redmine_reformat'

module TextileToMarkdown
  class ConvertString


    # receives textile, returns markdown
    def self.call(textile, reference = nil)
      new(textile, reference).call
    end

    def initialize(textile, reference = nil)
      @textile = textile.dup
      @reference = reference
      @placeholders = []
    end

    def call
      return String.new if @textile.empty?
      pre_process_textile @textile

      command = [
        'pandoc',
        '--wrap=preserve',
        '-f',
        'textile-smart',
        '-t',
        'gfm'
      ]

      output = exec_with_timeout(command.join(' '), stdin: @textile)
      post_process_markdown output
    end

    private
    include TextileToMarkdown::RedmineReformat

    def pre_process_textile(textile)

      clean_white_space textile
      initialize_reformatter textile, @reference

      # Do not interfere with protected blocks
      rip_offtags textile, false, false
      rip_macros textile
      unindent_pre_offtag textile
      # Move the class from <code> to <pre> and remove <code>, so pandoc can generate a code block with correct language
      merge_pre_code_offtags textile

      no_textile textile
      escape_html_tags textile
      block_textile_quotes textile

      # strip surrounding whitespace, which is allowed by Redmine, but would break further processing
      # temprarily placeholderize at the same time to avoid confusion with 'free qtags'
      normalize_hr_to_phs textile

      # make sure that empty lines mean new block
      glue_indented_continuations textile

      # extrect indented code and unindent lists
      process_indented_blocks textile

      # replace hard line breaks temporarily to support @multiline code@ and avoid "multi line":links
      hard_break textile
      inline_textile_link textile # avoid misinterpeation of invalid link-like sequences
      inline_textile_code textile # offtagize inline code
      revert_hard_break textile

      # all non-interpreted sections are offtagized now
      protect_offtag_contents

      ## Redmine-interpreted sequences
      protect_wiki_links textile
      normalize_lists_to_phs textile

      ## Textile sequences
      # Tables
      protect_pipes_in_tables textile
      drop_unsupported_table_features textile
      guess_table_headers textile
      pad_table_cells textile

      process_textile_prefix_blocks textile

      # make placeholderes from real qtags
      hard_break textile
      inline_textile_span_to_phs textile
      revert_hard_break textile

      # protect qtag characters that pandoc tend to misinterpret
      # has to be done after unindenting and protecting qtag chars in all semantic contexts
      protect_autolinks textile
      protect_qtag_chars textile
      protect_qtag_surroundings textile

      # finished with qtag caracters
      restore_real_qtags textile

      ## restore constructs that use qtag characters
      restore_textile_lists textile
      restore_textile_hrs textile

      # pandoc does not interpret html entities directly following a word
      put_breaks_before_html_entities textile

      # backslash-escaped issue links are ugly and escaped hash can break links
      protect_hashes textile

      # Force <pre> to have a blank line before them in lists
      # Without this fix, a list of items containing <pre> would not be interpreted as a list at all.
      put_blank_line_before_pre_in_list textile

      textile_footnote_refs textile

      # Avoid converting some symbols into special characters
      protect_symbols textile

      # Prefer inline code using backtics over code html tag (code is already protected as an offtag)
      prefer_inline_code_over_html textile

      # prevent sequences of = to be interpreted as <notextile>, see RedmineReformat#no_textile
      protect_eq_sequences textile

      smooth_offtags textile
      textile
    end


    def post_process_markdown(markdown)

      restore_protected_line_breaks markdown
      # TODO: Hopefuly can be deleted
      # Reclaim known placeholder sparations
      #markdown.gsub!(/\.(?<ph>B(?<flavour>any|escatstart|escoutword)#{PH_RE}E\k<flavour>)(?<mis2>[)])\./) do
      #  ".#{$~[:ph]}.#{$~[:mis2]}"
      #end
      restore_context_free_placeholders markdown
      restore_qtag_chars_to_md markdown
      md_footnotes markdown
      md_remove_auxiliary_code_block_lang markdown
      # see http://www.redmine.org/issues/20497
      md_separate_lists_redmine_friendly markdown
      # Restore/unescaping sequences that are protected differently in code blocks
      md_polish_before_code_restore markdown
      # Replace code and link placeholders *after* playing with the text
      restore_aftercode_placeholders markdown
      smooth_macros markdown
      normalize_and_rip_fenced_code_blocks markdown
      md_use_redmine_underline markdown
      # This should be the very last thing to break text length in table
      remove_init_breakers markdown
      md_reformat_tables markdown
      smooth_fenced_code_blocks markdown
      # restore placeholders preserving text length
      restore_after_table_reformat_placeholders markdown
      expand_blockqutes markdown

      finalize_reformatter markdown
      markdown
    end

    def exec_with_timeout(cmd, timeout: 10, stdin:)
      pid = nil
      result = nil

      begin
        Timeout.timeout(timeout) do
          Open3.popen2(cmd) do |i, o, t|
            pid = t.pid
            (i << stdin).close
            result = o.read
          end
        end
      rescue Timeout::Error
        Process.kill(-9, pid)
        Process.detach(pid)
        STDERR.puts 'timeout'
      end

      result
    end
  end

end
