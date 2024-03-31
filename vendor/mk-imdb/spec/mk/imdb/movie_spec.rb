require_relative '../../spec_helper'

describe MK::IMDb::Movie do
  let(:document) { Nokogiri::HTML File.open(File.join(__dir__, '../../data/tt7608028-reference.html')) }

  subject do
    MK::IMDb::Movie.new(document)
  end

  describe '#title' do
    it 'should have a title' do
      expect(subject.title).to eq 'The Open House'
    end

    it 'should have a year' do
      expect(subject.year).to eq '2018'
    end
  end

  describe '#plot' do
    it 'should have a plot' do
      expect(subject.plot).to eq 'A teenager (Dylan Minnette) and his mother (Piercey Dalton) find themselves besieged by threatening forces when they move into a new house.'
    end
  end

  describe '#genres!' do
    it 'should have genres' do
      expect(subject.genres).to_not be_empty
    end

    it 'should be horror and thriller' do
      expect(subject.genres).to include 'Horror', 'Thriller'
    end
  end

  describe '#rating' do
    it 'should have a rating' do
      expect(subject.rating).to_not be_nil
    end

    it 'should have a rating of 3.3' do
      expect(subject.rating).to eq 3.3
    end
  end

  describe '#directors' do
    it 'should have directors' do
      expect(subject.genres).to be_kind_of Array
    end

    it 'should have Matt Angel, Suzanne Coote as directors' do
      expect(subject.directors).to include 'Matt Angel', 'Suzanne Coote'
    end
  end

  describe '#release_date' do
    it 'should have a release date' do
      expect(subject.release_date).to_not be_nil
    end

    it 'should have a proper release date' do
      expect(subject.release_date).to eq '19 Jan 2018 (Poland)'
    end
  end

  describe '#casts' do
    it 'should have casts' do
      expect(subject.casts).to_not be_nil
    end

    it 'should have a list of casts' do
      expect(subject.casts).to include 'Dylan Minnette', 'Piercey Dalton'
    end
  end
end
