# frozen_string_literal: true

module MK
  module IMDb
    class Movie
      attr_accessor :id, :year, :plot, :genres, :rating, :casts, :directors,
                    :release_date, :title

      def initialize(document)
        if (element = document.at_css('section.article'))
          @body = document
        else
          raise MovieDataError, 'Missing main body!'
        end

        @directors = []

        # Parse the movie id.
        if (element = document.at('link[@rel="canonical"]'))
          href = element['href']

          if href =~ %r{imdb\.com/title/(tt\d+)/}
            @id = $1
          end
        end

        parse!
      end

      def director
        @directors&.first
      end

      private

      def parse!
        parse_plot!
        parse_title!
        parse_casts!
        parse_genres!
        parse_rating!
        parse_directors!
        parse_release_date!
      end

      # Parse the movie title.
      def parse_title!
        if (header = @body.at_css('.titlereference-header h3'))
          # Remove excess information.
          header_text = header.text.strip
          header_text.gsub! /[\r\n]+/, ''

          if header_text =~ /(.*?) \((.*?)\)/
            @title = sanitize $1
            @year = $2
          else
            @title = sanitize header_text
          end
        end
      end

      FILTERED_SECTION_PREFIXES = ['Seasons:', 'Episodes:', 'Creators:',
                                   'Writers:', 'Stars:', 'Awards:', 'Reviews:', 'Season:', 'Year:'].freeze

      # Parse the movie plot.
      def parse_plot!
        reference_sections = @body.css('section.titlereference-section-overview div')

        # Find the first element without bogus text.
        element = reference_sections.find do |element|
          text = element.text&.strip

          !FILTERED_SECTION_PREFIXES.find do |prefix|
            text&.start_with?(prefix)
          end
        end

        if element
          # Remove excess information.
          element.xpath('.//a').remove

          # Remove the dreaded characters.
          @plot = sanitize strip_see_more_text element.text
        end
      end

      # Parse the movie genres.
      def parse_genres!
        if (elements = @body.css('.titlereference-header ul.ipl-inline-list li'))
          # Go through the list elements and find the one with genre links.
          genre_list_element = find_list_element_with_link(elements, '/genre/')

          if genre_list_element
            genre_links = genre_list_element.css('a')

            @genres = genre_links.map(&:text)
          end
        end
      end

      # Go through the list of +list_elements+ and find the one which has links
      # that contain the string '/genre' and return the element.
      def find_list_element_with_link(list_elements, pattern)
        list_elements.find do |li|
          links = li.css 'a'

          if links.any? { |link| link['href'].include?(pattern) }
            return li
          end
        end

        nil
      end

      # Parse the movie rating.
      def parse_rating!
        if (element = @body.at_css(".titlereference-header ul.ipl-inline-list .ipl-rating-star"))
          @rating = element.at_css('span.ipl-rating-star__rating')&.text&.to_f
          @rating_votes = element.at_css('span.ipl-rating-star__total-votes')&.text
        end
      end

      # Parse the movie casts.
      def parse_casts!
        if (element = @body.at("table[@class='cast_list']"))
          cast_rows = element.css('tr')
          cast_rows.shift # Remove the first row

          @casts = cast_rows.css("td.itemprop[itemprop='actor']").map do |actor_td|
            actor_td.text.strip
          end
        end
      end

      # Parse the directors.
      def parse_directors!
        if (element = @body.at_css('section.titlereference-section-overview'))
          overview_sections = element.css('div.titlereference-overview-section')

          # Find the directors section
          directors_section = overview_sections.find do |section|
            section.text.strip.start_with?('Director')
          end

          if directors_section
            @directors = directors_section.css('a').map(&:text)
          end
        end
      end

      def find_overview_section_with_directors(sections_list)
        sections_list.find do |section|
          section.text.strip.start_with?('Director')
        end
      end

      # Parse the release date.
      def parse_release_date!
        if (elements = @body.css('.titlereference-header ul.ipl-inline-list li'))
          # Go through the list elements and find the one with release date links.
          release_date_elements = find_list_element_with_link(elements, '/releaseinfo')

          if release_date_elements
            @release_date = release_date_elements.at_css('a')&.text&.strip
          end
        end
      end

      # Strip the "See more »" text.
      def strip_see_more_text(text)
        text.delete("\u00BB\u00A0").sub(/\|\s+/, '').strip
      end

      def sanitize(string)
        string.gsub(/[\r\n]+/, '').gsub(/\s{2,}/, ' ').strip
      end
    end
  end
end
