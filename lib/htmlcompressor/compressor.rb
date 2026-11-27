require "htmlcompressor/exceptions"

module HtmlCompressor
  class Compressor

    JS_COMPRESSOR_YUI = "yui";
    JS_COMPRESSOR_CLOSURE = "closure";

    # Predefined pattern that matches <code>&lt;?php ... ?></code> tags.
    # Could be passed inside a list to {@link #setPreservePatterns(List) setPreservePatterns} method.
    PHP_TAG_PATTERN = /<\?php.*?\?>/im

    # Predefined pattern that matches <code>&lt;% ... %></code> tags.
    # Could be passed inside a list to {@link #setPreservePatterns(List) setPreservePatterns} method.
    SERVER_SCRIPT_TAG_PATTERN = /<%.*?%>/m

    # Predefined pattern that matches <code>&lt;--# ... --></code> tags.
    # Could be passed inside a list to {@link #setPreservePatterns(List) setPreservePatterns} method.
    SERVER_SIDE_INCLUDE_PATTERN = /<!--\s*#.*?-->/m

    # Predefined list of tags that are very likely to be block-level.
    #Could be passed to {@link #setRemoveSurroundingSpaces(String) setRemoveSurroundingSpaces} method.
    BLOCK_TAGS_MIN = "html,head,body,br,p"

    # Predefined list of tags that are block-level by default, excluding <code>&lt;div></code> and <code>&lt;li></code> tags.
    #Table tags are also included.
    #Could be passed to {@link #setRemoveSurroundingSpaces(String) setRemoveSurroundingSpaces} method.
    BLOCK_TAGS_MAX = BLOCK_TAGS_MIN + ",h1,h2,h3,h4,h5,h6,blockquote,center,dl,fieldset,form,frame,frameset,hr,noframes,ol,table,tbody,tr,td,th,tfoot,thead,ul"

    # Could be passed to {@link #setRemoveSurroundingSpaces(String) setRemoveSurroundingSpaces} method
    # to remove all surrounding spaces (not recommended).
    ALL_TAGS = "all"

    # temp replacements for preserved blocks
    TEMP_COND_COMMENT_BLOCK = "%%%~COMPRESS~COND~{0,number,#}~%%%"
    TEMP_PRE_BLOCK = "%%%~COMPRESS~PRE~{0,number,#}~%%%"
    TEMP_TEXT_AREA_BLOCK = "%%%~COMPRESS~TEXTAREA~{0,number,#}~%%%"
    TEMP_SCRIPT_BLOCK = "%%%~COMPRESS~SCRIPT~{0,number,#}~%%%"
    TEMP_STYLE_BLOCK = "%%%~COMPRESS~STYLE~{0,number,#}~%%%"
    TEMP_EVENT_BLOCK = "%%%~COMPRESS~EVENT~{0,number,#}~%%%"
    TEMP_LINE_BREAK_BLOCK = "%%%~COMPRESS~LT~{0,number,#}~%%%"
    TEMP_SKIP_BLOCK = "%%%~COMPRESS~SKIP~{0,number,#}~%%%"
    TEMP_USER_BLOCK = "%%%~COMPRESS~USER{0,number,#}~{1,number,#}~%%%"

    # compiled regex patterns
    EMPTY_PATTERN = Regexp.new("\\s")
    SKIP_PATTERN = Regexp.new("<!--\\s*\\{\\{\\{\\s*-->(.*?)<!--\\s*\\}\\}\\}\\s*-->", Regexp::MULTILINE | Regexp::IGNORECASE)
    OUTLOOK_COMMENT_OPENER = /<!--\[if\b[^\]]*\]>/i
    OUTLOOK_REVEAL_MARKER = /[ \t\r\n\f]*<!--(?:>|[ \t\r\n\f]*-->)/
    OUTLOOK_PADDED_END = /[ \t\r\n\f]+<!\[endif\]-->/i
    OUTLOOK_PADDED_CLOSER = /<!--#{OUTLOOK_PADDED_END}/
    # Keep the closing comment's opener in the revealed body so inline
    # whitespace is compressed the same way as with an unpadded closer.
    COND_COMMENT_END_PATTERN = /(?<=<!--)#{OUTLOOK_PADDED_END}|<!\[[^\]]+\]-->/im
    COND_COMMENT_PATTERN = /(<!(?:--)?\[[^\]]+?\]>(?:#{OUTLOOK_REVEAL_MARKER})?)(.*?)(#{COND_COMMENT_END_PATTERN})/im
    COMMENT_PATTERN = Regexp.new("<!---->|<!--[^\\[].*?-->", Regexp::MULTILINE | Regexp::IGNORECASE)
    # This is a prefilter only. An apparent comment can start in a quoted
    # attribute or raw-text body. Classify its boundaries before skipping it.
    PRESERVATION_COMMENT_CANDIDATE = /<!--(?!\[|<!\[endif\b)(?:-?>|.*?(?:--!?>|\z))/im
    HTML_TAG_TAIL = /(?:"[^"]*"|'[^']*'|[^"'<>])*>/
    PRESERVATION_BOUNDARY_PATTERN = /
      #{OUTLOOK_COMMENT_OPENER}(?:#{OUTLOOK_REVEAL_MARKER})?
      | #{OUTLOOK_PADDED_CLOSER}
      | <!--(?:<!\[endif\]-->|-?>)
      | <!--(?<comment>.*?)--!?>
      | \{\{.*?\}\} | \{%.*?%\}
      | <(?<raw>script|style|textarea|title|xmp|iframe|noembed|noframes|noscript)
        (?=[\s\/>])#{HTML_TAG_TAIL}(?<raw_body>.*?)<\/\k<raw>\s*>
      | <\/?[a-z][^\s\/<>"']*#{HTML_TAG_TAIL}
    /imx
    # Any conditional opener still present during comment removal can lack
    # a matching endif. Its first HTML comment terminator still matters.
    COMMENT_REMOVAL_BOUNDARY_PATTERN = Regexp.union(
      /#{OUTLOOK_COMMENT_OPENER}(?:#{OUTLOOK_REVEAL_MARKER}|.*?(?:--!?>|\z))/m,
      PRESERVATION_BOUNDARY_PATTERN
    )
    CONDITIONAL_HINT = /<!(?:--)?\[/
    EVENT_HINT = /\son[a-z]+\s*=\s*["']/i
    PRE_HINT = /<\/?pre/i
    SCRIPT_HINT = /<script/i
    STYLE_HINT = /<style/i
    TEXTAREA_HINT = /<textarea/i
    PRESERVATION_HINT = Regexp.union(CONDITIONAL_HINT, EVENT_HINT, PRE_HINT, SCRIPT_HINT, STYLE_HINT, TEXTAREA_HINT)
    COMMENT_JOIN_BOUNDARY = /(?:&[A-Za-z0-9#]*|<)(?=<!--)/
    INLINE_ELEMENTS = 'a|abbr|acronym|b|bdi|bdo|big|button|cite|code|data|del|dfn|em|font|i|img|input|ins|kbd|' \
      'label|mark|meter|nobr|output|picture|q|ruby|s|samp|select|small|span|strike|strong|sub|sup|time|tt|u|var|wbr'
    INTERTAG_PATTERN_TAG_TAG = /
      (?<left><\/?(?:#{INLINE_ELEMENTS})(?=[\s\/>])#{HTML_TAG_TAIL}|>)
      (?<space>\s+)(?=<(?:\/?(?<right>#{INLINE_ELEMENTS})(?=[\s\/>]))?)
    /ix
    # Outlook conditional blocks are invisible in HTML5 clients, so whitespace
    # between one and an inline element still separates the words around it.
    # Other preserved blocks keep the original tag-adjacent minification.
    INTERTAG_PATTERN_TAG_CUSTOM = /
      (?<left><\/?(?:#{INLINE_ELEMENTS})(?=[\s\/>])#{HTML_TAG_TAIL}|>)\s+(?=%%%~COMPRESS~(?<kind>[A-Z]+))
    /ix
    INTERTAG_PATTERN_CUSTOM_TAG = /
      (?<block>%%%~COMPRESS~(?<kind>[A-Z]+)\d*~\d+~%%%)\s+(?=<(?<right>\/?(?:#{INLINE_ELEMENTS})(?=[\s\/>]))?)
    /ix
    # Between two blocks, keep one space if either is a conditional: the
    # visible content on each side may be inline.
    INTERTAG_PATTERN_CUSTOM_CUSTOM = /
      (?<block>%%%~COMPRESS~(?<left>[A-Z]+)\d*~\d+~%%%)\s+(?=%%%~COMPRESS~(?<right>[A-Z]+))
    /x
    MULTISPACE_PATTERN = Regexp.new("\\s+", Regexp::MULTILINE | Regexp::IGNORECASE)
    QUOTED_URL_WHITESPACE_CANDIDATE = /\b(?:href|src)\s*=\s*(?:"[^"]*\s|'[^']*\s)/i
    HTML_START_TAG = /\A<[a-z][^\s\/<>"']*#{HTML_TAG_TAIL}/i
    HTML_ATTRIBUTE_WITH_VALUE = /
      (?<name>[^\s=<>"'\/]+)(?<assignment>\s*=\s*)(?:(?<quoted>"[^"]*"|'[^']*')|[^\s<>"']+)
    /x
    TAG_END_SPACE_PATTERN = Regexp.new("(<(?:[^>]+?))(?:\\s+?)(/?>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    TAG_LAST_UNQUOTED_VALUE_PATTERN = Regexp.new("=\\s*[a-z0-9\\-_]+$", Regexp::IGNORECASE)
    TAG_QUOTE_PATTERN = Regexp.new("\\s*=\\s*([\"'])([a-z0-9\\-_]+?)\\1(/?)(?=[^<]*?>)", Regexp::IGNORECASE)
    PRE_END_PATTERN = /<\/pre>/i
    PRE_PATTERN = /(<pre[^>]*?>)(.*?)(#{PRE_END_PATTERN})/im
    TA_PATTERN = Regexp.new("(<textarea[^>]*?>)(.*?)(</textarea>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    SCRIPT_PATTERN = Regexp.new("(<script[^>]*?>)(.*?)(</script>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    STYLE_PATTERN = Regexp.new("(<style[^>]*?>)(.*?)(</style>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    TAG_PROPERTY_PATTERN = Regexp.new("(\\s\\w+)\\s*=\\s*(?=[^<]*?>)", Regexp::IGNORECASE)
    CDATA_PATTERN = Regexp.new("\\s*<!\\[CDATA\\[(.*?)\\]\\]>\\s*", Regexp::MULTILINE | Regexp::IGNORECASE)
    DOCTYPE_PATTERN = Regexp.new("<!DOCTYPE[^>]*>", Regexp::MULTILINE | Regexp::IGNORECASE)
    TYPE_ATTR_PATTERN = Regexp.new("type\\s*=\\s*([\\\"']*)(.+?)\\1", Regexp::MULTILINE | Regexp::IGNORECASE)
    JS_TYPE_ATTR_PATTERN = Regexp.new("(<script[^>]*)type\\s*=\\s*([\"']*)(?:text|application)\/javascript\\2([^>]*>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    JS_LANG_ATTR_PATTERN = Regexp.new("(<script[^>]*)language\\s*=\\s*([\"']*)javascript\\2([^>]*>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    STYLE_TYPE_ATTR_PATTERN = Regexp.new("(<style[^>]*)type\\s*=\\s*([\"']*)text/(?:style|css)\\2([^>]*>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    LINK_TYPE_ATTR_PATTERN = Regexp.new("(<link[^>]*)type\\s*=\\s*([\"']*)text/(?:css|plain)\\2([^>]*>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    LINK_REL_ATTR_PATTERN = Regexp.new("<link(?:[^>]*)rel\\s*=\\s*([\"']*)(?:alternate\\s+)?stylesheet\\1(?:[^>]*)>", Regexp::MULTILINE | Regexp::IGNORECASE)
    FORM_METHOD_ATTR_PATTERN = Regexp.new("(<form[^>]*)method\\s*=\\s*([\"']*)get\\2([^>]*>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    INPUT_TYPE_ATTR_PATTERN = Regexp.new("(<input[^>]*)type\\s*=\\s*([\"']*)text\\2([^>]*>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    BOOLEAN_ATTR_PATTERN = Regexp.new("(<\\w+[^>]*[\"' ])(checked|selected|disabled|readonly)\\s*=\\s*([\"']*)\\w*\\3([^>]*>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    EVENT_JS_PROTOCOL_PATTERN = Regexp.new("^javascript:\\s*(.+)", Regexp::MULTILINE | Regexp::IGNORECASE)
    HTTP_PROTOCOL_PATTERN = Regexp.new("(<[^>]+?(?:href|src|cite|action)\\s*=\\s*['\"])http:(//[^>]+?>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    HTTPS_PROTOCOL_PATTERN = Regexp.new("(<[^>]+?(?:href|src|cite|action)\\s*=\\s*['\"])https:(//[^>]+?>)", Regexp::MULTILINE | Regexp::IGNORECASE)
    REL_EXTERNAL_PATTERN = Regexp.new("<(?:[^>]*)rel\\s*=\\s*([\"']*)(?:alternate\\s+)?external\\1(?:[^>]*)>", Regexp::MULTILINE | Regexp::IGNORECASE)
    EVENT_PATTERN1 = Regexp.new("(\\son[a-z]+\\s*=\\s*\")([^\"\\\\\\r\\n]*(?:\\\\.[^\"\\\\\\r\\n]*)*)(\")", Regexp::IGNORECASE) # unmasked: \son[a-z]+\s*=\s*"[^"\\\r\n]*(?:\\.[^"\\\r\n]*)*""
    EVENT_PATTERN2 = Regexp.new("(\\son[a-z]+\\s*=\\s*')([^'\\\\\\r\\n]*(?:\\\\.[^'\\\\\\r\\n]*)*)(')", Regexp::IGNORECASE)
    LINE_BREAK_PATTERN = Regexp.new("(?:[[:blank:]]*(\\r?\\n)[[:blank:]]*)+")
    SURROUNDING_SPACES_MIN_PATTERN = Regexp.new("\\s*(</?(?:" + BLOCK_TAGS_MIN.gsub(",", "|") + ")(?:>|[\\s/][^>]*>))\\s*", Regexp::MULTILINE | Regexp::IGNORECASE)
    SURROUNDING_SPACES_MAX_PATTERN = Regexp.new("\\s*(</?(?:" + BLOCK_TAGS_MAX.gsub(",", "|") + ")(?:>|[\\s/][^>]*>))\\s*", Regexp::MULTILINE | Regexp::IGNORECASE)
    SURROUNDING_SPACES_ALL_PATTERN = Regexp.new("\\s*(<[^>]+>)\\s*", Regexp::MULTILINE | Regexp::IGNORECASE)

    TEMP_BLOCK_PATTERN = /%%%~COMPRESS~(COND|PRE|TEXTAREA|SCRIPT|STYLE|EVENT|LT|SKIP|USER\d+)~(\d+)~%%%/
    TEMP_URL_VALUE_PATTERN = /%%%~COMPRESS~URL~(\d+)~%%%/
    AUTHORED_TOKEN_PATTERN = Regexp.union(TEMP_BLOCK_PATTERN, TEMP_URL_VALUE_PATTERN)

    JAVASCRIPT_COMPRESSORS_OPTIONS = {
      :closure => { :compilation_level => 'ADVANCED_OPTIMIZATIONS' },
      :yui => { :munge => true, :preserve_semicolons => true, :optimize => true, :line_break => nil }
    }

    CSS_COMPRESSORS_OPTIONS = {
      :yui => { :line_break => -1 }
    }

    DEFAULT_OPTIONS = {
      :enabled => true,

      # default settings
      :remove_comments => true,
      :remove_multi_spaces => true,
      :remove_spaces_inside_tags => true,

      # optional settings
      :javascript_compressor => :yui,
      :css_compressor => :yui,
      :remove_intertag_spaces => false,
      :remove_quotes => false,
      :compress_javascript => false,
      :compress_css => false,
      :simple_doctype => false,
      :remove_script_attributes => false,
      :remove_style_attributes => false,
      :remove_link_attributes => false,
      :remove_form_attributes => false,
      :remove_input_attributes => false,
      :simple_boolean_attributes => false,
      :remove_javascript_protocol => false,
      :remove_http_protocol => false,
      :remove_https_protocol => false,
      :preserve_line_breaks => false,
      :remove_surrounding_spaces => nil,

      :preserve_patterns => nil
    }

    def initialize(options = {})

      @options = DEFAULT_OPTIONS.merge(options)

      if @options[:compress_js_templates]
        @options[:remove_quotes] = false

        js_template_types = [ 'text/x-jquery-tmpl' ]

        unless @options[:compress_js_templates].is_a? TrueClass
          js_template_types << @options[:compress_js_templates]
          js_template_types.flatten!
        end

        @options[:js_template_types] = js_template_types
      else
        @options[:js_template_types] = []
      end

      detect_external_compressors
    end

    def detect_external_compressors
      @javascript_compressors = {}
      @css_compressors = {}

      # Try Closure.
      begin
        require 'closure-compiler'
        @javascript_compressors[:closure] = Closure::Compiler
      rescue LoadError
      end

      # Try YUI
      begin
        require 'yui/compressor'
        @javascript_compressors[:yui] = YUI::JavaScriptCompressor
        @css_compressors[:yui] = YUI::CssCompressor
      rescue LoadError
      end
    end

    def get_javascript_compressor(compressor_name)

      if @javascript_compressors.has_key? compressor_name
        @javascript_compressors[compressor_name].new JAVASCRIPT_COMPRESSORS_OPTIONS[compressor_name]
      end

    end

    def get_css_compressor(compressor_name)

      if @css_compressors.has_key? compressor_name
        @css_compressors[compressor_name].new CSS_COMPRESSORS_OPTIONS[compressor_name]
      end

    end

    def compress html
      if not @options[:enabled] or html.nil? or html.length == 0
        return html
      end
      # A literal token could be mistaken for a saved block during restoration.
      return html if AUTHORED_TOKEN_PATTERN.match?(html)

      # preserved block containers
      condCommentBlocks = []
      preBlocks = []
      taBlocks = []
      scriptBlocks = []
      styleBlocks = []
      eventBlocks = []
      skipBlocks = []
      lineBreakBlocks = []
      userBlocks = []

      # preserve blocks
      html = preserve_blocks(html, preBlocks, taBlocks, scriptBlocks, styleBlocks, eventBlocks, condCommentBlocks, skipBlocks, lineBreakBlocks, userBlocks)

      # process pure html
      html = process_html(html)

      # process preserved blocks
      process_preserved_blocks(preBlocks, taBlocks, scriptBlocks, styleBlocks, eventBlocks, condCommentBlocks, skipBlocks, lineBreakBlocks, userBlocks)

      # put preserved blocks back
      html = return_blocks(html, preBlocks, taBlocks, scriptBlocks, styleBlocks, eventBlocks, condCommentBlocks, skipBlocks, lineBreakBlocks, userBlocks)

      html
    end

    private

    def preservation_candidates(html)
      html.scan(PRESERVATION_COMMENT_CANDIDATE).select { |comment| PRESERVATION_HINT =~ comment }
    end

    def preserve_outside_comments(html, pattern, candidates, hint, closing_pattern = nil)
      unless candidates.any? { |comment| hint =~ comment }
        return html.gsub(pattern) { yield Regexp.last_match }
      end

      ranges = preservation_guard_ranges(html, hint)
      return html.gsub(pattern) { yield Regexp.last_match } if ranges.empty?

      result = html[0, 0]
      consumed = 0
      offset = 0
      range_index = 0
      while (match = pattern.match(html, offset))
        start = match.begin(0)
        range_index += 1 while ranges[range_index] && ranges[range_index].end <= start
        range = ranges[range_index]
        if range && range.cover?(start)
          # Retry after the comment. The rejected match may already include
          # the complete real block, so advancing to match.end loses it.
          offset = range.end
          next
        end

        block = match
        finish = match.end(0)
        if closing_pattern && range && range.begin <= match.begin(3)
          closer = match_outside_ranges(html, closing_pattern, match.begin(3), ranges, range_index)
          unless closer
            offset = match.end(1)
            next
          end
          if closer.begin(0) != match.begin(3)
            finish = closer.end(0)
            block = [html[start...finish], match[1], html[match.end(1)...closer.begin(0)], closer[0]]
          end
        end
        result << html[consumed...start] << yield(block)
        consumed = offset = finish
      end
      result << html[consumed..-1]
    end

    # Conditional and PRE bodies can contain ordinary HTML comments. Ignore
    # closing markers in those comments as well as false openers.
    def match_outside_ranges(html, pattern, offset, ranges, index)
      while (match = pattern.match(html, offset))
        start = match.begin(0)
        index += 1 while ranges[index] && ranges[index].end <= start
        range = ranges[index]
        return match unless range && range.cover?(start)

        offset = range.end
      end
      nil
    end

    def preservation_guard_ranges(html, hint)
      ranges = []
      html.to_enum(:scan, PRESERVATION_BOUNDARY_PATTERN).each do
        token = Regexp.last_match
        if token[:comment] && hint =~ token[:comment]
          ranges << (token.begin(0)...token.end(0))
        elsif hint == CONDITIONAL_HINT && OUTLOOK_PADDED_CLOSER.match?(token[0], 1)
          # A closer inside an opaque token is literal text. Skip the whole
          # token so a quoted attribute or raw body cannot end the branch.
          ranges << (token.begin(0)...token.end(0))
          next
        end
        raw_body = token[:raw_body]
        next unless raw_body && raw_body.include?('<!--')

        # In raw text, comment-looking text cannot consume a close marker
        # outside that element. These ranges are only for preservation.
        base = token.begin(:raw_body)
        raw_body.to_enum(:scan, /<!--.*?(?:--!?>|\z)/m).each do
          literal = Regexp.last_match
          if hint =~ literal[0]
            ranges << ((base + literal.begin(0))...(base + literal.end(0)))
          end
        end
      end
      ranges
    end

    def compress_conditional_body(compressor, opening, body)
      # A literal comment terminator inside an Outlook branch can expose the
      # rest of the branch to normal HTML clients. Keep that boundary intact.
      if opening.start_with?('<!--') && !opening.end_with?('-->') && (boundary = /--!?>/.match(body))
        offset = boundary.end(0)
        return body[0...offset] + compressor.compress(body[offset..-1])
      end

      compressor.compress(body)
    end

    def preserve_blocks(html, preBlocks, taBlocks, scriptBlocks, styleBlocks, eventBlocks, condCommentBlocks, skipBlocks, lineBreakBlocks, userBlocks)

      # preserve <!-- {{{ ---><!-- }}} ---> skip blocks
      skipBlockIndex = -1

      html = html.gsub(SKIP_PATTERN) do |match|
        if $1.strip.length > 0
          skipBlocks << match
          skipBlockIndex += 1
          message_format(TEMP_SKIP_BLOCK, skipBlockIndex)
        else
          match
        end
      end

      candidates = preservation_candidates(html)

      # preserve conditional comments
      condCommentCompressor = self.clone
      index = -1

      html = preserve_outside_comments(html, COND_COMMENT_PATTERN, candidates, CONDITIONAL_HINT, COND_COMMENT_END_PATTERN) do |match|
        if match[2].strip.length > 0
          index += 1
          compressed_body = compress_conditional_body(condCommentCompressor, match[1], match[2])
          condCommentBlocks << (match[1] + compressed_body + match[3])
          message_format(TEMP_COND_COMMENT_BLOCK, index)
        else
          ''
        end
      end

      # preserve inline events
      index = -1

      html = preserve_outside_comments(html, EVENT_PATTERN1, candidates, EVENT_HINT) do |match|
        if match[2].strip.length > 0
          eventBlocks << match[2]
          index += 1
          match[1] + message_format(TEMP_EVENT_BLOCK, index) + match[3]
        else
          ''
        end
      end

      html = preserve_outside_comments(html, EVENT_PATTERN2, candidates, EVENT_HINT) do |match|
        if match[2].strip.length > 0
          eventBlocks << match[2]
          index += 1
          match[1] + message_format(TEMP_EVENT_BLOCK, index) + match[3]
        else
          ''
        end
      end

      # preserve PRE tags
      index = -1
      html = preserve_outside_comments(html, PRE_PATTERN, candidates, PRE_HINT, PRE_END_PATTERN) do |match|
        if match[2].strip.length > 0
          index += 1
          preBlocks << match[2]
          match[1] + message_format(TEMP_PRE_BLOCK, index) + match[3]
        else
          ''
        end
      end

      # preserve SCRIPT tags
      index = -1

      html = preserve_outside_comments(html, SCRIPT_PATTERN, candidates, SCRIPT_HINT) do |match|
        group_1, group_2, group_3 = match.captures
        # ignore empty scripts
        if group_2.strip.length > 0
          # check type
          type = script_type(group_1)

          if type.length == 0 or type == 'text/javascript' or type == 'application/javascript'
            # javascript block, preserve and compress with js compressor
            scriptBlocks << group_2
            index += 1
            group_1 + message_format(TEMP_SCRIPT_BLOCK, index) + group_3
          elsif @options[:js_template_types].include?(type)
            # jquery template, ignore so it gets compressed with the rest of html
            match[0]
          else
            # some custom script, preserve it inside "skip blocks" so it won't be compressed with js compressor
            skipBlocks << group_2
            skipBlockIndex += 1
            group_1 + message_format(TEMP_SKIP_BLOCK, skipBlockIndex) + group_3
          end

        else
          match[0]
        end
      end

      # preserve STYLE tags
      index = -1

      html = preserve_outside_comments(html, STYLE_PATTERN, candidates, STYLE_HINT) do |match|
        if match[2].strip.length > 0
          styleBlocks << match[2]
          index += 1
          match[1] + message_format(TEMP_STYLE_BLOCK, index) + match[3]
        else
          match[0]
        end
      end

      # preserve TEXTAREA tags
      index = -1
      html = preserve_outside_comments(html, TA_PATTERN, candidates, TEXTAREA_HINT) do |match|
        index += 1

        if match[2].strip.length > 0
          taBlocks << match[2]
        else
          taBlocks << ''
        end

        match[1] + message_format(TEMP_TEXT_AREA_BLOCK, index) + match[3]
      end

      # preserve user blocks
      preservePatterns = @options[:preserve_patterns]
      unless (preservePatterns.nil?)
        preservePatterns.each_with_index do |preservePattern, i|
          userBlock = []
          index = -1

          html = html.gsub(preservePattern) do |match|
            if match.strip.length > 0
              userBlock << match
              index += 1
              message_format(TEMP_USER_BLOCK, i, index)
            else
              ''
            end
          end

          userBlocks << userBlock
        end
      end

      # preserve line breaks
      if @options[:preserve_line_breaks]
        index = -1
        html = html.gsub(LINE_BREAK_PATTERN) do |match|
          lineBreakBlocks << $1
          index += 1
          message_format(TEMP_LINE_BREAK_BLOCK, index)
        end
      end

      html
    end

    def return_blocks(html, preBlocks, taBlocks, scriptBlocks, styleBlocks, eventBlocks, condCommentBlocks, skipBlocks, lineBreakBlocks, userBlocks)
      blocks = {
        'COND' => condCommentBlocks, 'PRE' => preBlocks, 'TEXTAREA' => taBlocks,
        'SCRIPT' => scriptBlocks, 'STYLE' => styleBlocks, 'EVENT' => eventBlocks,
        'LT' => lineBreakBlocks, 'SKIP' => skipBlocks
      }
      userBlocks.each_with_index { |group, index| blocks["USER#{index}"] = group }

      # A preserved block can contain tokens from earlier passes. Resolve
      # those tokens when the block is restored, regardless of its type.
      restored = {}
      restore = lambda do |match|
        token = match[0]
        restored.fetch(token) do
          group = blocks[match[1]]
          content = group ? group.fetch(match[2].to_i, '') : ''
          # A custom minifier can emit token-shaped text. Guard against a
          # reference back to a block already being restored.
          restored[token] = token
          restored[token] = content.gsub(TEMP_BLOCK_PATTERN) { restore.call(Regexp.last_match) }
        end
      end
      html.gsub(TEMP_BLOCK_PATTERN) { restore.call(Regexp.last_match) }
    end

    def process_preserved_blocks(preBlocks, taBlocks, scriptBlocks, styleBlocks, eventBlocks, condCommentBlocks, skipBlocks, lineBreakBlocks, userBlocks)
      # processPreBlocks(preBlocks)
      # processTextAreaBlocks(taBlocks)
      process_script_blocks(scriptBlocks)
      process_style_blocks(styleBlocks)
      process_event_blocks(eventBlocks)
      # processCondCommentBlocks(condCommentBlocks)
      # processSkipBlocks(skipBlocks)
      # processUserBlocks(userBlocks)
      # processLineBreakBlocks(lineBreakBlocks)
    end

    def process_script_blocks(scriptBlocks)
      if @options[:compress_javascript]
        scriptBlocks.map! do |block|
          compress_javascript(block)
        end
      end
    end

    def process_style_blocks(styleBlocks)
      if @options[:compress_css]
        styleBlocks.map! do |block|
          compress_css_styles(block)
        end
      end
    end

    def process_event_blocks(eventBlocks)
      if @options[:remove_javascript_protocol]
        eventBlocks.map! do |block|
          remove_javascript_protocol(block)
        end
      end
    end

    def compress_javascript(source)
      # set default javascript compressor
      javascript_compressor = @options[:javascript_compressor]

      if javascript_compressor.is_a?(Symbol)
        javascript_compressor = get_javascript_compressor(javascript_compressor)
      end

      if javascript_compressor.nil?
        if @options[:javascript_compressor].is_a?(Symbol)
          raise NotFoundCompressorError, "JavaScript Compressor \"#{@options[:javascript_compressor]}\" not found, please check :javascript_compressor option"
        else
          raise MissingCompressorError, "No JavaScript Compressor. Please set the :javascript_compressor option"
        end
      end

      # detect CDATA wrapper
      cdataWrapper = false
      if source =~ CDATA_PATTERN
        cdataWrapper = true
        source = $1
      end

      result = javascript_compressor.compress(source).strip

      if cdataWrapper
        result = "/*<![CDATA[*/" + result + "/*]]>*/"
      end

      result
    end

    def compress_css_styles(source)
      # CSS minifiers can rewrite template expressions before they are rendered.
      preserve_patterns = @options[:preserve_patterns]
      return source if preserve_patterns && preserve_patterns.any? { |pattern| source[pattern] }

      # set default css compressor
      css_compressor = @options[:css_compressor]

      if css_compressor.is_a?(Symbol)
        css_compressor = get_css_compressor(css_compressor)
      end

      if css_compressor.nil?
        if @options[:css_compressor].is_a?(Symbol)
          raise NotFoundCompressorError, "CSS Compressor \"#{@options[:css_compressor]}\" not found, please check :css_compressor option"
        else
          raise MissingCompressorError, "No CSS Compressor. Please set the :css_compressor option"
        end
      end

      # detect CDATA wrapper
      original = source
      cdataWrapper = false
      if source =~ CDATA_PATTERN
        cdataWrapper = true
        source = $1
      end

      result = css_compressor.compress(source)
      # YUI can return UTF-8 bytes tagged as US-ASCII or binary.
      if !result.ascii_only? && [Encoding::US_ASCII, Encoding::BINARY].include?(result.encoding)
        result = result.dup.force_encoding(source.encoding)
      end
      return original unless result.valid_encoding?

      if cdataWrapper
        result = "<![CDATA[" + result + "]]>"
      end

      result
    end

    def remove_javascript_protocol(source)
      # remove javascript: from inline events
      source.sub(EVENT_JS_PROTOCOL_PATTERN, '\1')
    end

    def process_html(html)

      # remove comments
      html = remove_comments(html)

      # simplify doctype
      html = simple_doctype(html)

      # remove script attributes
      html = remove_script_attributes(html)

      # remove style attributes
      html = remove_style_attributes(html)

      # remove link attributes
      html = remove_link_attributes(html)

      # remove form attributes
      html = remove_form_attributes(html)

      # remove input attributes
      html = remove_input_attributes(html)

      # simplify boolean attributes
      html = simple_boolean_attributes(html)

      # remove http from attributes
      html = remove_http_protocol(html)

      # remove https from attributes
      html = remove_https_protocol(html)

      # A tab or newline in a URL is discarded by URL parsers. Replacing it
      # with a space, or changing existing spaces in the value, can change
      # the destination. Shield values from the whitespace passes below.
      url_values = []
      html = preserve_quoted_url_values(html, url_values)

      # remove inter-tag spaces
      html = remove_intertag_spaces(html)

      # remove multi whitespace characters
      html = remove_multi_spaces(html)

      # remove spaces around equals sign and ending spaces
      html = remove_spaces_inside_tags(html)

      # remove quotes from tag attributes
      html = remove_quotes_inside_tags(html)

      # # remove surrounding spaces
      html = remove_surrounding_spaces(html)

      unless url_values.empty?
        html = html.gsub(TEMP_URL_VALUE_PATTERN) { url_values.fetch(Regexp.last_match(1).to_i) }
      end
      html.strip
    end

    def preserve_quoted_url_values(html, url_values)
      return html unless QUOTED_URL_WHITESPACE_CANDIDATE.match?(html)

      html.gsub(COMMENT_REMOVAL_BOUNDARY_PATTERN) do |fragment|
        next fragment unless QUOTED_URL_WHITESPACE_CANDIDATE.match?(fragment)

        fragment.sub(HTML_START_TAG) do |tag|
          tag.gsub(HTML_ATTRIBUTE_WITH_VALUE) do |text|
            attribute = Regexp.last_match
            quoted = attribute[:quoted]
            next text unless quoted && %w[href src].include?(attribute[:name].downcase) &&
              MULTISPACE_PATTERN.match?(quoted)

            marker = "%%%~COMPRESS~URL~#{url_values.length}~%%%"
            url_values << quoted[1...-1]
            attribute[:name] + attribute[:assignment] + quoted[0] + marker + quoted[-1]
          end
        end
      end
    end

    def remove_comments(html)
      return html unless @options[:remove_comments] && html.include?('<!--')

      # Match byte offsets so scanning the tags stays linear for UTF-8 copy.
      source = html.b
      last_comment = source.rindex('<!--')
      # Removing some comments would join a character reference or a tag
      # opener. Keeping those comments preserves the rendered text.
      join_boundaries = {}
      source.to_enum(:scan, COMMENT_JOIN_BOUNDARY).each do
        join_boundaries[Regexp.last_match.end(0)] = true
      end

      result = html.byteslice(0, 0)
      consumed = 0
      source.to_enum(:scan, COMMENT_REMOVAL_BOUNDARY_PATTERN).each do
        token = Regexp.last_match
        start = token.begin(0)
        break if start > last_comment

        if token[:comment] && removable_comment?(token[:comment]) && !join_boundaries[start]
          result << html.byteslice(consumed...start)
          consumed = token.end(0)
        elsif token[:raw] && token[:raw].casecmp('script') == 0 && !@options[:js_template_types].empty?
          body_start = token.begin(:raw_body)
          body_end = token.end(:raw_body)
          opening_tag = html.byteslice(start...body_start)
          if @options[:js_template_types].include?(script_type(opening_tag))
            result << html.byteslice(consumed...body_start) << remove_comments(html.byteslice(body_start...body_end))
            consumed = body_end
          end
        end
      end
      result << html.byteslice(consumed..-1)
    end

    def removable_comment?(comment)
      return false if comment.start_with?('[')

      # A nested opener can make a trailing Outlook delimiter ambiguous.
      !(comment.include?('<!--') && /<!\[endif\]\z/i =~ comment)
    end

    def script_type(opening_tag)
      type = TYPE_ATTR_PATTERN.match(opening_tag)
      type ? type[2].downcase : ''
    end

    def simple_doctype(html)
      # simplify doctype
      if @options[:simple_doctype]
        html = html.gsub(DOCTYPE_PATTERN, '<!DOCTYPE html>')
      end

      html
    end

    def remove_script_attributes(html)
      if @options[:remove_script_attributes]
        #remove type from script tags
        html = html.gsub(JS_TYPE_ATTR_PATTERN, '\1\3')

        #remove language from script tags
        html = html.gsub(JS_LANG_ATTR_PATTERN, '\1\3')
      end

      html
    end

    def remove_style_attributes(html)
      # remove type from style tags
      if @options[:remove_style_attributes]
        html = html.gsub(STYLE_TYPE_ATTR_PATTERN, '\1\3')
      end

      html
    end

    def remove_link_attributes(html)
      # remove type from link tags with rel=stylesheet
      if @options[:remove_link_attributes]
        html = html.gsub(LINK_TYPE_ATTR_PATTERN) do |match|
          group_1 = $1
          group_3 = $3
          # if rel=stylesheet
          if match =~ LINK_REL_ATTR_PATTERN
            group_1 + group_3
          else
            match
          end
        end
      end

      html
    end

    def remove_form_attributes(html)
      # remove method from form tags
      if @options[:remove_form_attributes]
        html = html.gsub(FORM_METHOD_ATTR_PATTERN, '\1\3')
      end

      html
    end

    def remove_input_attributes(html)
      # remove type from input tags
      if @options[:remove_input_attributes]
        html = html.gsub(INPUT_TYPE_ATTR_PATTERN, '\1\3')
      end

      html
    end

    def remove_http_protocol(html)
      # remove http protocol from tag attributes
      if @options[:remove_http_protocol]
        html = html.gsub(HTTP_PROTOCOL_PATTERN) do |match|
          group_1 = $1
          group_2 = $2

          if match =~ REL_EXTERNAL_PATTERN
            match
          else
            "#{group_1}#{group_2}"
          end
        end
      end

      html
    end

    def remove_https_protocol(html)
      # remove https protocol from tag attributes
      if @options[:remove_https_protocol]
        html = html.gsub(HTTPS_PROTOCOL_PATTERN) do |match|
          group_1 = $1
          group_2 = $2

          if match =~ REL_EXTERNAL_PATTERN
            match
          else
            "#{group_1}#{group_2}"
          end
        end
      end

      html
    end

    def remove_intertag_spaces(html)

      # remove inter-tag spaces
      if @options[:remove_intertag_spaces]
        html = html.gsub(INTERTAG_PATTERN_TAG_TAG) do
          match = Regexp.last_match
          left = match[:left]
          left != '>' && match[:right] ? left + match[:space] : left
        end
        html = html.gsub(INTERTAG_PATTERN_TAG_CUSTOM) do
          match = Regexp.last_match
          match[:kind] == 'COND' && match[:left] != '>' ? match[:left] + ' ' : match[:left]
        end
        html = html.gsub(INTERTAG_PATTERN_CUSTOM_TAG) do
          match = Regexp.last_match
          match[:kind] == 'COND' && match[:right] ? match[:block] + ' ' : match[:block]
        end
        html = html.gsub(INTERTAG_PATTERN_CUSTOM_CUSTOM) do
          match = Regexp.last_match
          [match[:left], match[:right]].include?('COND') ? match[:block] + ' ' : match[:block]
        end
      end

      html
    end

    def remove_spaces_inside_tags(html)
      #remove spaces around equals sign inside tags

      if @options[:remove_spaces_inside_tags]
        html = html.gsub(TAG_PROPERTY_PATTERN, '\1=')

        #remove ending spaces inside tags

        html.gsub!(TAG_END_SPACE_PATTERN) do |match|

          group_1 = $1
          group_2 = $2

          # keep space if attribute value is unquoted before trailing slash
          if group_2.start_with?("/") and (TAG_LAST_UNQUOTED_VALUE_PATTERN =~ group_1)
            "#{group_1} #{group_2}"
          else
            "#{group_1}#{group_2}"
          end
        end
      end

      html
    end

    def remove_quotes_inside_tags(html)
      if @options[:remove_quotes]
        html = html.gsub(TAG_QUOTE_PATTERN) do |match|
          # if quoted attribute is followed by "/" add extra space
          if $3.strip.length == 0
            "=#{$2}"
          else
            "=#{$2} #{$3}"
          end
        end
      end

      html
    end

    def remove_multi_spaces(html)
      # collapse multiple spaces
      if @options[:remove_multi_spaces]
        html = html.gsub(MULTISPACE_PATTERN, ' ')
      end

      html
    end

    def simple_boolean_attributes(html)
      # simplify boolean attributes
      if @options[:simple_boolean_attributes]
        html = html.gsub(BOOLEAN_ATTR_PATTERN, '\1\2\4')
      end

      html
    end

    def remove_surrounding_spaces(html)
      # remove spaces around provided tags

      unless @options[:remove_surrounding_spaces].nil?
        pattern = case @options[:remove_surrounding_spaces].downcase
        when BLOCK_TAGS_MIN
          SURROUNDING_SPACES_MIN_PATTERN
        when BLOCK_TAGS_MAX
          SURROUNDING_SPACES_MAX_PATTERN
        when ALL_TAGS
          SURROUNDING_SPACES_ALL_PATTERN
        else
          Regexp.new("\\s*(</?(?:" + @options[:remove_surrounding_spaces].gsub(",", "|") + ")(?:>|[\\s/][^>]*>))\\s*", Regexp::MULTILINE | Regexp::IGNORECASE)
        end

        html = html.gsub(pattern, '\1')
      end

      html
    end

    def message_format(message, *params)
      message.gsub(/\{(\d+),number,#\}/) do
        params[$1.to_i]
      end
    end

  end

end
