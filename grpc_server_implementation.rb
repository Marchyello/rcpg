#!/usr/bin/env ruby

require 'json'
require 'rcpg_services_pb'

include Rcpg

class GrpcServer < PaymentGatewayGrpc::Service

	attr_reader :payment_gateway
  attr_reader :topics

  def initialize(config)
    env = config[:environment].to_sym
    @topics = config[:kafka][:topics]
    @payment_gateway = PaymentGateway.new(config[:providers], env, topics)
  end

  def initiate_cardless(request, _call)
    puts "--- initiate_cardless RPC invoked ---"
    initiate_result = payment_gateway.initiate_payment(request)

    if initiate_result[:payment_errors].any?
      InitiateCardlessResponse.new(payment_errors: initiate_result[:payment_errors])
    else
      InitiateCardlessResponse.new(
        payment_errors: [], 
        token: initiate_result[:token], 
        confirm_initiation_url: initiate_result[:confirm_initiation_url],
        initiated_on: initiate_result[:initiated_on]
      )
    end
  end

  def pay_standard(request, _call)
    puts "--- pay_standard RPC invoked ---"
    pay_result = payment_gateway.pay_standard(request)

    response = convert_to_pay_response(pay_result)

    # Produce message only if capture was attempted.
    if request.intent == :PURCHASE
      deliver_response_msg(response)
    end

    response
  end

  def pay_cardless(request, call)
    puts "--- pay_cardless RPC invoked ---"
    pay_result = payment_gateway.pay_cardless(request)

    response = convert_to_pay_response(pay_result)

    # Produce message only if capture was attempted.
    if request.intent == :PURCHASE
      deliver_response_msg(response)
    end
    
    response
  end

  def capture(request, _call)
    puts "--- capture RPC invoked ---"
    capture_result = payment_gateway.capture(request)

    response = convert_to_pay_response(capture_result)

    deliver_response_msg(response)
    response
  end

  def get_details(request, _call)
    puts "--- get_details RPC invoked ---"
    details_result = payment_gateway.get_details(request)

    if details_result[:errors].any?
      GetDetailsResponse.new(errors: details_result[:errors])
    else
      GetDetailsResponse.new(
        errors: [], 
        details: details_result[:details].to_json
      )
    end
  end
  
  private

  def convert_to_pay_response(pay_result)
    if pay_result[:payment_errors].any?
      PayResponse.new(payment_errors: pay_result[:payment_errors])
    else
      PayResponse.new(
        payment_errors: [], 
        payment_id: pay_result[:payment_id],
        executed_on: pay_result[:executed_on]
      )
    end
  end

  # Write response as a Kafka message to capture results topic.
  def deliver_response_msg(msg)
    $kafka_producer.produce(msg.to_json, topic: topics[:results])
    $kafka_producer.deliver_messages
  end

end
