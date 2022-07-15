# frozen_string_literal: true

module AbideDevUtils
  # Formats text for output in markdown
  class Markdown
    def initialize(file, with_toc: true)
      @file = file
      @with_toc = with_toc
      @toc = ["## Table of Contents\n"]
      @body = []
      @title = nil
    end

    def to_markdown
      toc = @toc.join("\n")
      body = @body.join("\n")
      "#{@title}\n#{toc}\n\n#{body}"
    end

    def to_file
      File.write(@file, to_markdown)
    end

    def method_missing(name, *args, &block)
      if name.to_s.start_with?('add_')
        add(name.to_s.sub('add_', '').to_sym, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      name.to_s.start_with?('add_') || super
    end

    def title(text)
      "# #{text}\n"
    end

    def h1(text)
      "## #{text}\n"
    end

    def h2(text)
      "### #{text}\n"
    end

    def h3(text)
      "#### #{text}\n"
    end

    def ul(text, indent: 0)
      indented_text = []
      indent.times { indented_text << '  ' } if indent.positive?

      indented_text << "* #{text}"
      indented_text.join
    end

    def bold(text)
      "**#{text}**"
    end

    def italic(text)
      "*#{text}*"
    end

    def link(text, url, anchor: false)
      url = anchor(url) if anchor
      "[#{text}](#{url.downcase})"
    end

    def code(text)
      "\`#{text}\`"
    end

    def code_block(text, language: nil)
      language.nil? ? "```\n#{text}\n```" : "```#{language}\n#{text}\n```"
    end

    def anchor(text)
      "##{text.downcase.gsub(%r{\s|_}, '-').tr('.,\'"()', '')}"
    end

    private

    def add(type, text, *args, **kwargs)
      @toc << ul(link(text, text, anchor: true), indent: 0) if @with_toc && type == :h1

      case type.to_sym
      when :title
        @title = title(text)
      when :ul
        @body << ul(text, indent: kwargs.fetch(:indent, 0))
      when :link
        @body << link(text, args.first, anchor: kwargs.fetch(:anchor, false))
      when :code_block
        @body << code_block(text, language: kwargs.fetch(:language, nil))
      else
        @body << send(type, text)
      end
    end
  end
end
