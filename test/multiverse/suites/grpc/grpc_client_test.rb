# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'grpc'
require 'newrelic_rpm'

class GrpcTest < Minitest::Test
  include MultiverseHelpers

  def setup
  end

  def teardown
  end

  # Helpers
  TRACE_WITH_NEWRELIC = :@trace_with_newrelic
  HOST = '0.0.0.0:5000'
  CHANNEL = :this_channel_is_insecure

  def basic_grpc_client
    ::GRPC::ClientStub.new(HOST, CHANNEL)
  end

  def assert_trace_with_newrelic_present(grpc_client)
    assert_includes grpc_client.instance_variables, TRACE_WITH_NEWRELIC
  end

  ## Tests
  ## initialize_with_tracing
  def test_initialize_with_tracing_sets_trace_with_new_relic_true_when_host_present
    assert_trace_with_newrelic_present(basic_grpc_client)
    assert basic_grpc_client.instance_variable_get(TRACE_WITH_NEWRELIC)
  end

  def test_initialize_with_tracing_sets_trace_with_new_relic_false_with_blocked_host
    grpc_client = ::GRPC::ClientStub.new('tracing.edge.nr-data.not.a.real.endpoint', CHANNEL)
    assert_trace_with_newrelic_present(grpc_client)
    refute grpc_client.instance_variable_get(TRACE_WITH_NEWRELIC)
  end

  def test_initialize_with_tracing_sets_trace_with_new_relic_without_host
    ::GRPC::ClientStub.stub(:name, 'GRPC::InterceptorRegistry') do
      grpc_client = ::GRPC::ClientStub.new(HOST, CHANNEL)
      refute grpc_client.send(:trace_with_newrelic?)
    end
  end

  # ## issue_request_with_tracing
  # is this testing what we think?
  def test_falsey_trace_with_newrelic_does_not_create_segment
    return_value = 'Dinosaurs looked like big birds'
    grpc_client = basic_grpc_client
    basic_grpc_client.instance_variable_set(TRACE_WITH_NEWRELIC, false)
    # NOTE: by passing nil for metadata, we are guaranteed to encounter an
    #       exception unless the early 'return yield' is hit as desired
    result = basic_grpc_client.issue_request_with_tracing(nil, nil, nil, nil,
      deadline: nil, return_op: nil, parent: nil, credentials: nil,
      metadata: nil) { return_value }
    assert_equal return_value, result
  end

  def test_issue_request_with_tracing_returns_grpc_block
    return_value = 'Dinosaurs looked like big birds'
    grpc_client = basic_grpc_client
    transaction = NewRelic::Agent.instance.stub(:connected?, true) do
      in_transaction('gRPC client test transaction') do |txn|
        grpc_client.instance_variable_set(TRACE_WITH_NEWRELIC, true)
        result = grpc_client.issue_request_with_tracing(
          method,
          nil,
          nil,
          nil,
          deadline: nil,
          return_op: nil,
          parent: nil,
          credentials: nil,
          metadata: metadata
        ) { return_value }
        assert_equal return_value, result
      end
    end
  end

  def test_new_relic_creates_and_finishes_segment
    host = '0.0.0.0:5000'
    method = 'routeguide.RouteGuide/GetFeature'
    metadata = {}
    return_value = 'Dinosaurs looked like big birds'
    transaction = NewRelic::Agent.instance.stub(:connected?, true) do
      in_transaction('gRPC client test transaction') do |txn|
        grpc_client = basic_grpc_client
        grpc_client.instance_variable_set(TRACE_WITH_NEWRELIC, true)
        result = grpc_client.issue_request_with_tracing(
          method,
          nil,
          nil,
          nil,
          deadline: nil,
          return_op: nil,
          parent: nil,
          credentials: nil,
          metadata: metadata
        ) { return_value }
        assert_equal return_value, result
      end
    end
    segment = transaction.segments.last
    # DT
    assert_includes metadata.keys, 'newrelic'
    refute_nil metadata['newrelic']
    assert transaction.distributed_tracer.instance_variable_get(:@distributed_trace_payload_created)
    # Correct name applied
    assert_includes segment.class.name, 'ExternalRequest'
    assert_includes segment.name, host

    # Span attributes
    span = last_span_event
    assert 'gRPC', span[0]['component']
    assert method, span[0]['http.method']
    assert "grpc://#{host}/#{method}", span[2]['http.url']
    # Metrics
    assert_metrics_recorded("External/#{host}/gRPC/#{method}")
  end

  def test_new_relic_captures_segment_error
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', CHANNEL)
    # in_web_transaction? what's the difference?
    transaction = in_transaction('gRPC client test transaction') do |txn|
      grpc_client_stub.instance_variable_set(TRACE_WITH_NEWRELIC, true)
      result = grpc_client_stub.issue_request_with_tracing { raise ::GRPC::Unknown }
    rescue StandardError
      # NOP - Allowing error to be noticed
    end
    binding.irb
    segment = transaction.segments.last
    # was the error noticed by the segment?
    # does it have the error codes and other info we want from the response?
    assert_segment_noticed_error txn, /Memcached\/set(_cas)?$/, simulated_error_class.name, /No server available/i
    assert_transaction_noticed_error txn, simulated_error_class.name
  end

  def test_noticed_error_at_segment_and_txn_on_error
    txn = nil
    exception_class = GRPC::Unknown
    begin
      in_transaction do |ext_txn|
        txn = ext_txn
        ::GRPC::ClientStub.any_instance.stubs(:request_response).raises(exception_class.new)
        grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0:5000', CHANNEL)
        grpc_client_stub.request_response(
          'routeguide.RouteGuide/GetFeature',
          nil,
          nil,
          nil,
          deadline: nil,
          return_op: nil,
          parent: nil,
          credentials: nil,
          metadata: {}
        ) { 'i like traffic lights' }
      end
    rescue StandardError => e
      # NOP -- allowing span and transaction to notice error
    end
    assert_segment_noticed_error txn, /gRPC/, exception_class.name, "2:unknown cause"
    assert_transaction_noticed_error txn, exception_class.name
  end

  def test_noticed_error_only_at_segment_on_error
    txn = nil
    in_transaction do |ext_txn|
      begin
        txn = ext_txn
        simulate_error_response
      rescue StandardError => e
        # NOP -- allowing ONLY span to notice error
      end
    end

    assert_segment_noticed_error txn, /GET$/, timeout_error_class.name, /timeout|couldn't connect/i
    refute_transaction_noticed_error txn, timeout_error_class.name
  end

  def test_formats_a_grpc_uri_from_a_method_string
    host = 'Up!'
    method = 'Russell'
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', CHANNEL)
    grpc_client_stub.instance_variable_set(:@host, host)
    result = grpc_client_stub.send(:method_uri, method)
    assert_equal "grpc://#{host}/#{method}", result
  end

  def test_does_not_format_a_uri_unless_there_is_a_host
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', CHANNEL)
    grpc_client_stub.remove_instance_variable(:@host)
    assert_nil grpc_client_stub.send(:method_uri, 'a method')
  end

  def test_does_not_format_a_uri_unless_there_is_a_method
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', CHANNEL)
    grpc_client_stub.instance_variable_set(:@host, 'a host')
    assert_nil grpc_client_stub.send(:method_uri, nil)
  end

  # test_issue_request_with_tracing_captures_error

  # test_issue_request_with_tracing_adds_request_headers

  # test_issue_request_with_tracing_creates_external_request_segment

  # test_method_uri_uses_correct_format

  # test_method_has_cleaned_name

  # test_request_not_traced_if_class_interceptor

  # test_bidi_streaming
  # test_request_response
  # test_server_streaming
  # test_client_streaming
end
