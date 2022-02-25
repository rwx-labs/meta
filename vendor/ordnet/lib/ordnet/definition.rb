module Ordnet
  class Definition
    attr_accessor :index
    attr_accessor :example
    attr_accessor :definition

    def initialize element
      @element = element

      parse!
    end

    def parse!
      # Find the index.
      if element = @element.at('//span[@class="l"]')
        @index = element.text
      end

      # Find the example text.
      if element = @element.at('//span[@class="ex"]')
        @example = element.text
      end

      # Find the definition text.
      if element = @element.at('span[@class="dtrn"]')
        @definition = element.text
      end
    end
  end
end