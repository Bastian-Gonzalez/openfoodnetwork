require 'spec_helper'

describe Spree::OrderMailer do
  include OpenFoodNetwork::EmailHelper

  describe "order confimation" do
    after do
      ActionMailer::Base.deliveries.clear
    end

    before do
      setup_email
      ActionMailer::Base.delivery_method = :test
      ActionMailer::Base.perform_deliveries = true
      ActionMailer::Base.deliveries = []

      @bill_address = create(:address)
      @distributor_address = create(:address, address1: "distributor address", city: 'The Shire', zipcode: "1234")
      @distributor = create(:distributor_enterprise, address: @distributor_address)
      product = create(:product)
      @shipping_instructions = "pick up on thursday please!"
      ship_address = create(:address, address1: "distributor address", city: 'The Shire', zipcode: "1234")
      @order1 = create(:order, distributor: @distributor, bill_address: @bill_address, ship_address: ship_address, special_instructions: @shipping_instructions)
      ActionMailer::Base.deliveries = []
    end

    describe "for customers" do
      it "should send an email to the customer when given an order" do
        Spree::OrderMailer.confirm_email_for_customer(@order1.id).deliver
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to).to eq([@order1.email])
      end

      it "sets a reply-to of the enterprise email" do
        Spree::OrderMailer.confirm_email_for_customer(@order1.id).deliver
        expect(ActionMailer::Base.deliveries.first.reply_to).to eq([@distributor.contact.email])
      end
    end

    describe "for shops" do
      it "sends an email to the shop owner when given an order" do
        Spree::OrderMailer.confirm_email_for_shop(@order1.id).deliver
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to).to eq([@distributor.contact.email])
      end

      it "sends an email even if a footer_email is given" do
        # Testing bug introduced by a9c37c162e1956028704fbdf74ce1c56c5b3ce7d
        ContentConfig.footer_email = "email@example.com"
        Spree::OrderMailer.confirm_email_for_shop(@order1.id).deliver
        expect(ActionMailer::Base.deliveries.count).to eq(1)
      end
    end
  end
end
