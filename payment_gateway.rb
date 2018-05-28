#!/usr/bin/env ruby

require 'json'
require 'rcpg_services_pb'
require 'uri'
require 'validation'

class PaymentGateway

	attr_reader :providers
	attr_reader :topics
	attr_reader :validator
	
	# def initialize(paypal_config)
	def initialize(provider_configs, environment, topics)
		ActiveMerchant::Billing::Base.mode = environment.to_sym
		@topics = topics

		@providers = {}
		provider_keys = []

		provider_configs.each do |provider, config|
			# Intitalize all service providers
			begin
				providers[provider] = ("ActiveMerchant::Billing::" << provider.to_s).constantize.new(config[environment][:credentials])
				provider_keys << provider
			rescue StandardError => ex
				log_msg = "--- Failed to initialize provider \"#{provider.to_s}\". Exception occurred. ---\n"
				log_msg << "--- Exception message: #{ex.message} ---"
				deliver_log_msg(log_msg)
			end
		end

    @validator = Validator.new(provider_keys)
    puts "--- RCPG microservice initiated ---"
	end

	# Authenticates user and verifies payment information, but executes no payment method. Instead returns 
	# token and payer id which can be used to execute payment actions. Is only used for cardless providers.
	def initiate_payment(request)
		payment_errors = validator.validate_initiate_cardless_request(request)
		return { :payment_errors => payment_errors } if payment_errors.any?

		options = {
			return_url: request.return_url,
			cancel_return_url: request.cancel_return_url,
			currency: request.currency,
			allow_guest_checkout: request.allow_guest_checkout
		}
		options[:items] = build_items(request.items) if request.items.any?
		
		begin
			case request.intent
			when :AUTHORIZATION
	    	response = providers[request.provider].setup_authorization(request.payment_sum, options)
	    when :PURCHASE
	      response = providers[request.provider].setup_purchase(request.payment_sum, options)
	    end
	    if !(response.success?)
	    	payment_errors << PaymentError.new(source: "provider", error_code: response.message)
	    	return { :payment_errors => payment_errors }
	    end
		rescue ActiveMerchant::ActiveMerchantError => ex
			log_msg = "--- While trying to initiate payment via provider \"#{provider.to_s}\" exception occurred. ---\n"
			log_msg << "--- Exception message: #{ex.message} ---"
			deliver_log_msg(log_msg)
			
			payment_errors << PaymentError.new(source: "provider", error_code: ex.message)
			return { :payment_errors => payment_errors }
		end

		# Logging to console for dev use only.
		puts "--- Logging initiate_payment response to console ---"
		puts response.to_yaml
		puts "--- End of initiate_payment response log ---"

		# Log via Kafka.
		deliver_log_msg(response.to_json)

		confirm_initiation_url = build_confirm_initiation_url(response.token)
		result = {
			:payment_errors => payment_errors,
			:token => response.token,
			:confirm_initiation_url => confirm_initiation_url,
			:initiated_on => response.params["timestamp"]
		}
	end

	# Either authorizes a payment or executes a purchase for standard transactions. Authorized payment must 
	# be captured later to pull funds. Purchase means executing authorization and capture in a single step.
	# "Standard" means that payment gateway dirctly handles payment card data.
	def pay_standard(request)
		payment_errors = validator.validate_pay_standard_request(request)
		# Verifies that no required payment card fields are missing.
		begin
			payment_card = build_payment_card(request.payment_card)
		rescue ActiveMerchant::ActiveMerchantError => ex
			payment_errors << PaymentError.new(source: "payment_card", error_code: "missing_input")
		end
		# Validates format of payment card fields.
		payment_errors << PaymentError.new(source: "payment_card", error_code: "invalid_input") if !(payment_card.validate.empty?)
		return { :payment_errors => payment_errors } if payment_errors.any?

		options = build_standard_options(request)
		options[:items] = build_items(request.items) if request.items.any?

		begin
			case request.intent
			when :AUTHORIZATION
				response = providers[request.provider].authorize(request.payment_sum, payment_card, options)
			when :PURCHASE
				response = providers[request.provider].purchase(request.payment_sum, payment_card, options)
			end

			if !(response.success?)
	    	payment_errors << PaymentError.new(source: "provider", error_code: response.message)
	    	return { :payment_errors => payment_errors }
	    end
	  rescue ActiveMerchant::ActiveMerchantError => ex
	  	log_msg = "--- While trying to pay with card data via provider \"#{provider.to_s}\" exception occurred. ---"
			log_msg << "--- Exception message: #{ex.message} ---"
			deliver_log_msg(log_msg)

	  	payment_errors << PaymentError.new(source: "provider", error_code: ex.message)
	  	return { :payment_errors => payment_errors }
	  end

	  # Logging to console for dev use only.
	  puts "--- Logging pay_standard response ---"
	  puts response.to_yaml
	  puts "--- End of pay_standard response log ---"

	  # Log via Kafka.
		deliver_log_msg(response.to_json)

	  result = {
	  	:payment_errors => payment_errors,
	  	:payment_id => response.params["transaction_id"],
	  	:executed_on => DateTime.now.strftime("%FT%T%z")
	  }
	end

	# Either authorizes a payment or executes a purchase for cardless transactions. Authorized payment must
	# be captured later to pull funds. Purchase means executing authorization and capture in a single step. 
	# "Cardless" means that payment gateway does not come in contact with payment card data, instead a token
	# is used.
	def pay_cardless(request)
		payment_errors = validator.validate_pay_cardless_request(request)
		return { :payment_errors => payment_errors } if payment_errors.any?

		options = build_cardless_options(request)
		begin
			case request.intent
			when :AUTHORIZATION
				response = providers[request.provider].authorize(request.payment_sum, options)
			when :PURCHASE
				response = providers[request.provider].purchase(request.payment_sum, options)
			end

			if !(response.success?)
	    	payment_errors << PaymentError.new(source: "provider", error_code: response.message)
	    	return { :payment_errors => payment_errors }
	    end
		rescue ActiveMerchant::ActiveMerchantError => ex
			log_msg = "--- While trying to pay without card data via provider \"#{provider.to_s}\" exception occurred. ---"
			log_msg << "--- Exception message: #{ex.message} ---"
			deliver_log_msg(log_msg)

			payment_errors << PaymentError.new(source: "provider", error_code: ex.message)
			return { :payment_errors => payment_errors }
		end

		# Logging to console for dev use only.
		puts "--- Logging pay_cardless response ---"
		puts response.to_yaml
		puts "--- End of pay_cardless response logging ---"

		# Log via Kafka.
		deliver_log_msg(response.to_json)

		result = {
			:payment_errors => payment_errors,
			:payment_id => response.params["transaction_id"],
			:executed_on => response.params["PaymentInfo"]["PaymentDate"]
		}
	end

	# Captures funds based on previously made authorization. Single method for both cardless and standard 
	# transactions. Captured amount can be less that authorized (partial capture).
	def capture(request)
		payment_errors = validator.validate_capture_request(request)
		return { :payment_errors => payment_errors } if payment_errors.any?

		options = build_standard_options(request)
		begin
			response = providers[request.provider].capture(request.payment_sum, request.payment_id, options)

			if !(response.success?)
	    	payment_errors << PaymentError.new(source: "provider", error_code: response.message)
	    	return { :payment_errors => payment_errors }
	    end
		rescue ActiveMerchant::ActiveMerchantError => ex
			log_msg = "--- While trying to capture authorization via provider \"#{provider.to_s}\" exception occurred. ---"
			log_msg = "--- Exception message: #{ex.message} ---"
			deliver_log_msg(log_msg)
			
			payment_errors << PaymentError.new(source: "provider", error_code: ex.message)
			return { :payment_errors => payment_errors }
		end

		# Logging to console for dev use only.
		puts "--- Logging capture response ---"
		puts response.to_yaml
		puts "--- End of capture response logging ---"

		# Log via Kafka.
		deliver_log_msg(response.to_json)
		
		result = {
	  	:payment_errors => payment_errors,
	  	:payment_id => response.params["transaction_id"],
	  	:executed_on => DateTime.now.strftime("%FT%T%z")
	  }
	end

	# Get payment details by token or transaction id. Different methods are called for both idetnifiers.
	# Using transaction id provides more information since transaction id is only given to a successfully 
	# authorized or captured payment, while token is given on initiation.
	def get_details(request)
		errors = validator.validate_get_details_request(request)
		return { :errors => errors } if errors.any?

		# Only PayPayl Express Checkout supports getting payment details.
		if request.provider != :PaypalExpressGateway
			return {
				:errors => errors,
				:details => {
					:message => "This provider does not support payment details"
				}
			}
		end

		begin
			case request.id_type
			when :TOKEN
				response = providers[request.provider].details_for(request.identifier)
			when :TRANSACTION_ID
				response = providers[request.provider].transaction_details(request.identifier)
			end

				if !(response.success?)
					errors << PaymentError.new(source: "provider", error_code: response.message)
					return { :errors => errors }
				end
		rescue ActiveMerchant::ActiveMerchantError => ex
			errors << PaymentError.new(source: "provider", error_code: ex.message)
			return { :errors => errors }
		end

		# Logging to console for dev use only.
		puts "--- Logging get_details response ---"
		puts response.params.to_yaml
		puts "--- End of get_details response logging ---"

		result = {
			:errors => errors,
			:details => response.params
		}
	end

	private

	# Write Kafka message to log topic.
	def deliver_log_msg(msg)
		$kafka_producer.produce(msg, topic: topics[:log])
		$kafka_producer.deliver_messages
	end

	# Builds items from protocol buffer as Active Merchant CreditCard class.
	def build_payment_card(card_data)
		card = ActiveMerchant::Billing::CreditCard.new(
      :number => card_data.primary_number,
      :first_name => card_data.first_name,
      :last_name => card_data.last_name,
      :month => card_data.month,
      :year => card_data.year,
      :verification_value => card_data.verification_value
		)
	end

	# Builds items from protocol buffer as array of hashes.
	def build_items(items)
		order_items = []
		items.each do |item|
			converted_item = {
				name: item.name,
				description: item.description,
				quantity: item.quantity,
				amount: item.amount
			}
			order_items << converted_item
		end
		return order_items
	end

	def build_standard_options(request)
		{
			currency: request.currency
		}
	end

	def build_cardless_options(request)
		{
			token: request.payment_id,
			payer_id: request.payer_id,
			currency: request.currency
		}
	end

	# Builds url that will let buyer to authenticate on providers site.
	def build_confirm_initiation_url(token)
		args = {
			:host => "www.sandbox.paypal.com",
			:path => "/cgi-bin/webscr",
			:query => { 
				:cmd => "_express-checkout",
				:token => token
			}.to_query
		}

		url = URI::HTTPS.build(args).to_s
	end

	# Converts string that represents decimal to integer.
	def to_cents(value) 
		(value.to_f * 100).to_i
	end

end
