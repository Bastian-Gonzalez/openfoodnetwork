require 'open_food_network/cached_products_renderer'

class ShopController < BaseController
  layout "darkswarm"
  before_filter :require_distributor_chosen, :set_order_cycles, except: :changeable_orders_alert
  before_filter :enable_embedded_shopfront

  def show
    redirect_to main_app.enterprise_shop_path(current_distributor)
  end

  def products
    renderer = OpenFoodNetwork::CachedProductsRenderer.new(current_distributor,
                                                           current_order_cycle)

    # If we add any more filtering logic, we should probably
    # move it all to a lib class like 'CachedProductsFilterer'
    products_json = filter(renderer.products_json)

    render json: products_json
  rescue OpenFoodNetwork::CachedProductsRenderer::NoProducts
    render status: :not_found, json: ''
  end

  def order_cycle
    if request.post?
      if oc = OrderCycle.with_distributor(@distributor).active.find_by_id(params[:order_cycle_id])
        current_order(true).set_order_cycle! oc
        @current_order_cycle = oc
        render partial: "json/order_cycle"
      else
        render status: :not_found, json: ""
      end
    else
      render partial: "json/order_cycle"
    end
  end

  def changeable_orders_alert
    render layout: false
  end

  private

  def filtered_json(products_json)
    if applicator.rules.any?
      filter(products_json)
    else
      products_json
    end
  end

  def filter(products_json)
    products_hash = JSON.parse(products_json)
    applicator.filter!(products_hash)
    JSON.unparse(products_hash)
  end

  def applicator
    return @applicator unless @applicator.nil?
    @applicator = OpenFoodNetwork::TagRuleApplicator.new(current_distributor,
                                                         "FilterProducts",
                                                         current_customer.andand.tag_list)
  end
end
