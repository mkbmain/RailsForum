require "test_helper"

class BanReasonTest < ActiveSupport::TestCase
  test "valid with a name" do
    assert BanReason.new(name: "Spam").valid?
  end

  test "invalid without a name" do
    assert_not BanReason.new(name: nil).valid?
  end

  test "invalid with a duplicate name" do
    BanReason.create!(name: "Spam")
    assert_not BanReason.new(name: "Spam").valid?
  end
end
