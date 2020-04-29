# frozen_string_literal: true

module RedmineReformat
  class Context
    attr_accessor :from_formatting, :to_formatting
    attr_accessor :klass, :item
    attr_accessor :id, :project_id
    attr_accessor :vals
    attr_writer :project, :ref

    @@project_cache = nil

    def initialize(**kwargs)
      kwargs.each do |key, value|
        send("#{key}=", value)
      end
    end

    def project
      return nil if @project_id.nil? || @project_id.zero?
      if @@project_cache
        @@project_cache[@project_id]
      else
        Project.find(@project_id)
      end
    end

    def ref
      @ref || "#{@item}\##{id}"
    end

    def to_s
      ref
    end

    def self.with_cached_projects(&block)
      current = @@project_cache
      begin
        @@project_cache = Hash[Project.all.map{|p| [p.id, p]}]
        block.call
      ensure
        @@project_cache = current
      end
    end
  end
end
