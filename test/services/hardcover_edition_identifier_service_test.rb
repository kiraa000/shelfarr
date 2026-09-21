# frozen_string_literal: true

require "test_helper"

class HardcoverEditionIdentifierServiceTest < ActiveSupport::TestCase
  setup do
    @book = books(:audiobook_acquired)
    @book.update!(
      title: "The Primal Hunter 3",
      author: "Zogarth",
      hardcover_id: "995246"
    )
  end

  test "chooses explicit audiobook edition and ignores paperback and Kindle identifiers" do
    editions = [
      edition(
        id: 31_019_999,
        format: "Paperback",
        isbn_13: "9798848371628",
        isbn_13_valid: true
      ),
      edition(
        id: 31_229_951,
        format: "Kindle",
        asin: "B0B2X2HFL4"
      ),
      edition(
        id: 31_991_971,
        format: "Audiobook",
        asin: "B0B6JRLWVY",
        audio_seconds: 66_180
      ),
      edition(
        id: 32_179_331,
        format: nil,
        asin: "B0B6JM8KKV",
        audio_seconds: 66_180
      ),
      edition(
        id: 32_682_082,
        title: "The Primal Hunter 3: A LitRPG Adventure",
        format: "Paperback",
        isbn_13: "9798856907864",
        isbn_13_valid: true
      )
    ]

    HardcoverClient.stub(:book_editions, editions) do
      result = HardcoverEditionIdentifierService.call(@book)

      assert_equal 31_991_971, result.edition_id
      assert_equal "B0B6JRLWVY", result.asin
      assert_nil result.isbn
    end
  end

  test "uses valid ISBN only when it belongs to selected audiobook edition" do
    editions = [
      edition(
        id: 100,
        format: "Audiobook",
        asin: "B000AUDIO1",
        audio_seconds: 10_000,
        isbn_13: "9781234567897",
        isbn_13_valid: true
      )
    ]

    HardcoverClient.stub(:book_editions, editions) do
      result = HardcoverEditionIdentifierService.call(@book)

      assert_equal "B000AUDIO1", result.asin
      assert_equal "9781234567897", result.isbn
    end
  end

  test "rejects invalid ISBN on audiobook edition" do
    editions = [
      edition(
        id: 101,
        format: "Audiobook",
        asin: "B000AUDIO2",
        audio_seconds: 10_000,
        isbn_13: "9780000000000",
        isbn_13_valid: false
      )
    ]

    HardcoverClient.stub(:book_editions, editions) do
      result = HardcoverEditionIdentifierService.call(@book)

      assert_equal "B000AUDIO2", result.asin
      assert_nil result.isbn
    end
  end

  test "does not use Hardcover audiobook identifiers for ebook records" do
    @book.update!(book_type: :ebook)

    called = false

    HardcoverClient.stub(:book_editions, ->(*) {
      called = true
      []
    }) do
      result = HardcoverEditionIdentifierService.call(@book)

      assert_nil result.edition_id
      assert_nil result.isbn
      assert_nil result.asin
      assert_not called
    end
  end

  test "refuses conflicting equally ranked audiobook editions" do
    editions = [
      edition(
        id: 200,
        format: "Audiobook",
        asin: "B000AUDIOA",
        audio_seconds: 10_000
      ),
      edition(
        id: 201,
        format: "Audiobook",
        asin: "B000AUDIOB",
        audio_seconds: 10_000
      )
    ]

    HardcoverClient.stub(:book_editions, editions) do
      result = HardcoverEditionIdentifierService.call(@book)

      assert_nil result.edition_id
      assert_nil result.isbn
      assert_nil result.asin
    end
  end

  private

  def edition(
    id:,
    title: "The Primal Hunter 3",
    format:,
    asin: nil,
    audio_seconds: nil,
    isbn_10: nil,
    isbn_10_valid: nil,
    isbn_13: nil,
    isbn_13_valid: nil
  )
    HardcoverClient::EditionDetails.new(
      id: id,
      title: title,
      asin: asin,
      audio_seconds: audio_seconds,
      edition_format: format,
      reading_format_id: nil,
      isbn_10: isbn_10,
      isbn_10_valid: isbn_10_valid,
      isbn_13: isbn_13,
      isbn_13_valid: isbn_13_valid,
      isbns_match: nil,
      release_date: "2022-08-30",
      release_year: 2022
    )
  end
end
