require 'minitest/autorun'
require 'htmlcompressor/compressor'

module HtmlCompressor

  module TestFixtures
    EMAIL_PRESERVE_PATTERNS = [
      /\s?\{%.*?%\}\s?/im, /\s?\{\{.*?\}\}\s?/im,
      /<!--<!\[endif\]-->/im, /<!--\[if !mso\]><!-->/im, /<!-- End -->/im, /<!-->/im
    ].freeze
  end

  class TestCompressor < Minitest::Test

    private

    def resource_path
      File.join File.expand_path(File.dirname(__FILE__)), 'resources', 'html'
    end

    def read_resource file
      File.open File.join(resource_path, file), 'r' do |f|
        return f.readlines.join('')
      end
    end

  end

end
