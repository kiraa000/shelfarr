# frozen_string_literal: true

require "test_helper"

class HardcoverIdentifierBackfillServiceTest < ActiveSupport::TestCase
  setup do
    @book = books(:audiobook_acquired)
    @book.update!(
      title: "The Primal Hunter 3",
      hardcover_id: "995246",
      isbn: nil,
      asin: nil
    )
  end

  test "fills blank audiobook identifiers" do
    result = HardcoverEditionIdentifierService::Result.new(
      edition_id: 31_991_971,
      isbn: nil,
      asin: "B0B6JRLWVY"
    )

    HardcoverEditionIdentifierService.stub(:call, result) do
      assert HardcoverIdentifierBackfillService.apply!(@book)
    end

    @book.reload

    assert_nil @book.isbn
    assert_equal "B0B6JRLWVY", @book.asin
  end

  test "fills valid audiobook ISBN when available" do
    result = HardcoverEditionIdentifierService::Result.new(
      edition_id: 123,
      isbn: "9781234567897",
      asin: "B000AUDIO1"
    )

    HardcoverEditionIdentifierService.stub(:call, result) do
      assert HardcoverIdentifierBackfillService.apply!(@book)
    end

    @book.reload

    assert_equal "9781234567897", @book.isbn
    assert_equal "B000AUDIO1", @book.asin
  end

  test "never overwrites existing identifiers" do
    @book.update!(
      isbn: "EXISTING-ISBN",
      asin: "EXISTING-ASIN"
    )

    result = HardcoverEditionIdentifierService::Result.new(
      edition_id: 123,
      isbn: "9781234567897",
      asin: "B000AUDIO1"
    )

    HardcoverEditionIdentifierService.stub(:call, result) do
      assert_not HardcoverIdentifierBackfillService.apply!(@book)
    end

    @book.reload

    assert_equal "EXISTING-ISBN", @book.isbn
    assert_equal "EXISTING-ASIN", @book.asin
  end

  test "does nothing when edition matching is ambiguous" do
    result = HardcoverEditionIdentifierService::Result.new(
      edition_id: nil,
      isbn: nil,
      asin: nil
    )

    HardcoverEditionIdentifierService.stub(:call, result) do
      assert_not HardcoverIdentifierBackfillService.apply!(@book)
    end

    @book.reload

    assert_nil @book.isbn
    assert_nil @book.asin
  end

  test "does not process ebooks" do
    @book.update!(book_type: :ebook)

    HardcoverEditionIdentifierService.stub(
      :call,
      ->(*) { flunk "selector should not be called for ebooks" }
    ) do
      assert_not HardcoverIdentifierBackfillService.apply!(@book)
    end
  end
end
