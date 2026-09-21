# frozen_string_literal: true

class HardcoverIdentifierBackfillService
  class << self
    def apply!(book)
      return false unless book.audiobook?
      return false if book.hardcover_id.blank?

      result = HardcoverEditionIdentifierService.call(book)

      attrs = {}

      if book.isbn.blank? && result.isbn.present?
        attrs[:isbn] = result.isbn
      end

      if book.asin.blank? && result.asin.present?
        attrs[:asin] = result.asin
      end

      return false if attrs.empty?

      book.update!(attrs)
      true
    end
  end
end
