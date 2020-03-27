# frozen_string_literal: true

module RedmineReformat
  # Adopted from https://github.com/a-ono/redmine_per_project_formatting
  module SettingPatch
    def text_formatting
      current_text_formatting || super
    end

    def current_text_formatting
      Thread.current[:current_text_formatting]
    end

    def current_text_formatting=(format)
      Thread.current[:current_text_formatting] = format
    end

    def with_text_formatting(format, &block)
      current = current_text_formatting
      begin
        self.current_text_formatting = format
        block.call
      ensure
        self.current_text_formatting = current
      end
    end
  end
end
