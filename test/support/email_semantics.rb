# encoding: UTF-8
require 'nokogiri'
require 'liquid'

module HtmlCompressor
  # What an email client sees after parsing, independent of byte layout.
  # Nokogiri::HTML5 follows the WHATWG parser used by Gmail, Apple Mail and
  # browsers, so a comment boundary moved by compression shows up here.
  module EmailSemantics
    # Options BSFT passes in EmailTemplate#update_inlined_content, including its
    # nonstandard `<!--[if !mso><!-->` pattern, so these checks match production.
    BSFT_OPTIONS = {
      :compress_css => true,
      :remove_intertag_spaces => true,
      :preserve_patterns => [
        /\s?\{%.*?%\}\s?/im, /\s?\{\{.*?\}\}\s?/im,
        /<!--<!\[endif\]-->/im, /<!--\[if !mso><!-->/im, /<!-- End -->/im, /<!-->/im
      ]
    }.freeze

    BLOCK = %w[
      address article aside blockquote body br button caption center colgroup dd details dialog div dl dt
      fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hr html li main nav ol option p pre
      section select table tbody td textarea tfoot th thead tr ul
    ].freeze
    NO_TEXT = %w[head script style template title noscript].freeze
    FORMATTING = %w[a b big code em font i nobr s small strike strong tt u].freeze
    LIQUID = /\{%-?.*?-?%\}|\{\{.*?\}\}/m
    COLLAPSIBLE = /[ \t\n\r\f]+/

    module_function

    def of(html)
      document = Nokogiri::HTML5(html, :max_errors => 0)
      result = {
        :hrefs => [], :srcs => [], :styles => [], :outlook => [], :outlook_hrefs => 0,
        :tags => Hash.new(0), :alt_title => [], :liquid => html.scan(LIQUID)
      }
      stream = []
      walk(document, false, result, stream)
      result[:words] = stream.join.split(/[ \t\n\r\f\u0001]+/).reject(&:empty?)
      result[:hrefs].sort!
      result[:srcs].sort!
      result[:alt_title].sort!
      result[:liquid].sort!
      result
    end

    def walk(node, skip_text, result, stream)
      if node.comment?
        markers = outlook_markers(node.content)
        unless markers.empty?
          result[:outlook].concat(markers)
          result[:outlook_hrefs] += node.content.scan(/\bhref\s*=/i).length
        end
        return
      end
      if node.text?
        stream << node.content unless skip_text
        return
      end
      name = node.element? ? node.name.downcase : nil
      # The HTML5 adoption agency clones open formatting elements around
      # whitespace when blocks are nested inside them. Whitespace removal
      # changes the number of empty clones, not what the client shows.
      if name && FORMATTING.include?(name) && node.children.none? { |c| c.element? || (c.text? && !c.content.strip.empty?) }
        node.children.each { |child| walk(child, skip_text, result, stream) }
        return
      end
      if name
        result[:tags][name] += 1
        result[:hrefs] << node['href'].strip if name == 'a' && node['href']
        result[:srcs] << node['src'].strip if name == 'img' && node['src']
        %w[alt title].each { |attr| result[:alt_title] << "#{name}@#{attr}=#{node[attr].gsub(COLLAPSIBLE, ' ').strip}" if node[attr] }
        # Count, not bytes: CSS minification legitimately rewrites the body.
        result[:styles] << 'style' if name == 'style' && !node.content.strip.empty?
        skip_text ||= NO_TEXT.include?(name)
        stream << "\u0001" if BLOCK.include?(name)
      end
      node.children.each { |child| walk(child, skip_text, result, stream) }
      stream << "\u0001" if name && BLOCK.include?(name)
    end

    def outlook_markers(text)
      text = text.strip
      markers = []
      opener = text[/\A\[if[^\]]*\]>?/i]
      markers << "open:#{opener.downcase.gsub(/\s+/, ' ')}" if opener
      markers << 'close' if text =~ /(?:\A|<!)\[endif\]\z/i
      markers
    end

    # Liquid renders before HTML parsing at send time; BSFT's send path uses the
    # default lax error mode.
    def render(html, context)
      Liquid::Template.parse(html).render(context)
    end
  end
end
