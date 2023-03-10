# Configure Spree Preferences
#
# Note: Initializing preferences available within the Admin will overwrite any changes that were made through the user interface when you restart.
#       If you would like users to be able to update a setting with the Admin it should NOT be set here.
#
# In order to initialize a setting do:
# config.setting_name = 'new value'

require 'spree/product_filters'

# Due to a bug in ActiveRecord we need to load the tagging code in Gateway which
# should have inherited it from its parent PaymentMethod.
# We have to call it before loading the PaymentMethod decorator because the
# tagging code won't load twice within the inheritance chain.
# https://github.com/openfoodfoundation/openfoodnetwork/issues/3121
Spree::Gateway.class_eval do
  acts_as_taggable
  attr_accessible :tag_list
end

require "#{Rails.root}/app/models/spree/payment_method_decorator"
require "#{Rails.root}/app/models/spree/gateway_decorator"

Spree.config do |config|
  config.shipping_instructions = true
  config.address_requires_state = true
  config.admin_interface_logo = 'ofn-logo.png'

  # -- spree_paypal_express
  # Auto-capture payments. Without this option, payments must be manually captured in the paypal interface.
  config.auto_capture = true
  #config.override_actionmailer_config = false

  config.package_factory = Stock::Package
  config.order_updater_decorator = OrderUpdater

  # S3 settings
  config.s3_bucket = ENV['S3_BUCKET'] if ENV['S3_BUCKET']
  config.s3_access_key = ENV['S3_ACCESS_KEY'] if ENV['S3_ACCESS_KEY']
  config.s3_secret = ENV['S3_SECRET'] if ENV['S3_SECRET']
  config.use_s3 = true if ENV['S3_BUCKET']
  config.s3_protocol = ENV.fetch('S3_PROTOCOL', 'https')
end

# Spree 2.0 recommends explicitly setting this here when using spree_auth_devise
Spree.user_class = 'Spree::User'

# Don't log users out when setting a new password
Spree::Auth::Config[:signout_after_password_change] = false

# TODO Work out why this is necessary
# Seems like classes within OFN module become 'uninitialized' when server reloads
# unless the empty module is explicity 'registered' here. Something to do with autoloading?
module OpenFoodNetwork
end
