module Ordnet
  class Idiom
    attr_accessor :definition
    attr_accessor :example
    def initialize element
      @element = element

      parse!
    end

    def parse!
      if element = @element.at('//span[@class="ex"]')
        @example = element.text
      end

      # Find the definition text.
      if element = @element.at('span[@class=dtrn]')
        @definition = element.text
      end
    end
  end
end
