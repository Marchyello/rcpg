#!/usr/bin/env ruby

require 'rcpg_services_pb'

class Validator

  attr_reader :valid_providers

  def initialize(valid_providers)
    @valid_providers = valid_providers
  end

	def validate_initiate_cardless_request(request)
		validation_errors = validate_common(request)
  	add_error(validation_errors, "intent", "invalid") if intent_invalid(request.intent)
  	add_error(validation_errors, "return_url", "empty") if string_empty(request.return_url)
  	add_error(validation_errors, "cancel_return_url", "empty") if string_empty(request.cancel_return_url)
  	return validation_errors
  end

  def validate_pay_standard_request(request)
  	validation_errors = validate_common(request)
    add_error(validation_errors, "intent", "invalid") if intent_invalid(request.intent)
    add_error(validation_errors, "payment_card", "empty") if request.payment_card.nil?
  	return validation_errors
  end

  def validate_pay_cardless_request(request)
  	validation_errors = validate_common(request)
  	add_error(validation_errors, "payment_id", "empty") if string_empty(request.payment_id)
    add_error(validation_errors, "payer_id", "empty") if string_empty(request.payer_id)
    add_error(validation_errors, "intent", "invalid") if intent_invalid(request.intent)
  	return validation_errors
  end

  def validate_capture_request(request)
    validation_errors = validate_common(request)
    add_error(validation_errors, "payment_id", "empty") if string_empty(request.payment_id)
    return validation_errors
  end

  def validate_get_details_request(request)
  	validation_errors = []
    add_error(validation_errors, "provider", "invalid") if provider_invalid(request.provider)
  	add_error(validation_errors, "identifier", "empty") if string_empty(request.identifier)
    add_error(validation_errors, "id_type", "invalid") if id_type_invalid(request.id_type)
  	return validation_errors
  end

  private

  def validate_common(request)
    validation_errors = []
    add_error(validation_errors, "provider", "invalid") if provider_invalid(request.provider)
    add_error(validation_errors, "payment_sum", "empty") if int_empty(request.payment_sum)
    add_error(validation_errors, "payment_sum", "invalid") if int_invalid(request.payment_sum)
    add_error(validation_errors, "currency", "empty") if string_empty(request.currency)
    return validation_errors
  end

  def provider_invalid(value)
    value == :NO_PROVIDER || !(valid_providers.include? value)
  end

  def int_empty(value)
  	value.nil? || value == 0
  end

  def string_empty(value)
  	value.nil? || value == ""
  end

  def int_invalid(value)
  	!(value.is_a? Integer) || value <= 0
  end

  def intent_invalid(value)
  	value.nil? || value == :NO_INTENT
  end

  def id_type_invalid(value)
    value.nil? || value == :NO_IDENTIFIER_TYPE
  end

  def add_error(validation_errors, source, error_code)
  	validation_errors << PaymentError.new(source: source, error_code: error_code)
  end
end
