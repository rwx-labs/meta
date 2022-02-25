# encoding: utf-8

module Ordnet
  class Query
    attr_reader :idioms
    attr_reader :definitions
    attr_accessor :word
    attr_accessor :origin
    attr_accessor :success
    attr_accessor :document
    attr_accessor :phonetic
    attr_accessor :audio_url
    attr_accessor :inflection
    attr_accessor :word_classes

    def initialize document
      @idioms = []
      @phonetic = ""
      @document = Nokogiri::HTML document
      @definitions = []

      parse!
    end

    def parse!
      if results = @document.at('span[@class=ar]')
        # Parse the "head" of the word listing.
        if head = results.at('span[@class=head]')
          # Set the original word.
          if element = head.at('span[@class=k]')
            @word = element.text
          end

          # Look for an auditory pronounciation.
          if audio = head.at('span[@class=audio]/audio')
            @audio_url = audio['src']
          end
        end

        if element = results.at('span[@class=pos]')
          @word_classes = element.text
        end

        if element = results.at('span[@class=m]')
          @inflection = element.text
        end

        # Parse the phonetic spelling.
        if element = results.at('span[@class=phon]')
          @phonetic = element.text
        end

        # Parse the definitions.
        definitions_body = results.at 'span[@class=def]'

        # For some reason the origin of the word is listed in the definitions
        # and not the head.
        if element = definitions_body.at('span[@class=etym]')
          @origin = element.text
        end

        definitions = definitions_body.xpath "span[@class='def']"
        definitions.each do |element|
          @definitions << Definition.new(element)
        end

        idiom_body = definitions_body.at 'span[@class="idiom"]'

        if idiom_body
          idioms = idiom_body.xpath 'span[@class="idiom"]'
          idioms.each do |element|
            @idioms << Idiom.new(element)
          end
        end

        @success = true
      else
        # No results found
        @success = false
      end
    end
  end
end
