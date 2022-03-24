# frozen_string_literal: true

require_relative "../spec_helper"

class TestCapture
  def thing_1(arg)
    arg
  end

  def thing_2(arg:)
    arg
  end

  def thing_3(arg_1, arg_2:, &block)
    yield(arg_1, arg_2)
  end
end

describe SpartanAPM::Instrumentation do
  describe "instrument!" do
    it "should inject statistic capture into specified methods" do
      object = TestCapture.new
      SpartanAPM::Instrumentation.instrument!(TestCapture, :thing, [:thing_1, :thing_2])
      SpartanAPM::Instrumentation.instrument!(TestCapture, :other, :thing_3, exclusive: true)
      expect(SpartanAPM).to receive(:capture).twice.with(:thing, exclusive: false).and_call_original
      expect(SpartanAPM).to receive(:capture).once.with(:other, exclusive: true).and_call_original
      expect(object.thing_1(1)).to eq 1
      expect(object.thing_2(arg: 2)).to eq 2
      expect(object.thing_3(1, arg_2: 2) { |x, y| x + y }).to eq 3
    end
  end

  describe "auto_instrument!" do
    it "should not raise any errors" do
      expect { SpartanAPM::Instrumentation.auto_instrument! }.to_not raise_error
    end
  end
end
