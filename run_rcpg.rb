#!/usr/bin/env ruby

root_dir = File.expand_path(File.dirname(__FILE__))
protos_dir = File.join(root_dir, 'protos')
protoc_generated_dir = File.join(protos_dir, 'protoc_generated')
validation_dir = File.join(root_dir, 'validation')

paths_to_load = [root_dir, protos_dir, protoc_generated_dir, validation_dir]
paths_to_load.reverse_each do |path|
	$LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path)
end

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)
require 'yaml'
require 'payment_gateway'
require 'grpc_server_implementation'

# Run Restore Commerce Payment Gateway.
def run_rcpg
  config = YAML.load_file('config.yml')

  kafka_config = config[:kafka]

  kafka_client = Kafka.new(kafka_config[:port], client_id: kafka_config[:client_id])
  # Make producer global since it should be available everywhere.
  $kafka_producer = kafka_client.producer
  
  gprc_config = config[:grpc]
  # The port gRPC server will listen to.
	grpc_port = gprc_config[:port]
  # Amount of seconds to wait for active calls to complete before cancelling them and shutting down the server.
  poll_period = gprc_config[:poll_period]
	
  
  grpc_server = GRPC::RpcServer.new(poll_period: poll_period)
  grpc_server.add_http2_port(grpc_port, :this_port_is_insecure)

  server_implementation = GrpcServer.new(config)

  grpc_server.handle(server_implementation)

  puts "--- Initiating RCPG microservice ---"
  begin
  	grpc_server.run_till_terminated
  rescue Interrupt
    puts "--- Stopping RCPG microservice ---"
  	grpc_server.stop
  	puts "--- RCPG microservice stopped ---"
  end

end

run_rcpg
