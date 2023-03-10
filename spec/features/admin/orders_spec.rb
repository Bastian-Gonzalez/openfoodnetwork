require "spec_helper"
include ActionView::Helpers::NumberHelper

feature '
    As an administrator
    I want to manage orders
', js: true do
  include AuthenticationWorkflow
  include WebHelper
  include CheckoutHelper

  background do
    @user = create(:user)
    @product = create(:simple_product)
    @distributor = create(:distributor_enterprise, owner: @user, charges_sales_tax: true)
    @order_cycle = create(:simple_order_cycle, name: 'One', distributors: [@distributor], variants: [@product.variants.first])

    @order = create(:order_with_totals_and_distribution, user: @user, distributor: @distributor, order_cycle: @order_cycle, state: 'complete', payment_state: 'balance_due')
    @customer = create(:customer, enterprise: @distributor, email: @user.email, user: @user, ship_address: create(:address))

    # ensure order has a payment to capture
    @order.finalize!

    create :check_payment, order: @order, amount: @order.total
  end

  def new_order_with_distribution(distributor, order_cycle)
    visit 'admin/orders/new'
    expect(page).to have_selector('#s2id_order_distributor_id')
    select2_select distributor.name, from: 'order_distributor_id'
    select2_select order_cycle.name, from: 'order_order_cycle_id'
    click_button 'Next'
  end

  scenario "order cycles appear in descending order by close date on orders page" do
    create(:simple_order_cycle, name: 'Two', orders_close_at: 2.weeks.from_now)
    create(:simple_order_cycle, name: 'Four', orders_close_at: 4.weeks.from_now)
    create(:simple_order_cycle, name: 'Three', orders_close_at: 3.weeks.from_now)

    quick_login_as_admin
    visit 'admin/orders'

    open_select2('#s2id_q_order_cycle_id_in')

    expect(find('#q_order_cycle_id_in', visible: :all)[:innerHTML]).to have_content(/.*Four.*Three.*Two.*One/m)
  end

  scenario "creating an order with distributor and order cycle" do
    distributor_disabled = create(:distributor_enterprise)
    create(:simple_order_cycle, name: 'Two')

    quick_login_as_admin

    visit '/admin/orders'
    click_link 'New Order'

    # Distributors without an order cycle should be shown as disabled
    open_select2('#s2id_order_distributor_id')
    expect(page).to have_selector "ul.select2-results li.select2-result.select2-disabled", text: distributor_disabled.name
    close_select2('#s2id_order_distributor_id')

    # Order cycle selector should be disabled
    expect(page).to have_selector "#s2id_order_order_cycle_id.select2-container-disabled"

    # When we select a distributor, it should limit order cycle selection to those for that distributor
    select2_select @distributor.name, from: 'order_distributor_id'
    expect(page).to have_select2 'order_order_cycle_id', options: ['One (open)']
    select2_select @order_cycle.name, from: 'order_order_cycle_id'
    click_button 'Next'

    # it suppresses validation errors when setting distribution
    expect(page).not_to have_selector '#errorExplanation'
    expect(page).to have_content 'ADD PRODUCT'
    targetted_select2_search @product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'
    find('button.add_variant').click
    page.has_selector? "table.index tbody[data-hook='admin_order_form_line_items'] tr" # Wait for JS
    expect(page).to have_selector 'td', text: @product.name

    click_button 'Update'

    expect(page).to have_selector 'h1', text: 'Customer Details'
    o = Spree::Order.last
    expect(o.distributor).to eq(@distributor)
    expect(o.order_cycle).to eq(@order_cycle)
  end

  scenario "can add a product to an existing order", retry: 3 do
    quick_login_as_admin
    visit '/admin/orders'

    click_icon :edit

    targetted_select2_search @product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'

    find('button.add_variant').click

    expect(page).to have_selector 'td', text: @product.name
    expect(@order.line_items(true).map(&:product)).to include @product
  end

  scenario "displays error when incorrect distribution for products is chosen" do
    d = create(:distributor_enterprise)
    oc = create(:simple_order_cycle, distributors: [d])

    # Move the order back to the cart state
    @order.state = 'cart'
    @order.completed_at = nil
    # A nil user keeps the order in the cart state
    #   Even if the edit page tries to automatically progress the order workflow
    @order.user = nil
    @order.save

    quick_login_as_admin
    visit '/admin/orders'
    uncheck 'Only show complete orders'
    page.find('a.icon-search').click

    click_icon :edit
    select2_select d.name, from: 'order_distributor_id'
    select2_select oc.name, from: 'order_order_cycle_id'

    click_button 'Update And Recalculate Fees'
    expect(page).to have_content "Distributor or order cycle cannot supply the products in your cart"
  end

  scenario "can't add products to an order outside the order's hub and order cycle" do
    product = create(:simple_product)

    quick_login_as_admin
    visit '/admin/orders'
    page.find('td.actions a.icon-edit').click

    expect(page).not_to have_select2 "add_variant_id", with_options: [product.name]
  end

  scenario "can't change distributor or order cycle once order has been finalized" do
    quick_login_as_admin
    visit '/admin/orders'
    page.find('td.actions a.icon-edit').click

    expect(page).not_to have_select2 'order_distributor_id'
    expect(page).not_to have_select2 'order_order_cycle_id'

    expect(page).to have_selector 'p', text: "Distributor: #{@order.distributor.name}"
    expect(page).to have_selector 'p', text: "Order cycle: #{@order.order_cycle.name}"
  end

  scenario "filling customer details" do
    # Given a customer with an order, which includes their shipping and billing address

    # We change the 1st order's address details
    #   This way we validate that the original details (stored in customer) are picked up in the 2nd order
    @order.ship_address = create(:address, lastname: 'Ship')
    @order.bill_address = create(:address, lastname: 'Bill')
    @order.save!

    # We set the existing shipping method to delivery, this shipping method will be used in the 2nd order
    #   Otherwise order_updater.shipping_address_from_distributor will set the 2nd order address to the distributor address
    @order.shipping_method.update_attribute :require_ship_address, true

    # When I create a new order
    quick_login_as @user
    new_order_with_distribution(@distributor, @order_cycle)
    targetted_select2_search @product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'
    find('button.add_variant').click
    page.has_selector? "table.index tbody[data-hook='admin_order_form_line_items'] tr" # Wait for JS
    click_button 'Update'

    expect(page).to have_selector 'h1.page-title', text: "Customer Details"

    # And I select that customer's email address and save the order
    targetted_select2_search @customer.email, from: '#customer_search_override', dropdown_css: '.select2-drop'
    click_button 'Update'
    expect(page).to have_selector "h1.page-title", text: "Customer Details"

    # Then their addresses should be associated with the order
    order = Spree::Order.last
    expect(order.ship_address.lastname).to eq @customer.ship_address.lastname
    expect(order.bill_address.lastname).to eq @customer.bill_address.lastname
  end

  scenario "capture payment from the orders index page" do
    quick_login_as_admin

    visit spree.admin_orders_path
    expect(page).to have_current_path spree.admin_orders_path

    # click the 'capture' link for the order
    page.find("[data-action=capture][href*=#{@order.number}]").click

    expect(page).to have_content "Payment Updated"

    # check the order was captured
    expect(@order.reload.payment_state).to eq "paid"

    # we should still be on the same page
    expect(page).to have_current_path spree.admin_orders_path
  end

  context "as an enterprise manager" do
    let(:coordinator1) { create(:distributor_enterprise) }
    let(:coordinator2) { create(:distributor_enterprise) }
    let!(:order_cycle1) { create(:order_cycle, coordinator: coordinator1) }
    let!(:order_cycle2) { create(:simple_order_cycle, coordinator: coordinator2) }
    let!(:supplier1) { order_cycle1.suppliers.first }
    let!(:supplier2) { order_cycle1.suppliers.last }
    let!(:distributor1) { order_cycle1.distributors.first }
    let!(:distributor2) { order_cycle1.distributors.reject{ |d| d == distributor1 }.last } # ensure d1 != d2
    let(:product) { order_cycle1.products.first }

    before(:each) do
      @enterprise_user = create_enterprise_user
      @enterprise_user.enterprise_roles.build(enterprise: supplier1).save
      @enterprise_user.enterprise_roles.build(enterprise: coordinator1).save
      @enterprise_user.enterprise_roles.build(enterprise: distributor1).save

      quick_login_as @enterprise_user
    end

    feature "viewing the edit page" do
      let!(:shipping_method_for_distributor1) { create(:shipping_method, name: "Normal", distributors: [distributor1]) }
      let!(:different_shipping_method_for_distributor1) { create(:shipping_method, name: "Different", distributors: [distributor1]) }
      let!(:shipping_method_for_distributor2) { create(:shipping_method, name: "Other", distributors: [distributor2]) }

      background do
        Spree::Config[:enable_receipt_printing?] = true

        distributor1.update_attribute(:abn, '12345678')
        @order = create(:order_with_taxes,
                        distributor: distributor1,
                        ship_address: create(:address),
                        product_price: 110,
                        tax_rate_amount: 0.1,
                        tax_rate_name: "Tax 1")
        Spree::TaxRate.adjust(@order)
        @order.update_shipping_fees!

        visit spree.edit_admin_order_path(@order)
      end

      scenario "shows a list of line_items" do
        within('table.index tbody', match: :first) do
          @order.line_items.each do |item|
            expect(page).to have_selector "td", match: :first, text: item.full_name
            expect(page).to have_selector "td.item-price", text: item.single_display_amount
            expect(page).to have_selector "input#quantity[value='#{item.quantity}']", visible: false
            expect(page).to have_selector "td.item-total", text: item.display_amount
          end
        end
      end

      scenario "shows the order items total" do
        within('fieldset#order-total') do
          expect(page).to have_selector "span.order-total", text: @order.display_item_total
        end
      end

      scenario "shows the order non-tax adjustments" do
        within('table.index tbody') do
          @order.adjustments.eligible.each do |adjustment|
            expect(page).to have_selector "td", match: :first, text: adjustment.label
            expect(page).to have_selector "td.total", text: adjustment.display_amount
          end
        end
      end

      scenario "shows the order total" do
        expect(page).to have_selector "fieldset#order-total", text: @order.display_total
      end

      scenario "shows the order tax adjustments" do
        within('fieldset', text: I18n.t('spree.admin.orders.form.line_item_adjustments').upcase) do
          expect(page).to have_selector "td", match: :first, text: "Tax 1"
          expect(page).to have_selector "td.total", text: Spree::Money.new(10)
        end
      end

      scenario "shows the dropdown menu" do
        find("#links-dropdown .ofn-drop-down").click
        within "#links-dropdown" do
          expect(page).to have_link "Resend Confirmation", href: spree.resend_admin_order_path(@order)
          expect(page).to have_link "Send Invoice", href: spree.invoice_admin_order_path(@order)
          expect(page).to have_link "Print Invoice", href: spree.print_admin_order_path(@order)
          expect(page).to have_link "Cancel Order", href: spree.fire_admin_order_path(@order, e: 'cancel')
        end
      end

      scenario "cannot split the order in different stock locations" do
        # There's only 1 stock location in OFN, so the split functionality that comes with spree should be hidden
        expect(page).to_not have_selector '.split-item'
      end

      scenario "can edit shipping method" do
        expect(page).to_not have_content different_shipping_method_for_distributor1.name

        find('.edit-method').click
        expect(page).to have_select2 'selected_shipping_rate_id', with_options: [shipping_method_for_distributor1.name, different_shipping_method_for_distributor1.name], without_options: [shipping_method_for_distributor2.name]
        select2_select different_shipping_method_for_distributor1.name, from: 'selected_shipping_rate_id'
        find('.save-method').click

        expect(page).to have_content different_shipping_method_for_distributor1.name
      end

      scenario "can edit tracking number" do
        test_tracking_number = "ABCCBA"
        expect(page).to_not have_content test_tracking_number

        find('.edit-tracking').click
        fill_in "tracking", with: test_tracking_number
        find('.save-tracking').click

        expect(page).to have_content test_tracking_number
      end

      scenario "can print an order's ticket" do
        find("#links-dropdown .ofn-drop-down").click

        ticket_window = window_opened_by do
          within('#links-dropdown') do
            click_link('Print Ticket')
          end
        end

        within_window ticket_window do
          accept_alert do
            print_data = page.evaluate_script('printData');
            elements_in_print_data =
              [
                @order.distributor.name,
                @order.distributor.address.address_part1,
                @order.distributor.address.address_part2,
                @order.distributor.contact.email,
                @order.number,
                @order.line_items.map { |line_item|
                  [line_item.quantity.to_s,
                   line_item.product.name,
                   line_item.single_display_amount_with_adjustments.format(symbol: false, with_currency: false),
                   line_item.display_amount_with_adjustments.format(symbol: false, with_currency: false)]
                },
                checkout_adjustments_for(@order, exclude: [:line_item]).reject { |a| a.amount == 0 }.map { |adjustment|
                  [raw(adjustment.label),
                   display_adjustment_amount(adjustment).format(symbol: false, with_currency: false)]
                },
                @order.display_total.format(with_currency: false),
                display_checkout_taxes_hash(@order).map { |tax_rate, tax_value|
                  [tax_rate,
                   tax_value.format(with_currency: false)]
                },
                display_checkout_total_less_tax(@order).format(with_currency: false)
              ]
            expect(print_data.join).to include(*elements_in_print_data.flatten)
          end
        end
      end

      scenario "editing shipping fees" do
        click_link "Adjustments"
        page.find('td.actions a.icon-edit').click

        fill_in "Amount", with: "5"
        click_button "Continue"

        expect(page.find("td.amount")).to have_content "$5.00"
      end
    end

    scenario "creating an order with distributor and order cycle" do
      new_order_with_distribution(distributor1, order_cycle1)

      expect(page).to have_content 'ADD PRODUCT'
      targetted_select2_search product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'

      find('button.add_variant').click
      page.has_selector? "table.index tbody[data-hook='admin_order_form_line_items'] tr" # Wait for JS
      expect(page).to have_selector 'td', text: product.name

      expect(page).to have_select2 'order_distributor_id', with_options: [distributor1.name]
      expect(page).to_not have_select2 'order_distributor_id', with_options: [distributor2.name]

      expect(page).to have_select2 'order_order_cycle_id', with_options: ["#{order_cycle1.name} (open)"]
      expect(page).to_not have_select2 'order_order_cycle_id', with_options: ["#{order_cycle2.name} (open)"]

      click_button 'Update'

      expect(page).to have_selector 'h1', text: 'Customer Details'
      o = Spree::Order.last
      expect(o.distributor).to eq distributor1
      expect(o.order_cycle).to eq order_cycle1
    end
  end
end
